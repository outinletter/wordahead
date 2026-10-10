import UIKit
import WebKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ReaderController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class ReaderController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private var web: WKWebView!
    private let speaker = AVSpeechSynthesizer()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red:0.96,green:0.96,blue:0.97,alpha:1)
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name:"captions")
        config.userContentController.add(self, name:"speak")
        web = WKWebView(frame:.zero, configuration:config)
        web.navigationDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        web.isOpaque = false
        web.backgroundColor = view.backgroundColor
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),
            web.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor),
            web.leadingAnchor.constraint(equalTo:view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo:view.trailingAnchor)
        ])
        if let root = Bundle.main.url(forResource:"Web",withExtension:nil) {
            web.loadFileURL(root.appendingPathComponent("index.html"),allowingReadAccessTo:root)
        }
    }
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        if message.name == "speak", let word = message.body as? String {
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
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url=action.request.url else {decisionHandler(.cancel);return}
        if url.isFileURL {decisionHandler(.allow);return}
        if ["https","http","mailto"].contains(url.scheme ?? "") {UIApplication.shared.open(url)}
        decisionHandler(.cancel)
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
