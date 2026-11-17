import Foundation
@main struct NativeLearningTests {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("learning.json")
        let video: [String:Any] = ["id":"test", "title":"Saved transcript", "youtubeId":"WsdcF7EEvhM", "text":"Learning begins with curiosity. Every discovery matters.", "segments":[["start":2.0,"text":"Learning begins"], ["start":4.0,"text":"with curiosity."], ["start":7.0,"text":"Every discovery matters."]], "customMetadata":"preserved"]
        let words: [[String:Any]] = [["word":"illumination", "definition":"한글 뜻을 찾지 못했습니다. 잠시 후 다시 열어주세요.", "status":"learning"]]
        func json(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
        let snapshot = ["wa-videos": try json([video]), "wa-saved": try json(words), "wa-known-words":try json(["familiar"]), "wa-profile":try json(["discovery":["lookups":3]]), "wa-korean-meanings":try json(["cachedexample":["", "", "저장한 한글 뜻"]])]
        let initial: [String:Any] = ["version":1, "legacy":snapshot, "wa-videos":[video], "wa-saved":words, "wa-known-words":["familiar"], "wa-profile":["discovery":["lookups":3]], "wa-korean-meanings":["cachedexample":["", "", "저장한 한글 뜻"]]]
        try JSONSerialization.data(withJSONObject: initial).write(to: file)
        let store = NativeLearningStore(location: file)
        precondition(store.loaded && store.error == nil && store.videos.count == 1 && store.words.count == 1)
        precondition(NSDictionary(dictionary: store.videos[0].data).isEqual(to: video))
        let disk = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String:Any]
        precondition(disk["legacy"] as! [String:String] == snapshot)
        let reopened = NativeLearningStore(location: file)
        precondition(reopened.loaded && reopened.known.contains("familiar"))
        let lines = reopened.lines(reopened.videos[0])
        precondition(lines.count == 1 && lines[0].text == "Learning begins with curiosity. Every discovery matters." && lines[0].start == 2)
        let shorter = reopened.lines(reopened.videos[0], layoutKey: "short", fits: { text, _ in text.count <= 38 })
        precondition(shorter.count == 2 && shorter[0].start == 2 && shorter[1].start == 7)
        let turns = LearningVideo(data: ["id":"turns", "text":"First speaker. Second speaker.", "segments":[["start":0.0,"text":"First speaker.","speaker":"a"],["start":3.0,"text":"Second speaker.","speaker":"b"]]])
        let turnLines = reopened.lines(turns)
        precondition(turnLines.count == 2 && turnLines[1].start == 3)
        let split = LearningVideo(data:["id":"split", "text":"one two three four five six seven eight", "segments":[["start":0.0, "duration":8.0, "text":"one two three four five six seven eight"]]])
        let pieces = reopened.lines(split, layoutKey: "narrow", fits: { text, _ in text.count <= 16 })
        precondition(pieces.count > 1 && pieces.dropFirst().allSatisfy { $0.estimated && $0.start! > 0 })
        precondition(reopened.words[0].definition.isEmpty)
        let resolved = await reopened.meaning("illumination", online: false)
        precondition(!resolved.definition.isEmpty && !resolved.definition.contains("찾지 못"))
        let cached = await reopened.meaning("cachedexample", online: false)
        precondition(cached.definition == "저장한 한글 뜻")
        let addiction = await reopened.meaning("addiction", online: false)
        precondition(addiction.definition.contains("중독"))
        let missing = await reopened.meaning("nonexistentzzword", online: false)
        precondition(missing.definition.isEmpty)
        reopened.save(addiction); reopened.mark("addiction", known: true)
        let again = NativeLearningStore(location: file)
        precondition(again.words.contains { $0.id == "addiction" && $0.known })
        try again.importBackup(again.backup())
        precondition(NativeLearningStore.youtubeID("https://youtu.be/WsdcF7EEvhM") == "WsdcF7EEvhM")
        precondition(NativeLearningStore.youtubeID("https://evil.test/?v=WsdcF7EEvhM") == nil)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var basic = ""
        for name in ["basic-vocabulary.js", "extended-basic.js"] {
            let source = try String(contentsOf: root.appendingPathComponent("dictionary/\(name)"), encoding: .utf8)
            basic += source.components(separatedBy: "\"")[1] + " "
        }
        let excluded = again.previewWords(LearningVideo(data:["id":"basic", "text":basic + " WE'RE won't we’re let's world's far-away"]))
        precondition(excluded.isEmpty, "Basic vocabulary leaked: \(excluded.prefix(5))")
        let pronouns = again.previewWords(LearningVideo(data:["id":"pronouns", "text":"themselves anybody nobody yours ours whom zyzzyva"]))
        precondition(pronouns == ["zyzzyva"], "Pronouns leaked: \(pronouns)")
        precondition(again.previewWords(LearningVideo(data:["id":"unknown", "text":"zyzzyva 한글 addiction"])) == ["zyzzyva"])
        try Data("corrupt".utf8).write(to: file)
        let corrupt = NativeLearningStore(location: file)
        precondition(!corrupt.loaded && !corrupt.needsMigration && corrupt.error != nil)
        let retained = try String(contentsOf: file, encoding: .utf8); precondition(retained == "corrupt")
        let reference = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String:Any]]
        for item in reference {
            let video = LearningVideo(data: item["video"] as! [String:Any])
            let limit = item["limit"] as! Int
            let expected = item["expected"] as! [[String:Any]]
            let actual = reopened.lines(video, layoutKey: "parity-\(limit)", fits: { text, _ in text.utf16.count <= limit })
            precondition(actual.count == expected.count, "Group count differs: \(video.id), limit \(limit)")
            for (line, target) in zip(actual, expected) {
                precondition(line.text == target["text"] as! String)
                precondition(abs(line.start! - (target["start"] as! Double)) < 0.00001)
                precondition(line.estimated == target["estimated"] as! Bool && line.sharedTimestamp == target["shared"] as! Bool)
            }
        }
        print("PASS: native caption text, timestamps, turn breaks and estimated timing match the previous JS reader in all 15 reference cases")
        print("PASS: persistence and original preservation; offline transcript sentences/timing; Korean cache and missing meanings; save/known/backup; all bundled basic forms and contractions excluded; URL validation; corrupt-file protection")
    }
}
