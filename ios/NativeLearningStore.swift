import Foundation
import Combine
import AVFoundation
import SwiftUI
import StoreKit

struct LearningVideo: Identifiable {
    var data: [String: Any]
    var id: String { data["id"] as? String ?? "" }
    var title: String { data["title"] as? String ?? "저장한 자막" }
    var text: String { data["text"] as? String ?? "" }
    var youtubeID: String? { data["youtubeId"] as? String }
    var channel: String { data["channel"] as? String ?? "내 자막" }
    var segments: [[String: Any]] { data["segments"] as? [[String: Any]] ?? [] }
}
struct LearningWord: Identifiable {
    var data: [String: Any]
    var id: String { data["word"] as? String ?? "" }
    var definition: String { let value = data["definition"] as? String ?? ""; return NativeLearningStore.isMeaning(value) ? value : "" }
    var known: Bool { data["status"] as? String == "known" }
}
struct TranscriptLine: Identifiable {
    let id: Int
    let text: String
    let start: Double?
    var estimated = false
    var sharedTimestamp = false
    var lastSentence = ""
}
struct SavedSentence: Identifiable {
    var data: [String: Any]
    var id: String { data["id"] as? String ?? "" }
    var text: String { data["text"] as? String ?? "" }
    var source: String { data["source"] as? String ?? "" }
    var added: Double { data["added"] as? Double ?? 0 }
    var start: Double? { data["start"] as? Double }
}
struct WordMeaning: Identifiable {
    let id: String
    var phonetic = ""
    var part = ""
    var definition = ""
}

final class SpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let callback = onFinish; onFinish = nil
        DispatchQueue.main.async { callback?() }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let callback = onFinish; onFinish = nil
        DispatchQueue.main.async { callback?() }
    }
}

@MainActor
final class NativeLearningStore: ObservableObject {
    @Published var videos: [LearningVideo] = []
    @Published var words: [LearningWord] = []
    @Published var known: Set<String> = []
    @Published var sentences: [SavedSentence] = []
    @Published var loaded = false
    @Published var error: String?
    @Published var sharedURL = ""
    @Published var billing: [String: Any] = [:]
    private var document: [String: Any] = [:]
    private let location: URL
    private let dictionary = OfflineDictionaryStore()
    private let subscription = WordAheadSubscriptionService()
    private let speaker = AVSpeechSynthesizer()
    private let speakerCoordinator = SpeechCoordinator()
    private var meaningCache: [String: WordMeaning] = [:]
    private var lineCache: [String: (text: String, lines: [TranscriptLine])] = [:]
    private var transactionTask: Task<Void, Never>?
    private var basic: Set<String> = []

    init(location: URL? = nil) {
        self.location = location ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WordAheadNative/learning.json")
        speaker.delegate = speakerCoordinator
        try? AVAudioSession.sharedInstance().setActive(true)
        Task { [dictionary] in await dictionary.warmUp() }
        if FileManager.default.fileExists(atPath: self.location.path) {
            do {
                let data = try Data(contentsOf: self.location)
                document = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                guard document["version"] as? Int == 1 else { throw CocoaError(.fileReadCorruptFile) }
                restore(); loaded = true
            } catch { self.error = "저장 데이터를 열 수 없습니다. 원본을 보존했습니다. \(error.localizedDescription)" }
        } else {
            document = ["version": 1, "wa-videos": [["id": "native-sample", "title": "오늘의 작은 발견", "channel": "WordAhead 연습 자막", "text": "Learning a language begins with curiosity. Every small discovery brings us closer to understanding. Take your time and enjoy the journey."]]]
            restore(); loaded = true
            try? write()
        }
        if let root = Bundle.main.url(forResource: "Web", withExtension: nil) {
            for file in ["basic-vocabulary.js", "extended-basic.js"] {
                if let source = try? String(contentsOf: root.appendingPathComponent("dictionary/\(file)")),
                   let pattern = try? NSRegularExpression(pattern: "\"([a-zA-Z '-]{100,})\""),
                   let match = pattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                   let range = Range(match.range(at: 1), in: source) {
                    basic.formUnion(source[range].split(separator: " ").map(String.init))
                }
            }
        }
        transactionTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshBilling()
            }
        }
    }
    deinit { transactionTask?.cancel() }
    var needsMigration: Bool { !loaded && error == nil && !FileManager.default.fileExists(atPath: location.path) }
    func migrate(_ snapshot: [String: String]) {
        guard !loaded else { return }
        do {
            document = ["version": 1, "legacy": snapshot]
            for key in ["wa-videos", "wa-saved", "wa-known-words", "wa-profile", "wa-korean-meanings"] {
                if let value = snapshot[key], let bytes = value.data(using: .utf8) {
                    document[key] = try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
                }
            }
            if document["wa-videos"] == nil {
                document["wa-videos"] = [["id": "native-sample", "title": "오늘의 작은 발견", "channel": "WordAhead 연습 자막", "text": "Learning a language begins with curiosity. Every small discovery brings us closer to understanding. Take your time and enjoy the journey."]]
            }
            if let size = snapshot["wa-font-size"].flatMap(Double.init) { UserDefaults.standard.set(min(30, max(14, size)), forKey: "nativeReaderFontSize") }
            if let size = snapshot["wa-preview-font-size"].flatMap(Double.init) { UserDefaults.standard.set(min(28, max(14, size)), forKey: "nativePreviewFontSize") }
            if let dark = snapshot["wa-dark-mode"] { UserDefaults.standard.set(dark == "1" ? "dark" : "light", forKey: "nativeAppearance") }
            if let language = snapshot["wa-app-language"] { UserDefaults.standard.set(language, forKey: "nativeAppLanguage") }
            try write(); restore(); loaded = true
        } catch { self.error = "기존 데이터 이전에 실패했습니다. 원본 데이터는 유지됩니다. \(error.localizedDescription)" }
    }
    private func restore() {
        videos = (document["wa-videos"] as? [[String: Any]] ?? []).filter { $0["id"] is String }.map { LearningVideo(data: $0) }
        words = (document["wa-saved"] as? [[String: Any]] ?? []).filter { $0["word"] is String }.map { LearningWord(data: $0) }
        known = Set(document["wa-known-words"] as? [String] ?? []).union(words.filter(\.known).map(\.id))
        sentences = (document["wa-sentences"] as? [[String: Any]] ?? []).filter { $0["id"] is String }.map { SavedSentence(data: $0) }
    }
    private func write() throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        try data.write(to: location, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func persist() {
        document["wa-videos"] = videos.map(\.data)
        document["wa-saved"] = words.map(\.data)
        document["wa-known-words"] = known.sorted()
        document["wa-sentences"] = sentences.map(\.data)
        do { try write() } catch { self.error = "저장하지 못했습니다: \(error.localizedDescription)" }
    }
    func save(_ meaning: WordMeaning, context: String = "", source: String = "") {
        if let index = words.firstIndex(where: { $0.id == meaning.id }) {
            words[index].data["definition"] = meaning.definition
        } else {
            words.insert(LearningWord(data: ["word": meaning.id, "display": meaning.id, "definition": meaning.definition, "phonetic": meaning.phonetic, "part": meaning.part, "status": "learning", "context": context, "source": source, "added": Date().timeIntervalSince1970 * 1000]), at: 0)
        }
        persist(); Haptic.success()
    }
    func mark(_ word: String, known value: Bool) {
        if value { known.insert(word) } else { known.remove(word) }
        if let index = words.firstIndex(where: { $0.id == word }) { words[index].data["status"] = value ? "known" : "learning" }
        persist()
    }
    func savePreviewWords(_ selected: [String], video: LearningVideo) async {
        for word in selected.reversed() {
            if !words.contains(where: { $0.id == word }) {
                let value = await meaning(word, online: true)
                save(value, context: video.text, source: video.title)
            }
            mark(word, known: true)
        }
    }
    static func sentenceID(_ text: String) -> String { text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") }
    func isSentenceSaved(_ text: String) -> Bool { let id = Self.sentenceID(text); return sentences.contains { $0.id == id } }
    @discardableResult func toggleSentence(_ text: String, source: String, start: Double? = nil, videoID: String = "") -> Bool {
        let id = Self.sentenceID(text)
        if let index = sentences.firstIndex(where: { $0.id == id }) { sentences.remove(at: index); persist(); return false }
        var data: [String: Any] = ["id": id, "text": text, "source": source, "videoId": videoID, "added": Date().timeIntervalSince1970 * 1000]
        if let start { data["start"] = start }
        sentences.insert(SavedSentence(data: data), at: 0)
        persist(); Haptic.success(); return true
    }
    func savedSentences(in line: String) -> [String] { sentences.map(\.text).filter { line.contains($0) || $0.contains(line) } }
    func removeSentences(in line: String) { let ids = Set(savedSentences(in: line).map(Self.sentenceID)); sentences.removeAll { ids.contains($0.id) }; persist() }
    // Expand a dragged fragment to the whole sentence (previous terminator to next terminator), even across caption groups.
    func fullSentence(_ fragment: String, in video: LearningVideo) -> String {
        func normalize(_ value: String) -> String { value.replacingOccurrences(of: ">>", with: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
        let text = normalize(video.text), part = normalize(fragment)
        guard !part.isEmpty, let found = text.range(of: part), let regex = try? NSRegularExpression(pattern: "[.!?][\"'”’)\\]]*(?=\\s|$)") else { return part }
        let whole = text as NSString, from = NSRange(found, in: text)
        let abbreviation = try? NSRegularExpression(pattern: "(?:\\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|St|vs|etc)|\\b[A-Z])\\.$", options: .caseInsensitive)
        let ends = regex.matches(in: text, range: NSRange(location: 0, length: whole.length)).map { NSMaxRange($0.range) }.filter { end in
            let head = whole.substring(to: end)
            return abbreviation?.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)) == nil
        }
        var start = ends.last { $0 <= from.location } ?? 0
        let finish = ends.first { $0 >= NSMaxRange(from) } ?? whole.length
        while start < finish, let scalar = Unicode.Scalar(whole.character(at: start)), CharacterSet.whitespaces.contains(scalar) { start += 1 }
        let result = whole.substring(with: NSRange(location: start, length: max(0, finish - start))).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.count > 500 || result.isEmpty ? part : result
    }
    func removeSentence(_ id: String) { sentences.removeAll { $0.id == id }; persist() }
    private var translations: [String: String] = UserDefaults.standard.dictionary(forKey: "WordAheadSentenceTranslations") as? [String: String] ?? [:]
    func cachedTranslation(_ sentence: String) -> String? { translations[Self.language + ":" + Self.sentenceID(sentence)] }
    func translation(_ sentence: String) async -> String? {
        let language = Self.language
        guard language != "en" else { return nil }
        let key = language + ":" + Self.sentenceID(sentence)
        if let cached = translations[key] { return cached }
        let query = String(sentence.prefix(480))
        let codes = ["zh-Hans": "zh-CN", "es-MX": "es", "fr-FR": "fr"]
        guard var components = URLComponents(string: "https://api.mymemory.translated.net/get") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "langpair", value: "en|" + (codes[language] ?? language))]
        guard let address = components.url?.absoluteString, let response = try? await dictionary.handle(["action": "online", "url": address]), let text = response["json"] as? String, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], (object["responseStatus"] as? Int ?? Int(object["responseStatus"] as? String ?? "") ?? 200) == 200,
              let body = object["responseData"] as? [String: Any], let translated = (body["translatedText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !translated.isEmpty,
              !translated.uppercased().contains("MYMEMORY WARNING"), translated.caseInsensitiveCompare(query) != .orderedSame else { return nil }
        if translations.count > 3000 { translations = [:] }
        translations[key] = translated
        UserDefaults.standard.set(translations, forKey: "WordAheadSentenceTranslations")
        return translated
    }
    func removeWord(_ word: String) { words.removeAll { $0.id == word }; persist() }
    func removeVideo(_ id: String) { videos.removeAll { $0.id == id }; persist() }
    func addTranscript(title: String, text: String, youtubeID: String? = nil) -> String {
        let id = youtubeID.map { "yt-\($0)" } ?? UUID().uuidString
        var data: [String: Any] = ["id": id, "title": title.isEmpty ? "직접 입력한 자막" : title, "channel": "내 자막", "text": text]
        if let youtubeID { data["youtubeId"] = youtubeID }
        videos.removeAll { $0.id == id }; videos.insert(LearningVideo(data: data), at: 0); persist()
        return id
    }
    static func youtubeID(_ value: String) -> String? {
        guard let url = URL(string: value), let host = url.host?.lowercased(), ["youtu.be", "youtube.com", "www.youtube.com", "m.youtube.com"].contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let id = host == "youtu.be" ? parts.first : URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value ?? (["shorts", "embed", "live"].contains(parts.first ?? "") ? parts.last : nil)
        guard let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        return id
    }
    func handleSharedURL(_ value: String) {
        guard let id = Self.youtubeID(value) else { return }
        let videoID = "yt-\(id)"
        if !videos.contains(where: { $0.youtubeID == id }) {
            let data: [String: Any] = [
                "id": videoID,
                "youtubeId": id,
                "title": "YouTube 자막 수집 중…",
                "channel": "YouTube",
                "text": "",
                "segments": []
            ]
            videos.insert(LearningVideo(data: data), at: 0)
            persist()
        }
        sharedURL = ""
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.importYouTube(value)
            } catch {
                if let video = self.videos.first(where: { $0.id == videoID }), video.text.isEmpty {
                    self.removeVideo(videoID)
                }
                self.error = error.localizedDescription
            }
        }
    }
    func importYouTube(_ value: String) async throws -> String {
        guard let id = Self.youtubeID(value) else { throw CaptionFailure.unavailable("올바른 YouTube 영상 주소를 입력하세요.") }
        if let existing = videos.first(where: { $0.youtubeID == id && !$0.text.isEmpty }) { return existing.id }
        guard await subscription.beginAnalysis(id) else { throw CaptionFailure.unavailable("오늘의 무료 분석을 모두 사용했습니다. 설정에서 Plus를 확인하세요.") }
        do {
            let response = try await CaptionFetcher.fetch(id)
            let segments = response["segments"] as? [[String: Any]] ?? []
            var data = videos.first(where: { $0.youtubeID == id })?.data ?? [:]
            data.merge(["id": "yt-\(id)", "youtubeId": id, "title": response["title"] as? String ?? "YouTube", "channel": response["channel"] as? String ?? "YouTube", "segments": segments, "text": segments.compactMap { $0["text"] as? String }.joined(separator: "\n")]) { _, new in new }
            let video = LearningVideo(data: data)
            videos.removeAll { $0.id == video.id }; videos.insert(video, at: 0); persist()
            await subscription.finishAnalysis(id, success: true); await refreshBilling()
            return video.id
        } catch { await subscription.finishAnalysis(id, success: false); throw error }
    }
    func speak(_ word: String, onFinish: (() -> Void)? = nil) {
        speakerCoordinator.onFinish = onFinish
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: word); utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speaker.speak(utterance)
    }
    static func key(_ raw: String) -> String { raw.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted) }
    nonisolated static var language: String { UserDefaults.standard.string(forKey: "nativeAppLanguage") ?? "ko" }
    nonisolated static var meaningCacheKey: String { language == "ko" ? "wa-korean-meanings" : "wa-meanings-" + language }
    nonisolated static func isMeaning(_ value: String) -> Bool {
        let hangul = value.range(of: "[가-힣]", options: .regularExpression) != nil
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (language == "ko" ? hangul : !hangul) && !["한글 뜻을 찾지 못", "뜻을 확인하는 중", "사전에서 뜻을 찾는 중", "저장된 뜻 확인 중", "오프라인 사전 미수록", "뜻을 조회하는 중"].contains(where: value.contains)
    }
    func quickMeaning(_ raw: String) -> WordMeaning? {
        let key = Self.key(raw)
        if let cached = meaningCache[Self.language + ":" + key] { return cached }
        if let entry = words.first(where: { $0.id == key && Self.isMeaning($0.definition) }) {
            return WordMeaning(id: key, phonetic: entry.data["phonetic"] as? String ?? "", part: entry.data["part"] as? String ?? "", definition: entry.definition)
        }
        if let cached = document[Self.meaningCacheKey] as? [String: Any], let entry = cached[key] as? [String], entry.count > 2, Self.isMeaning(entry[2]) {
            return WordMeaning(id: key, phonetic: entry[0], part: entry[1], definition: entry[2])
        }
        return nil
    }
    func meaning(_ raw: String, online: Bool = true) async -> WordMeaning {
        let key = Self.key(raw)
        if online {
            var profiles = document["wa-profile"] as? [String: [String: Any]] ?? [:]
            var profile = profiles[key] ?? [:]; profile["lookups"] = (profile["lookups"] as? Int ?? 0) + 1; profiles[key] = profile
            document["wa-profile"] = profiles
        }
        if let cached = meaningCache[Self.language + ":" + key] { return cached }
        if let entry = words.first(where: { $0.id == key && Self.isMeaning($0.definition) }) {
            return WordMeaning(id: key, phonetic: entry.data["phonetic"] as? String ?? "", part: entry.data["part"] as? String ?? "", definition: entry.definition)
        }
        if let cached = document[Self.meaningCacheKey] as? [String: Any], let entry = cached[key] as? [String], entry.count > 2, Self.isMeaning(entry[2]) {
            return WordMeaning(id: key, phonetic: entry[0], part: entry[1], definition: entry[2])
        }
        if Self.language != "ko" {
            var phonetic = "", part = ""
            if let response = try? await dictionary.handle(["action": "lookup", "word": key]), let entry = response["entry"] as? [String], entry.count > 1 { phonetic = entry[0]; part = entry[1] }
            guard online, let translated = await onlineMeaning(key, language: Self.language), Self.isMeaning(translated.definition) else { return WordMeaning(id: key) }
            let result = WordMeaning(id: key, phonetic: phonetic.isEmpty ? translated.phonetic : phonetic, part: part.isEmpty ? translated.part : part, definition: translated.definition)
            meaningCache[Self.language + ":" + key] = result
            var cache = document[Self.meaningCacheKey] as? [String: Any] ?? [:]
            cache[key] = [result.phonetic, result.part, result.definition]; document[Self.meaningCacheKey] = cache; persist(); return result
        }
        var candidates = [key]
        if key.hasSuffix("ies") { candidates.append(String(key.dropLast(3)) + "y") }
        for suffix in ["ing", "ed", "es", "s"] where key.count > suffix.count + 2 && key.hasSuffix(suffix) {
            let stem = String(key.dropLast(suffix.count)); candidates += [stem, stem + "e"]
            if stem.count > 2 && stem.last == stem.dropLast().last { candidates.append(String(stem.dropLast())) }
        }
        for candidate in candidates {
            if let response = try? await dictionary.handle(["action": "lookup", "word": candidate]), let entry = response["entry"] as? [String], entry.count > 2, Self.isMeaning(entry[2]) {
                let result = WordMeaning(id: key, phonetic: entry[0], part: entry[1], definition: entry[2]); meaningCache[Self.language + ":" + key] = result; return result
            }
        }
        if online, let url = URL(string: "https://api.mymemory.translated.net/get") {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "q", value: key), URLQueryItem(name: "langpair", value: "en|ko")]
            if let response = try? await dictionary.handle(["action": "online", "url": components.url!.absoluteString]), let text = response["json"] as? String, let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let body = object["responseData"] as? [String: Any], let translated = body["translatedText"] as? String, Self.isMeaning(translated) {
                let result = WordMeaning(id: key, definition: translated); meaningCache[Self.language + ":" + key] = result
                var cache = document[Self.meaningCacheKey] as? [String: Any] ?? [:]
                cache[key] = ["", "", translated]; document[Self.meaningCacheKey] = cache; persist(); return result
            }
        }
        return WordMeaning(id: key)
    }
    private func onlineMeaning(_ word: String, language: String) async -> WordMeaning? {
        if language == "en" {
            guard let url = URL(string: "https://api.dictionaryapi.dev/v2/entries/en/" + (word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word)),
                  let response = try? await dictionary.handle(["action": "online", "url": url.absoluteString]), let text = response["json"] as? String, let data = text.data(using: .utf8),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = entries.first else { return nil }
            let meanings = first["meanings"] as? [[String: Any]] ?? []
            let definitions = meanings.prefix(3).compactMap { ($0["definitions"] as? [[String: Any]])?.first?["definition"] as? String }
            let part = (meanings.first?["partOfSpeech"] as? String) ?? ""
            return definitions.isEmpty ? nil : WordMeaning(id: word, phonetic: first["phonetic"] as? String ?? "", part: part.uppercased(), definition: definitions.joined(separator: "; "))
        }
        let codes = ["zh-Hans": "zh-CN", "es-MX": "es", "fr-FR": "fr"]
        guard var components = URLComponents(string: "https://api.mymemory.translated.net/get") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: word), URLQueryItem(name: "langpair", value: "en|" + (codes[language] ?? language))]
        guard let address = components.url?.absoluteString, let response = try? await dictionary.handle(["action": "online", "url": address]), let text = response["json"] as? String, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let body = object["responseData"] as? [String: Any], let translated = body["translatedText"] as? String else { return nil }
        return WordMeaning(id: word, definition: translated)
    }
    private func isBasic(_ word: String) -> Bool {
        if basic.contains(word) { return true }
        var stems: [String] = []
        if word.hasSuffix("ies"), word.count > 4 { stems.append(String(word.dropLast(3)) + "y") }
        for suffix in ["ing", "ed", "es", "s", "ly", "er", "est", "d"] where word.count > suffix.count + 2 && word.hasSuffix(suffix) {
            let stem = String(word.dropLast(suffix.count)); stems += [stem, stem + "e"]
            if stem.count > 2 && stem.last == stem.dropLast().last { stems.append(String(stem.dropLast())) }
        }
        return stems.contains { basic.contains($0) }
    }
    func previewWords(_ video: LearningVideo) -> [String] {
        let tokens = video.text.lowercased().replacingOccurrences(of: "’", with: "'").components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).inverted).map(Self.key).filter { $0.count > 2 }
        let counts = Dictionary(tokens.map { ($0, 1) }, uniquingKeysWith: +)
        let profiles = document["wa-profile"] as? [String: [String: Any]] ?? [:]
        func score(_ word: String) -> Int {
            let learning = words.contains { $0.id == word && !$0.known }
            return (learning ? 20 : 0) + min(6, (profiles[word]?["lookups"] as? Int ?? 0) * 2) + min(3, counts[word] ?? 0) + min(12, word.count)
        }
        let pronouns: Set<String> = [
            "i", "me", "my", "mine", "myself", "you", "your", "yours", "yourself", "yourselves",
            "he", "him", "his", "himself", "she", "her", "hers", "herself", "it", "its", "itself",
            "we", "us", "our", "ours", "ourselves", "they", "them", "their", "theirs", "themselves",
            "this", "that", "these", "those", "who", "whom", "whose", "which", "what",
            "anybody", "anyone", "anything", "everybody", "everyone", "everything", "nobody", "noone", "nothing",
            "somebody", "someone", "something", "each", "either", "neither", "one", "ones", "other", "others", "another"
        ]
        return Set(tokens).filter { word in
            let base = word.hasSuffix("'s") ? String(word.dropLast(2)) : word
            let contraction = word.range(of: "^(?:(?:i|you|he|she|it|we|they|that|there|here|who|what|where|when|how)'(?:m|re|s|ve|ll|d)|(?:is|are|was|were|have|has|had|do|does|did|ca|could|wo|would|sha|should|must|need|might|dare)n't|let's)$", options: .regularExpression) != nil
            return word.range(of: "^[a-z][a-z'-]*$", options: .regularExpression) != nil && !pronouns.contains(base) && !isBasic(base) && !contraction && !known.contains(word) && !(base.contains("-") && base.split(separator: "-").allSatisfy { isBasic(String($0)) })
        }.sorted { score($0) == score($1) ? $0 < $1 : score($0) > score($1) }
    }
    // Keep the previous reader's sentence/turn boundaries and five-line grouping.
    func lines(_ video: LearningVideo, layoutKey: String = "default", fits: ((String, Double?) -> Bool)? = nil) -> [TranscriptLine] {
        let cacheKey = video.id + ":" + layoutKey
        if let cached = lineCache[cacheKey], cached.text == video.text { return cached.lines }
        struct Cue {
            var text: String
            var start: Double
            var end: Double?
            var speaker: String
            var turn: Bool
            var timings: [(text: String, start: Double)]
            var estimated = false
            var shared = false
        }
        func clean(_ text: String) -> String { text.replacingOccurrences(of: ">>", with: "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
        func boundary(_ previous: Cue, _ next: Cue) -> Bool { next.turn || (!previous.speaker.isEmpty && !next.speaker.isEmpty && previous.speaker != next.speaker) }
        var cues: [Cue] = []
        for segment in video.segments {
            guard let base = segment["start"] as? Double, base.isFinite, base >= 0 else { continue }
            let sourceParts = segment["parts"] as? [[String: Any]]
            let parts = sourceParts?.isEmpty == false ? sourceParts! : [["text": segment["rawText"] ?? segment["text"] ?? "", "start": base]]
            let duration = segment["duration"] as? Double ?? 0
            let end = (segment["end"] as? Double).flatMap { $0 > base ? $0 : nil } ?? (duration > 0 ? base + duration : nil)
            var pending: Cue?
            var turn = segment["turnStart"] as? Bool ?? false
            func flush() { if var value = pending { value.text = clean(value.text); if !value.text.isEmpty { cues.append(value) } }; pending = nil }
            for part in parts {
                var raw = part["text"] as? String ?? ""
                var speaker = String(describing: part["speakerId"] ?? part["speaker"] ?? segment["speakerId"] ?? segment["speaker"] ?? "")
                if let voice = raw.range(of: "^\\s*<v(?:\\.[^\\s>]*)?\\s+([^>]+)>", options: [.regularExpression, .caseInsensitive]) {
                    speaker = String(raw[voice]).replacingOccurrences(of: "^.*?\\s+|>$", with: "", options: .regularExpression)
                    raw.removeSubrange(voice); raw = raw.replacingOccurrences(of: "</v>", with: "", options: .caseInsensitive)
                }
                let value = part["start"] as? Double ?? base
                let start = value.isFinite && value >= 0 ? value : base
                if part["turnStart"] as? Bool == true || (pending != nil && !speaker.isEmpty && !pending!.speaker.isEmpty && speaker != pending!.speaker) { flush(); turn = true }
                for (index, chunk) in raw.components(separatedBy: ">>").enumerated() {
                    if index > 0 { flush(); turn = true }
                    if chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    if pending == nil { pending = Cue(text: "", start: start, end: end, speaker: speaker, turn: turn, timings: []) }
                    pending!.text += chunk; pending!.timings.append((chunk, start)); turn = false
                }
            }
            flush()
        }
        cues.sort { $0.start < $1.start }
        var merged: [Cue] = []
        for cue in cues {
            if let last = merged.last, last.start == cue.start, !boundary(last, cue) {
                merged[merged.count - 1].text += " " + cue.text
                merged[merged.count - 1].timings += cue.timings
                if let end = cue.end { merged[merged.count - 1].end = end }
            } else { merged.append(cue) }
        }
        let within = fits ?? { text, _ in text.count <= 210 }
        var groups: [Cue] = [], pending: Cue?, sentence: [Cue] = [], pendingSentences = 0
        func flush() { if let pending { groups.append(pending) }; pending = nil; pendingSentences = 0 }
        func finishSentence() {
            guard !sentence.isEmpty else { return }
            let text = sentence.map(\.text).joined(separator: " ")
            if pending != nil && pendingSentences >= 3 { flush() }
            if let value = pending, !within(value.text + " " + text, value.start) { flush() }
            for piece in sentence {
                if let value = pending, !within(value.text + " " + piece.text, value.start) { flush() }
                if pending == nil { pending = piece } else { pending!.text += " " + piece.text }
            }
            pendingSentences += 1; sentence = []
        }
        for (index, cue) in merged.enumerated() {
            if let previous = sentence.last ?? pending, boundary(previous, cue) { finishSentence(); flush() }
            let words = cue.text.split(whereSeparator: \.isWhitespace).map(String.init)
            let times: [Double?] = cue.timings.flatMap { part in part.text.split(whereSeparator: \.isWhitespace).enumerated().map { $0.offset == 0 ? part.start : nil } }
            let next = index + 1 < merged.count ? merged[index + 1].start : nil
            let end = [cue.end, next].compactMap { $0 }.filter { $0 > cue.start }.min()
            for (offset, word) in words.enumerated() {
                let candidate = times.count == words.count ? times[offset] : nil
                let exact = offset == 0 ? cue.start : candidate.flatMap { $0 > cue.start ? $0 : nil }
                let estimated = exact == nil && end != nil
                var piece = cue
                piece.text = word; piece.turn = offset == 0 && cue.turn
                piece.start = exact ?? end.map { cue.start + ($0 - cue.start) * Double(offset) / Double(words.count) } ?? cue.start
                piece.estimated = estimated; piece.shared = offset > 0 && exact == nil && !estimated
                sentence.append(piece)
                let text = sentence.map(\.text).joined(separator: " ")
                if text.range(of: "[.!?][\"'”’\\])]*$", options: .regularExpression) != nil && text.range(of: "(?:\\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|St|vs|etc)|\\b[A-Z])\\.$", options: [.regularExpression, .caseInsensitive]) == nil { finishSentence() }
            }
        }
        finishSentence(); flush()
        var lines: [TranscriptLine]
        if merged.isEmpty {
            lines = []
            video.text.enumerateSubstrings(in: video.text.startIndex..., options: .bySentences) { value, _, _, _ in
                if let value, !clean(value).isEmpty { lines.append(TranscriptLine(id: lines.count, text: clean(value), start: nil)) }
            }
        } else {
            lines = groups.sorted { $0.start < $1.start }.enumerated().map { TranscriptLine(id: $0.offset, text: $0.element.text, start: $0.element.start, estimated: $0.element.estimated, sharedTimestamp: $0.element.shared, lastSentence: Self.lastSentence($0.element.text)) }
        }
        lineCache[cacheKey] = (video.text, lines)
        return lines
    }
    static func lastSentence(_ text: String) -> String {
        var last = text
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { value, _, _, _ in
            if let value, value.trimmingCharacters(in: .whitespacesAndNewlines).count > 1 { last = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return last
    }
    func position(_ id: String) -> Double { (document["nativePositions"] as? [String: Double])?[id] ?? 0 }
    func setPosition(_ id: String, time: Double) {
        var positions = document["nativePositions"] as? [String: Double] ?? [:]; positions[id] = time; document["nativePositions"] = positions
        persist()
    }
    func refreshBilling() async { if let value = try? await subscription.handle(["action": "status"]) { billing = value } }
    func purchase(_ action: String) async {
        do {
            billing = try await subscription.handle(["action": action])
            if billing["purchase"] as? String == "pending" { error = "구매 승인 대기 중입니다. 승인 후 이용할 수 있습니다." }
        } catch { self.error = "구매 처리를 완료하지 못했습니다: \(error.localizedDescription)" }
    }
    func reset() {
        videos = []; words = []; known = []; sentences = []; document = ["version": 1]; meaningCache = [:]; lineCache = [:]; persist()
        Task { await subscription.resetLearningHistory() }
    }
    func backup() throws -> Data { try JSONSerialization.data(withJSONObject: ["app": "WordAhead", "version": 1, "knownWords": known.sorted()], options: [.sortedKeys]) }
    func importBackup(_ data: Data) throws {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["app"] as? String == "WordAhead", value["version"] as? Int == 1, let list = value["knownWords"] as? [String], list.count <= 100000, list.allSatisfy({ $0.range(of: "^[A-Za-z][A-Za-z'-]*$", options: .regularExpression) != nil }) else { throw CocoaError(.fileReadCorruptFile) }
        known.formUnion(list.map { $0.lowercased() }); for index in words.indices where known.contains(words[index].id) { words[index].data["status"] = "known" }; persist()
    }
}
