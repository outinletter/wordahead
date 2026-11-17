import UIKit
import SwiftUI
import AVFoundation
import CryptoKit
import StoreKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let store = NativeLearningStore()
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: NativeAppearanceView(store: store))
        window.makeKeyAndVisible(); self.window = window
        PlaybackAudio.configure(); TabAppearance.configure()
        consumeShare()
        if let url = options?[.url] as? URL { receive(url) }
        return true
    }
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.scheme == "wordahead" else { return false }; receive(url); return true
    }
    func applicationWillEnterForeground(_ application: UIApplication) { consumeShare() }
    private func consumeShare() {
        let defaults = UserDefaults(suiteName: "group.com.addvalue.wordahead")
        if let value = defaults?.string(forKey: "pendingYouTubeURL"), let url = URL(string: value) {
            defaults?.removeObject(forKey: "pendingYouTubeURL"); receive(url)
        }
    }
    private func receive(_ url: URL) {
        let value = url.scheme == "wordahead" ? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value : url.absoluteString
        if let value, NativeLearningStore.youtubeID(value) != nil { store.handleSharedURL(value) }
    }
}
struct NativeAppearanceView: View {
    @ObservedObject var store: NativeLearningStore
    @AppStorage("nativeAppearance") private var appearance = "system"
    @AppStorage("nativeAppLanguage") private var language = "ko"
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NativeAppView(store: store).id(typeSize)
            .environment(\.locale, Locale(identifier: language))
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }
}

enum CaptionFailure: LocalizedError {
    case unavailable(String)
    var errorDescription:String? {if case .unavailable(let message)=self {return message};return nil}
}
enum CaptionFetcher {
    static func request(_ url:URL,body:Data?=nil) async throws -> Data {
        var request=URLRequest(url:url,timeoutInterval:15)
        if let body {request.httpMethod="POST";request.httpBody=body;request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await URLSession.shared.data(for:request)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode),!data.isEmpty else {
            throw CaptionFailure.unavailable("YouTube가 자막 요청을 거절했습니다. 다시 시도하세요.")
        }
        return data
    }
    static func fetch(_ video:String) async throws -> [String:Any] {
        guard video.range(of:"^[A-Za-z0-9_-]{11}$",options:.regularExpression) != nil else {throw CaptionFailure.unavailable("올바른 영상 주소를 입력하세요.")}
        let html=String(decoding:try await request(URL(string:"https://www.youtube.com/watch?v=\(video)")!),as:UTF8.self)
        let regex=try NSRegularExpression(pattern:"\"INNERTUBE_API_KEY\":\\s*\"([A-Za-z0-9_-]+)\"")
        guard let match=regex.firstMatch(in:html,range:NSRange(html.startIndex...,in:html)),let range=Range(match.range(at:1),in:html) else {throw CaptionFailure.unavailable("YouTube에서 자막 접근을 허용하지 않았습니다.")}
        let body=try JSONSerialization.data(withJSONObject:["context":["client":["clientName":"ANDROID","clientVersion":"20.10.38"]],"videoId":video])
        let data=try await request(URL(string:"https://www.youtube.com/youtubei/v1/player?key=\(html[range])")!,body:body)
        let player=try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
        let status=player["playabilityStatus"] as? [String:Any]
        guard status?["status"] as? String == "OK" else {throw CaptionFailure.unavailable("비공개·연령 제한 또는 접근할 수 없는 영상입니다.")}
        let captions=player["captions"] as? [String:Any]
        let renderer=captions?["playerCaptionsTracklistRenderer"] as? [String:Any]
        let tracks=(renderer?["captionTracks"] as? [[String:Any]] ?? []).filter {($0["languageCode"] as? String ?? "").hasPrefix("en")}
        guard let track=tracks.first(where:{$0["kind"] as? String == "asr"}) ?? tracks.first,
              let address=track["baseUrl"] as? String,var components=URLComponents(string:address),
              components.scheme=="https",["youtube.com","www.youtube.com"].contains(components.host ?? "") else {throw CaptionFailure.unavailable("이 영상에는 수집 가능한 영어 자막이 없습니다.")}
        guard !(components.queryItems ?? []).contains(where:{$0.name=="exp" && $0.value=="xpe"}) else {throw CaptionFailure.unavailable("YouTube에서 추가 인증을 요구해 자동 수집할 수 없습니다.")}
        components.queryItems=(components.queryItems ?? []).filter {$0.name != "fmt"}+[URLQueryItem(name:"fmt",value:"json3")]
        let captionData=try await request(components.url!)
        let json=try JSONSerialization.jsonObject(with:captionData) as? [String:Any] ?? [:]
        let events=json["events"] as? [[String:Any]] ?? []
        let segments:[[String:Any]]=events.compactMap {event in
            let text=(event["segs"] as? [[String:Any]] ?? []).compactMap {$0["utf8"] as? String}.joined().replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
            let start=(event["tStartMs"] as? Double ?? 0)/1000
            let parts:[[String:Any]]=(event["segs"] as? [[String:Any]] ?? []).map {["text":$0["utf8"] as? String ?? "","start":start+($0["tOffsetMs"] as? Double ?? 0)/1000]}
            return text.isEmpty ? nil : ["start":start,"text":text,"duration":(event["dDurationMs"] as? Double ?? 0)/1000,"parts":parts]
        }
        guard !segments.isEmpty else {throw CaptionFailure.unavailable("영어 자막 본문이 비어 있습니다.")}
        let details=player["videoDetails"] as? [String:Any] ?? [:]
        return ["videoId":video,"title":details["title"] as? String ?? "YouTube 영어 자막","channel":details["author"] as? String ?? "YouTube","language":track["languageCode"] as? String ?? "en","isGenerated":track["kind"] as? String == "asr","segments":segments]
    }
}

// Dictionary data survives app upgrades and is excluded from iCloud backup.
actor OfflineDictionaryStore {
    private var coreEntries:[String:Any]?
    private var supplementEntries:[String:Any]?
    private var storedManifest:Manifest?
    private struct Manifest:Decodable {
        struct FileInfo:Decodable {let sha256:String;let bytes:Int}
        let version:String;let entries:Int;let files:[String:FileInfo]
    }
    private func loadEntries() throws {
        guard coreEntries == nil else{return}
        guard let root=Bundle.main.url(forResource:"Web",withExtension:nil) else {throw URLError(.fileDoesNotExist)}
        let directory=root.appendingPathComponent("dictionary")
        let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:directory.appendingPathComponent("offline-manifest.json")))
        func read(_ name:String) throws -> [String:Any] {
            let data=try Data(contentsOf:directory.appendingPathComponent(name))
            guard let info=manifest.files[name],data.count==info.bytes,
                  SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==info.sha256,
                  let entries=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw URLError(.cannotParseResponse)}
            return entries
        }
        let core=try read("core-ko.json"),supplement=try read("kengdic-ko.json")
        guard Set(core.keys).union(supplement.keys).count==manifest.entries else {throw URLError(.cannotParseResponse)}
        coreEntries=core;supplementEntries=supplement;storedManifest=manifest
        // Remove only generated legacy shard caches after both bundled dictionaries verify.
        if let support=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first {
            let legacy=support.appendingPathComponent("OfflineDictionary",isDirectory:true)
            for file in (try? FileManager.default.contentsOfDirectory(at:legacy,includingPropertiesForKeys:nil)) ?? [] {
                if file.lastPathComponent.range(of:"^[0-9a-f]{64}\\.json$",options:.regularExpression) != nil {try? FileManager.default.removeItem(at:file)}
            }
        }
    }
    func warmUp() async { try? loadEntries() }
    private func localEntry(_ key:String) -> Any? {coreEntries?[key] ?? supplementEntries?[key]}
    func handle(_ request:[String:String]) async throws -> [String:Any] {
        if request["action"] == "online" {
            guard let address=request["url"],address.count<=4000,let url=URL(string:address),url.scheme=="https",
                  (url.host=="ko.wiktionary.org" && url.path=="/w/api.php") || (url.host=="api.mymemory.translated.net" && url.path=="/get") else {throw URLError(.badURL)}
            var query=URLRequest(url:url,timeoutInterval:12);query.setValue("WordAhead/1.1 (https://outinletter.github.io/wordahead/support.html)",forHTTPHeaderField:"User-Agent")
            let (data,response)=try await URLSession.shared.data(for:query)
            guard let status=(response as? HTTPURLResponse)?.statusCode,(200..<300).contains(status),data.count<3_000_000,let text=String(data:data,encoding:.utf8) else {throw URLError(.badServerResponse)}
            return ["json":text]
        }
        try loadEntries()
        if request["action"] == "lookup" {return ["entry":localEntry(request["word"] ?? "") ?? NSNull()]}
        if request["action"] == "lookupMany" {
            guard let data=request["words"]?.data(using:.utf8),let words=try JSONSerialization.jsonObject(with:data) as? [String],words.count<=12000,words.allSatisfy({$0.count<=100}) else {throw URLError(.badURL)}
            var entries:[String:Any]=[:]
            for key in Set(words) {entries[key]=localEntry(key) ?? NSNull()}
            return ["entries":entries]
        }
        guard let manifest=storedManifest else {throw URLError(.cannotParseResponse)}
        return ["complete":true,"builtIn":true,"downloaded":0,"total":0,"entries":manifest.entries,"bytes":manifest.files.values.reduce(0){$0+$1.bytes}]
    }
}

// The quota applies to new learning analysis, never to YouTube playback.
actor WordAheadSubscriptionService {
    static let annualID = "com.addvalue.wordahead.plus.annual"
    static let groupID = "22492648"
    private var product: Product?
    private var premium = false
    private var pending: Set<String> = []
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {self.defaults = defaults}
    private var catalogAttempt: Date?
    private var catalogError = ""
    func refreshEntitlements() async {
        var active = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.annualID,transaction.revocationDate == nil,!transaction.isUpgraded else {continue}
            active = true
        }
        premium = active
    }
    private func loadProduct(force: Bool = false) async {
        guard product == nil,force || catalogAttempt == nil || Date().timeIntervalSince(catalogAttempt!) > 60 else {return}
        catalogAttempt = Date()
        do {
            let products = try await Product.products(for: [Self.annualID])
            guard let value = products.first(where: { $0.id == Self.annualID }), value.type == .autoRenewable else {
                catalogError = "App Store에서 구독 상품을 제공하지 않았습니다. 잠시 후 다시 시도해 주세요."
                return
            }
            product = value; catalogError = ""
            defaults.set(true,forKey:"WordAheadSubscriptionCatalogSeen")
        } catch {
            catalogError = error.localizedDescription
        }
    }
    private func todayIDs() -> Set<String> {
        let formatter = DateFormatter();formatter.calendar = Calendar(identifier:.gregorian);formatter.locale = Locale(identifier:"en_US_POSIX");formatter.timeZone = .current;formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from:Date()),previous = defaults.string(forKey:"WordAheadAnalysisDay") ?? ""
        if day > previous {defaults.set(day,forKey:"WordAheadAnalysisDay");defaults.set([String](),forKey:"WordAheadAnalysisIDs");pending.removeAll()}
        return Set(defaults.stringArray(forKey:"WordAheadAnalysisIDs") ?? [])
    }
    private var enforced: Bool {product != nil || defaults.bool(forKey:"WordAheadSubscriptionCatalogSeen")}
    private func allowed(_ id: String) -> Bool {
        let ids = todayIDs(),known = Set(defaults.stringArray(forKey:"WordAheadAnalyzedVideos") ?? [])
        return premium || ids.contains(id) || known.contains(id) || pending.contains(id) || ids.union(pending).count < 2
    }
    func beginAnalysis(_ id: String) async -> Bool {
        await refreshEntitlements();await loadProduct()
        guard id.range(of:"^[A-Za-z0-9_-]{11}$",options:.regularExpression) != nil,allowed(id) else {return false}
        pending.insert(id);return true
    }
    func finishAnalysis(_ id: String,success: Bool) {
        pending.remove(id)
        guard success else {return}
        var known = Set(defaults.stringArray(forKey:"WordAheadAnalyzedVideos") ?? [])
        if !known.contains(id) {var ids = todayIDs();ids.insert(id);defaults.set(Array(ids),forKey:"WordAheadAnalysisIDs")}
        known.insert(id);defaults.set(Array(known),forKey:"WordAheadAnalyzedVideos")
    }
    func resetLearningHistory() {
        pending.removeAll()
        defaults.removeObject(forKey: "WordAheadAnalysisDay")
        defaults.removeObject(forKey: "WordAheadAnalysisIDs")
        defaults.removeObject(forKey: "WordAheadAnalyzedVideos")
    }
    private func snapshot() -> [String:Any] {
        ["premium":premium,"available":product != nil,"enforced":true,"remaining":max(0,2-todayIDs().union(pending).count),"limit":2,"price":product?.displayPrice ?? "","catalogError":catalogError]
    }
    func handle(_ request: [String:String]) async throws -> [String:Any] {
        let action = request["action"] ?? "status"
        await refreshEntitlements();await loadProduct(force: action == "status" || action == "purchase")
        var purchase = ""
        if action == "restore" {try await AppStore.sync();await refreshEntitlements()}
        if action == "purchase" {
            guard let product else {throw URLError(.cannotConnectToHost)}
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification,transaction.productID == Self.annualID else {throw URLError(.userAuthenticationRequired)}
                await transaction.finish();await refreshEntitlements();purchase = "success"
            case .pending:purchase = "pending"
            case .userCancelled:purchase = "cancelled"
            @unknown default:purchase = "unknown"
            }
        }
        var state = snapshot()
        if action == "authorize",let id=request["videoId"] {state["allowed"] = allowed(id)}
        if !purchase.isEmpty {state["purchase"] = purchase}
        return state
    }
}
