import UIKit
import WebKit
import AVFoundation
import CryptoKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var queuedShare: URL?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller=ReaderController()
        let shared=UserDefaults(suiteName:"group.com.addvalue.wordahead")?.string(forKey:"pendingYouTubeURL")
        if let shared {UserDefaults(suiteName:"group.com.addvalue.wordahead")?.removeObject(forKey:"pendingYouTubeURL");controller.receiveSharedURL(URL(string:shared))}
        if let url=options?[.url] as? URL {controller.receiveSharedURL(url)}
        if let queuedShare {controller.receiveSharedURL(queuedShare);self.queuedShare=nil}
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
    func application(_ application:UIApplication,open url:URL,options:[UIApplication.OpenURLOptionsKey:Any]=[:])->Bool {
        guard url.scheme=="wordahead" else{return false}
        if let controller=window?.rootViewController as? ReaderController {controller.receiveSharedURL(url)}else{queuedShare=url}
        return true
    }
    func applicationWillEnterForeground(_ application:UIApplication){
        guard let shared=UserDefaults(suiteName:"group.com.addvalue.wordahead")?.string(forKey:"pendingYouTubeURL") else{return}
        UserDefaults(suiteName:"group.com.addvalue.wordahead")?.removeObject(forKey:"pendingYouTubeURL")
        (window?.rootViewController as? ReaderController)?.receiveSharedURL(URL(string:shared))
    }
}

final class ReaderController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var web: WKWebView!
    private var playerWeb: WKWebView!
    private var playerHeight: NSLayoutConstraint!
    private var playerLoaded = false
    private var playerRequested = false
    private var playerVideoID: String?
    private var playerCommand: [String:Any]?
    private let speaker = AVSpeechSynthesizer()
    private let dictionaryStore = OfflineDictionaryStore()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red:0.96,green:0.96,blue:0.97,alpha:1)
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name:"captions")
        config.userContentController.add(self, name:"dictionaryStore")
        config.userContentController.add(self, name:"speak")
        config.userContentController.add(self, name:"vocabularyExport")
        config.userContentController.add(self, name:"youtubePlayer")
        let playerConfig = WKWebViewConfiguration()
        playerConfig.allowsInlineMediaPlayback = true
        playerConfig.mediaTypesRequiringUserActionForPlayback = []
        playerConfig.userContentController.add(self,name:"youtubeState")
        playerWeb = WKWebView(frame:.zero,configuration:playerConfig)
        playerWeb.navigationDelegate = self
        playerWeb.uiDelegate = self
        playerWeb.translatesAutoresizingMaskIntoConstraints = false
        playerWeb.scrollView.isScrollEnabled = false
        playerWeb.isHidden = true
        view.addSubview(playerWeb)
        playerHeight = playerWeb.heightAnchor.constraint(equalToConstant:0)
        web = WKWebView(frame:.zero, configuration:config)
        web.navigationDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        web.isOpaque = false
        web.backgroundColor = view.backgroundColor
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let backSwipe = UIScreenEdgePanGestureRecognizer(target:self,action:#selector(swipeBack(_:)))
        backSwipe.edges = .left
        web.addGestureRecognizer(backSwipe)
        web.scrollView.panGestureRecognizer.require(toFail:backSwipe)
        view.addSubview(web)
        NSLayoutConstraint.activate([
            playerWeb.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),
            playerWeb.leadingAnchor.constraint(equalTo:view.leadingAnchor),
            playerWeb.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            playerHeight,
            web.topAnchor.constraint(equalTo:playerWeb.bottomAnchor),
            web.bottomAnchor.constraint(equalTo:view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo:view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo:view.trailingAnchor)
        ])
        NotificationCenter.default.addObserver(self,selector:#selector(pauseYouTube),name:UIApplication.willResignActiveNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(restoreYouTubeRate),name:UIApplication.didBecomeActiveNotification,object:nil)
        if let root = Bundle.main.url(forResource:"Web",withExtension:nil) {
            web.loadFileURL(root.appendingPathComponent("index.html"),allowingReadAccessTo:root)
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["WORDAHEAD_PLAYER_SMOKE_TEST"] == "1" {
            handleYouTube(["action":"show","videoId":"M7lc1UVf-VE"])
            checkPlayerSmokeTest()
        }
        #endif
    }
    #if DEBUG
    private func checkPlayerSmokeTest(attempt:Int=0,phase:Int=0){
        guard attempt < 30 else {print("WORDAHEAD_PLAYER_TEST FAIL: player did not reach the requested playing position");pauseYouTube();showYouTube(false);return}
        playerWeb.evaluateJavaScript("typeof WordAheadYouTube === 'object' ? WordAheadYouTube.getState() : null") { [weak self] value,_ in
            guard let self = self else {return}
            var next = phase
            if let state = value as? [String:Any],state["ready"] as? Bool == true {
                let time = state["time"] as? Double ?? 0
                let playing = (state["state"] as? Int) == 1
                if phase == 0 {
                    self.handleYouTube(["action":"seek","videoId":"M7lc1UVf-VE","start":12.0,"play":true]);next = 1
                    print("WORDAHEAD_PLAYER_TEST ready; seeking 12s")
                }else if phase == 1,playing,time >= 11.5,time < 35 {
                    self.handleYouTube(["action":"seek","videoId":"M7lc1UVf-VE","start":42.0,"play":true]);next = 2
                    print("WORDAHEAD_PLAYER_TEST first seek playing at \(time); seeking 42s")
                }else if phase == 2,playing,time >= 40,time < 65 {
                    print("WORDAHEAD_PLAYER_TEST PASS: native inline playback and seek verified at \(time)")
                    self.pauseYouTube();self.showYouTube(false);return
                }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in self?.checkPlayerSmokeTest(attempt:attempt+1,phase:next) }
        }
    }
    #endif
    deinit {NotificationCenter.default.removeObserver(self)}
    private func showYouTube(_ visible:Bool){
        playerWeb.isHidden = !visible
        playerHeight.constant = visible ? min(290,max(230,view.bounds.width*9/16+32)) : 0
        view.layoutIfNeeded()
    }
    @objc private func pauseYouTube(){
        if var command = playerCommand {command["play"] = false;playerCommand = command}
        if playerLoaded {playerWeb.evaluateJavaScript("WordAheadYouTube.load({action:'pause'})",completionHandler:nil)}
    }
    @objc private func restoreYouTubeRate(){
        applyStoredYouTubeRate()
        DispatchQueue.main.asyncAfter(deadline:.now()+0.8){ [weak self] in self?.applyStoredYouTubeRate() }
    }
    private func applyStoredYouTubeRate(){
        guard playerLoaded,let rate=playerCommand?["rate"] as? Double,rate.isFinite,rate > 0 else {return}
        playerWeb.evaluateJavaScript("WordAheadYouTube.setRate(\(rate))",completionHandler:nil)
    }
    private func sendPlayerCommand(){
        guard playerLoaded,let command = playerCommand,
              let data = try? JSONSerialization.data(withJSONObject:command),
              let json = String(data:data,encoding:.utf8) else {return}
        playerWeb.evaluateJavaScript("WordAheadYouTube.load(\(json))",completionHandler:nil)
    }
    private func handleYouTube(_ data:[String:Any]){
        guard let action = data["action"] as? String else {return}
        if action == "pause" {pauseYouTube();return}
        if action == "rate" { if let rate=data["rate"] as? Double,rate.isFinite,rate > 0 { playerCommand?["rate"] = rate; playerWeb.evaluateJavaScript("WordAheadYouTube.setRate(\(rate))",completionHandler:nil) }; return }
        if action == "hide" {pauseYouTube();showYouTube(false);return}
        guard ["show","seek","load"].contains(action),let id = data["videoId"] as? String,
              id.range(of:"^[A-Za-z0-9_-]{11}$",options:.regularExpression) != nil else {return}
        showYouTube(true)
        let changed = playerVideoID != id
        if action == "show", let rate=data["rate"] as? Double, rate.isFinite, rate > 0 {
            playerCommand?["rate"] = rate
            if playerLoaded { playerWeb.evaluateJavaScript("WordAheadYouTube.setRate(\(rate))",completionHandler:nil) }
        }
        if action != "show" || changed {
            let start = (data["start"] as? Double) ?? 0
            guard start.isFinite,start >= 0 else {return}
            playerVideoID = id
            playerCommand = ["action":action == "seek" ? "seek" : "load","videoId":id,"start":start,"play":data["play"] as? Bool ?? false,"rate":data["rate"] as? Double ?? 1]
        }
        if !playerRequested {
            guard let url = Bundle.main.url(forResource:"youtube-player",withExtension:"html",subdirectory:"Web"),
                  let html = try? String(contentsOf:url,encoding:.utf8),
                  let base = URL(string:"https://\((Bundle.main.bundleIdentifier ?? "com.addvalue.wordahead").lowercased())/") else {return}
            playerRequested = true
            playerWeb.loadHTMLString(html,baseURL:base)
        }else if action != "show" || changed {sendPlayerCommand()}
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){
        if webView === playerWeb {playerLoaded = true;sendPlayerCommand()}
        if webView === web {consumeSharedURL()}
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        let alert = UIAlertController(title: "화면을 열 수 없습니다", message: "앱을 다시 시작하거나 잠시 후 다시 시도해주세요.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }
    @objc private func swipeBack(_ gesture:UIScreenEdgePanGestureRecognizer) {
        let movement = gesture.translation(in:web)
        guard gesture.state == .ended,movement.x > 64,abs(movement.y) < movement.x*0.6 else {return}
        speaker.stopSpeaking(at:.immediate)
        web.evaluateJavaScript("typeof navigateBack === 'function' ? navigateBack() : history.back()",completionHandler:nil)
    }
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        if message.name == "dictionaryStore", message.webView === web, message.frameInfo.isMainFrame,
           let request = message.body as? [String:String], let id = request["id"] {
            Task {
                do {
                    let result = try await dictionaryStore.handle(request)
                    let payload: [String:Any] = ["id":id,"result":result]
                    let data = try JSONSerialization.data(withJSONObject:payload)
                    if let json = String(data:data,encoding:.utf8) {web.evaluateJavaScript("window.WordAheadDictionary.receive(\(json))",completionHandler:nil)}
                } catch {
                    let data = try? JSONSerialization.data(withJSONObject:["id":id,"error":"사전 다운로드에 실패했습니다. Wi-Fi 연결을 확인하고 다시 시도해주세요."])
                    if let data, let json = String(data:data,encoding:.utf8) {web.evaluateJavaScript("window.WordAheadDictionary.receive(\(json))",completionHandler:nil)}
                }
            }
            return
        }
        if message.name == "youtubePlayer",message.webView === web,message.frameInfo.isMainFrame,let data = message.body as? [String:Any] {handleYouTube(data);return}
        if message.name == "youtubeState",let data=message.body as? [String:Any] {
            if let rate=data["rate"] as? Double,rate.isFinite,rate > 0 {
                playerCommand?["rate"] = rate
                web.evaluateJavaScript("if(typeof WordAheadVideo!=='undefined'){WordAheadVideo.playbackRate=\(rate);localStorage.setItem('wa-youtube-playback-rate',String(\(rate)));}",completionHandler:nil)
            }
            if let time=data["time"] as? Double,time.isFinite {web.evaluateJavaScript("window.WordAheadPlayback?.update(\(time))",completionHandler:nil)}
            return
        }
        if message.name == "vocabularyExport",let text=message.body as? String,let data=text.data(using:.utf8),data.count <= 5_000_000 {
            do {
                let url=FileManager.default.temporaryDirectory.appendingPathComponent("WordAhead-known-words.json")
                try data.write(to:url,options:.atomic)
                present(UIDocumentPickerViewController(forExporting:[url],asCopy:true),animated:true)
            } catch {web.evaluateJavaScript("notify('어휘 백업 파일을 저장할 수 없습니다.')",completionHandler:nil)}
        }
        if message.name == "speak", let word = message.body as? String {
            pauseYouTube()
            let utterance = AVSpeechUtterance(string:word)
            utterance.voice = AVSpeechSynthesisVoice(language:"en-US")
            utterance.rate = 0.43
            speaker.stopSpeaking(at:.immediate);speaker.speak(utterance)
        }
        if message.name == "captions", let data=message.body as? [String:String], let id=data["id"], let video=data["videoId"] {
            Task {
                var result: [String:Any]?
                var failure: String?
                do {result=try await CaptionFetcher.fetch(video)}catch {failure=error.localizedDescription}
                let payload:[Any] = [id,(result as Any?) ?? NSNull(),(failure as Any?) ?? NSNull()]
                if let encoded=try? JSONSerialization.data(withJSONObject:payload),let json=String(data:encoded,encoding:.utf8) {
                    await MainActor.run {self.web.evaluateJavaScript("WordAheadCaptions.complete(...\(json))",completionHandler:nil)}
                }
            }
        }
    }
    private var pendingSharedURL:URL?
    func receiveSharedURL(_ incoming:URL?){
        guard let incoming else{return}
        if incoming.scheme=="wordahead",let components=URLComponents(url:incoming,resolvingAgainstBaseURL:false),let value=components.queryItems?.first(where:{$0.name=="url"})?.value {pendingSharedURL=URL(string:value)}else{pendingSharedURL=incoming}
        if isViewLoaded,!web.isLoading,web.url != nil {consumeSharedURL()}
    }
    private func consumeSharedURL(){
        guard let url=pendingSharedURL,let data=try? JSONSerialization.data(withJSONObject:[url.absoluteString]),let array=String(data:data,encoding:.utf8) else{return}
        pendingSharedURL=nil
        let quoted=String(array.dropFirst().dropLast())
        web.evaluateJavaScript("window.WordAheadShare?.handle(\(quoted))",completionHandler:nil)
    }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url=action.request.url else {decisionHandler(.cancel);return}
        if webView === playerWeb {
            let host = url.host?.lowercased() ?? ""
            let embedded = ["youtube.com","youtube-nocookie.com","google.com"].contains {host == $0 || host.hasSuffix("."+$0)}
            let appHost = (Bundle.main.bundleIdentifier ?? "com.addvalue.wordahead").lowercased()
            if url.absoluteString == "about:blank" || (url.scheme == "https" && (host == appHost || (action.targetFrame?.isMainFrame == false && embedded))) {decisionHandler(.allow);return}
            if action.navigationType == .linkActivated,["https","http"].contains(url.scheme ?? "") {UIApplication.shared.open(url)}
            decisionHandler(.cancel);return
        }
        if url.isFileURL {
            guard let root = Bundle.main.url(forResource:"Web",withExtension:nil),
                  url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else {
                decisionHandler(.cancel);return
            }
            if action.navigationType == .linkActivated {
                webView.loadFileURL(url,allowingReadAccessTo:root)
                decisionHandler(.cancel);return
            }
            decisionHandler(.allow);return
        }
        if ["https","http","mailto"].contains(url.scheme ?? "") {UIApplication.shared.open(url)}
        decisionHandler(.cancel)
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for action:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        if action.targetFrame == nil,let url = action.request.url,["https","http"].contains(url.scheme ?? "") {UIApplication.shared.open(url)}
        return nil
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
            return text.isEmpty ? nil : ["start":(event["tStartMs"] as? Double ?? 0)/1000,"text":text]
        }
        guard !segments.isEmpty else {throw CaptionFailure.unavailable("영어 자막 본문이 비어 있습니다.")}
        let details=player["videoDetails"] as? [String:Any] ?? [:]
        return ["videoId":video,"title":details["title"] as? String ?? "YouTube 영어 자막","channel":details["author"] as? String ?? "YouTube","language":track["languageCode"] as? String ?? "en","isGenerated":track["kind"] as? String == "asr","segments":segments]
    }
}

// Dictionary data survives app upgrades and is excluded from iCloud backup.
actor OfflineDictionaryStore {
    private var downloading = false
    private var coreEntries: [String:Any]?
    private var shardEntries: [String:[String:Any]] = [:]
    private var cachedManifest: Manifest?
    private struct Manifest: Decodable {
        struct Shard: Decodable {let sha256: String; let bytes: Int}
        let version: String; let source: String; let shards: [String:Shard]
    }
    private func manifest() throws -> Manifest {
        if let cachedManifest {return cachedManifest}
        let url = Bundle.main.url(forResource:"offline-manifest",withExtension:"json",subdirectory:"Web/dictionary")!
        let result = try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:url)); cachedManifest = result; return result
    }
    private func directory() throws -> URL {
        var url = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("OfflineDictionary",isDirectory:true)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
        return url
    }
    func handle(_ request: [String:String]) async throws -> [String:Any] {
        let manifest = try manifest(), root = try directory()
        if request["action"] == "lookup" {
            let key = request["word"] ?? ""
            let hash = Array(SHA256.hash(data:Data(key.utf8)))[0]
            let shard = String(format:"%02x",hash)
            if let info = manifest.shards[shard] {
                let url = root.appendingPathComponent(info.sha256+".json")
                if let entries = shardEntries[shard], let entry = entries[key] {return ["entry":entry]}
                if shardEntries[shard] == nil, let data = try? Data(contentsOf:url), let entries = try JSONSerialization.jsonObject(with:data) as? [String:Any] {
                    if shardEntries.count >= 8 {shardEntries.removeAll()}
                    shardEntries[shard] = entries
                    if let entry = entries[key] {return ["entry":entry]}
                }
            }
            if coreEntries == nil {
                let coreURL = Bundle.main.url(forResource:"core-ko",withExtension:"json",subdirectory:"Web/dictionary")!
                coreEntries = try JSONSerialization.jsonObject(with:Data(contentsOf:coreURL)) as? [String:Any]
            }
            return ["entry":coreEntries?[key] ?? NSNull()]
        }
        if request["action"] == "download" {
            guard !downloading else {return ["busy":true]}
            downloading = true; defer {downloading = false}
            let config = URLSessionConfiguration.ephemeral
            config.allowsCellularAccess = false; config.allowsExpensiveNetworkAccess = false; config.allowsConstrainedNetworkAccess = false
            config.timeoutIntervalForRequest = 30
            let session = URLSession(configuration:config); defer {session.invalidateAndCancel()}
            for (shard,info) in manifest.shards.sorted(by:{$0.key < $1.key}) {
                let destination = root.appendingPathComponent(info.sha256+".json")
                if FileManager.default.fileExists(atPath:destination.path) {continue}
                guard let url = URL(string:manifest.source+shard+".js") else {throw URLError(.badURL)}
                let (data,response) = try await session.data(from:url)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count == info.bytes,
                      SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == info.sha256,
                      let text = String(data:data,encoding:.utf8), let start = text.firstIndex(of:"{"), let end = text.lastIndex(of:"}") else {throw URLError(.cannotParseResponse)}
                let json = Data(text[start...end].utf8)
                _ = try JSONSerialization.jsonObject(with:json)
                try json.write(to:destination,options:.atomic)
            }
            let keep = Set(manifest.shards.values.map{$0.sha256+".json"})
            for file in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) where !keep.contains(file.lastPathComponent) {try? FileManager.default.removeItem(at:file)}
        }
        let count = manifest.shards.values.filter{FileManager.default.fileExists(atPath:root.appendingPathComponent($0.sha256+".json").path)}.count
        return ["complete":count == manifest.shards.count,"downloaded":count,"total":manifest.shards.count,"bytes":manifest.shards.values.reduce(0){$0+$1.bytes}]
    }
}
