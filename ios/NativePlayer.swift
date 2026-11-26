import SwiftUI
import WebKit

@MainActor
final class NativePlayerModel: ObservableObject {
    @Published var time: Double = 0
    @Published var isPlaying: Bool = false
    let videoID: String
    let start: Double
    weak var web: WKWebView?
    var ready = false
    private var queuedTime: Double?
    init(videoID: String, start: Double) { self.videoID = videoID; self.start = start }
    func command(_ name: String, value: Any? = nil) {
        guard let web else { return }
        if name == "seek", let time = value as? Double {
            guard ready else { queuedTime = time; return }
            let payload: [String: Any] = ["action": "seek", "videoId": videoID, "start": max(0,time), "play": true, "rate": UserDefaults.standard.dictionary(forKey: "WordAheadYouTubeSettings")?["rate"] as? Double ?? 1]
            if let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) { web.evaluateJavaScript("WordAheadYouTube.load(\(json))") }
        } else if name == "pause" {
            isPlaying = false
            web.evaluateJavaScript("WordAheadYouTube.suspend()")
        } else if name == "play" {
            isPlaying = true
            web.evaluateJavaScript("WordAheadYouTube.load({action:'play'})")
        } else if name == "resume" {
            restoreSettings()
        }
    }
    func restoreSettings() {
        guard ready, let web else { return }
        let settings = UserDefaults.standard.dictionary(forKey: "WordAheadYouTubeSettings") ?? [:]
        if let data = try? JSONSerialization.data(withJSONObject: settings), let json = String(data: data, encoding: .utf8) { web.evaluateJavaScript("WordAheadYouTube.restoreSettings(\(json))") }
    }
    func didLoad() {
        ready = true
        let payload: [String: Any] = ["action": "load", "videoId": videoID, "start": start, "play": false, "rate": UserDefaults.standard.dictionary(forKey: "WordAheadYouTubeSettings")?["rate"] as? Double ?? 1]
        if let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) { web?.evaluateJavaScript("WordAheadYouTube.load(\(json))") }
        restoreSettings()
        if let queuedTime { command("seek", value: queuedTime); self.queuedTime = nil }
    }
}

struct NativeYouTubePlayer: UIViewRepresentable {
    @ObservedObject var model: NativePlayerModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.allowsInlineMediaPlayback = true; config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "youtubeState")
        config.userContentController.add(context.coordinator, name: "youtubeSettings")
        config.userContentController.addUserScript(Self.frameScript())
        let web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = context.coordinator; web.uiDelegate = context.coordinator; web.scrollView.isScrollEnabled = false
        model.web = web
        if let url = Bundle.main.url(forResource: "youtube-player", withExtension: "html", subdirectory: "Web"), let html = try? String(contentsOf: url), let base = URL(string: "https://com.addvalue.wordahead/") { web.loadHTMLString(html, baseURL: base) }
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static let rateKey = "WordAheadPlaybackRate"
    // Runs inside every frame (including the YouTube iframe): keeps the page "visible" so playback survives screen-off,
    // and pins the video's playback rate to the user's last explicit choice (a change counts as explicit only right after a touch).
    static func frameScript() -> WKUserScript {
        let saved = UserDefaults.standard.double(forKey: rateKey)
        let source = """
        (function(){
          try{
            Object.defineProperty(document,'hidden',{get:function(){return false},configurable:true});
            Object.defineProperty(document,'visibilityState',{get:function(){return 'visible'},configurable:true});
            ['visibilitychange','webkitvisibilitychange','pagehide','freeze'].forEach(function(n){
              window.addEventListener(n,function(e){e.stopImmediatePropagation()},true);
              document.addEventListener(n,function(e){e.stopImmediatePropagation()},true);
            });
          }catch(e){}
          var desired=\(saved > 0 ? String(saved) : "null"),lastTouch=0,internal=false;
          ['touchstart','touchend','pointerdown','pointerup','mousedown','click'].forEach(function(n){window.addEventListener(n,function(){lastTouch=Date.now()},true)});
          function video(){return document.querySelector('video')}
          function apply(){var v=video();if(v&&desired&&Math.abs(v.playbackRate-desired)>0.001){internal=true;v.playbackRate=desired;setTimeout(function(){internal=false},50)}}
          document.addEventListener('ratechange',function(e){
            var v=e.target;if(!(v instanceof HTMLVideoElement)||internal)return;
            if(Date.now()-lastTouch<3000){desired=v.playbackRate;try{window.webkit.messageHandlers.youtubeState.postMessage({rate:desired})}catch(x){}}
            else if(desired){apply()}
          },true);
          ['loadedmetadata','play','playing','seeked'].forEach(function(n){document.addEventListener(n,apply,true)});
          setInterval(function(){if(Date.now()-lastTouch>3000)apply()},400);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.model.command("pause"); view.stopLoading()
        for name in ["youtubeState", "youtubeSettings"] { view.configuration.userContentController.removeScriptMessageHandler(forName: name) }
        coordinator.model.ready = false; coordinator.model.web = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let model: NativePlayerModel
        init(_ model: NativePlayerModel) { self.model = model }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { model.didLoad() }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { model.ready = false; webView.reload() }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if message.name == "youtubeSettings" { UserDefaults.standard.set(body, forKey: "WordAheadYouTubeSettings") }
            else if body["videoId"] == nil, let rate = body["rate"] as? Double, rate > 0 {
                UserDefaults.standard.set(rate, forKey: NativeYouTubePlayer.rateKey)
                controller.removeAllUserScripts(); controller.addUserScript(NativeYouTubePlayer.frameScript())
            }
            else if body["videoId"] as? String == model.videoID {
                if let time = body["time"] as? Double, time.isFinite { model.time = time }
                if let playing = body["playing"] as? Bool { model.isPlaying = playing }
                else if let state = body["state"] as? Int { model.isPlaying = (state == 1) }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false, ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url); decisionHandler(.cancel) }
            else { decisionHandler(.allow) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }; return nil
        }
    }
}

@MainActor
final class NativeCaptionMeasure {
    let width: Double
    let size: Double
    private let font: UIFont
    private var widths: [String: Double] = [:]
    init(width: Double, size: Double) { self.width = max(1, width - 9); self.size = size; font = .systemFont(ofSize: size, weight: .medium) }
    private func measure(_ word: String) -> Double {
        if let value = widths[word] { return value }
        let value = (word as NSString).size(withAttributes: [.font: font]).width
        widths[word] = value; return value
    }
    func fits(_ text: String, start: Double?) -> Bool {
        var lines = 1, used = start == nil ? 0.0 : 72.0
        let space = measure(" ")
        for word in text.split(whereSeparator: \.isWhitespace) {
            let size = measure(String(word)), gap = used > 0 ? space : 0
            if used > 0 && used + gap + size > width { lines += 1; used = 0 }
            used += (used > 0 ? space : 0) + size
            if used > width { let extra = Int(ceil(used / width)) - 1; lines += extra; used -= Double(extra) * width }
            if lines > 5 { return false }
        }
        return true
    }
}

struct NativeTranscriptText: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let known: Set<String>
    let saved: Set<String>
    var start: Double? = nil
    var estimated = false
    var onSeek: (() -> Void)? = nil
    var onStamp: (() -> Void)? = nil
    var savedSentences: [String] = []
    let onWord: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.isEditable = false; view.isSelectable = false; view.isScrollEnabled = false; view.backgroundColor = .clear; view.delegate = context.coordinator
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHold(_:)))
        hold.minimumPressDuration = 0.45
        view.addGestureRecognizer(hold); tap.require(toFail: hold)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let state = RenderState(text: text, fontSize: fontSize, known: known, saved: saved, start: start, estimated: estimated, dark: colorScheme == .dark, savedSentences: savedSentences)
        guard context.coordinator.rendered != state else { return }; context.coordinator.rendered = state
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = fontSize * 1.65; paragraph.maximumLineHeight = fontSize * 1.65
        let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.93, green: 0.96, blue: 0.95, alpha: 1) : UIColor(red: 0.09, green: 0.13, blue: 0.15, alpha: 1) }
                let value = NSMutableAttributedString(string: "")
        if let start {
            let attachment = NSTextAttachment()
            let seconds = max(0, Int(start))
            let time = seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
            let caption = "▶ " + (estimated ? "≈ " : "") + time
            let stampHeight: CGFloat = max(16, min(19, fontSize * 0.95))
            let stampFont = UIFont.systemFont(ofSize: max(9, stampHeight - 8), weight: .semibold)
            let width: CGFloat = max(estimated ? 58 : 50, ceil((caption as NSString).size(withAttributes: [.font: stampFont]).width) + 10)
            let dark = view.traitCollection.userInterfaceStyle == .dark
            attachment.image = UIGraphicsImageRenderer(size: CGSize(width: width, height: stampHeight)).image { _ in
                let background = UIColor(red: dark ? 0.15 : 0.93, green: dark ? 0.24 : 0.96, blue: dark ? 0.21 : 0.95, alpha: 1)
                let border = UIColor(red: dark ? 0.28 : 0.85, green: dark ? 0.38 : 0.91, blue: dark ? 0.35 : 0.88, alpha: 1)
                let path = UIBezierPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: width - 1, height: stampHeight - 1), cornerRadius: 4.5)
                background.setFill(); path.fill(); border.setStroke(); path.lineWidth = 1; path.stroke()
                let attributes: [NSAttributedString.Key: Any] = [.font: stampFont, .foregroundColor: dark ? UIColor(red: 0.77, green: 0.93, blue: 0.89, alpha: 1) : UIColor(red: 0.03, green: 0.46, blue: 0.40, alpha: 1)]
                let size = (caption as NSString).size(withAttributes: attributes)
                (caption as NSString).draw(at: CGPoint(x: (width - size.width) / 2, y: (stampHeight - size.height) / 2), withAttributes: attributes)
            }
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - stampHeight) / 2, width: width, height: stampHeight)
            let button = NSMutableAttributedString(attachment: attachment)
            button.addAttribute(NativeTranscriptText.action, value: URL(string: "wordahead-seek://time")!, range: NSRange(location: 0, length: 1))
            value.append(button); value.append(NSAttributedString(string: " ", attributes: [.font: font]))
        }
        let prefix = value.length
        value.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph, .kern: -0.15]))
        value.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: value.length))
        for sentence in savedSentences { if let range = text.range(of: sentence) ?? (sentence.contains(text) ? text.startIndex..<text.endIndex : nil) { value.addAttribute(.backgroundColor, value: UIColor(red: 0.95, green: 0.68, blue: 0.2, alpha: 0.22), range: NSRange(location: prefix + NSRange(range, in: text).location, length: NSRange(range, in: text).length)) } }
        if let regex = try? NSRegularExpression(pattern: "[A-Za-z]+(?:['’-][A-Za-z]+)*") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                let word = String(text[range]).lowercased()
                var components = URLComponents(); components.scheme = "wordahead-word"; components.host = "lookup"; components.queryItems = [URLQueryItem(name: "word", value: word)]
                let location = NSRange(location: prefix + match.range.location, length: match.range.length)
                if let url = components.url { value.addAttribute(NativeTranscriptText.action, value: url, range: location) }
                if saved.contains(word) && !known.contains(word) { value.addAttribute(.backgroundColor, value: UIColor(red: 0.09, green: 0.54, blue: 0.47, alpha: 0.18), range: location) }
            }
        }
        context.coordinator.prefix = prefix
        if view.attributedText != value { view.attributedText = value }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }; return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
    static let action = NSAttributedString.Key("wordahead.action")
    struct RenderState: Equatable {
        let text: String; let fontSize: Double; let known: Set<String>; let saved: Set<String>
        let start: Double?; let estimated: Bool; let dark: Bool; let savedSentences: [String]
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeTranscriptText
        var prefix = 0
        var rendered: RenderState?
        init(_ parent: NativeTranscriptText) { self.parent = parent }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if URL.scheme == "wordahead-seek" { parent.onSeek?() }
            else if let word = URLComponents(url: URL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value { parent.onWord(word) }
            return false
        }
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView else { return }
            let point = recognizer.location(in: textView)
            let adjustedPoint = CGPoint(x: point.x - textView.textContainerInset.left, y: point.y - textView.textContainerInset.top)
            let index = textView.layoutManager.characterIndex(for: adjustedPoint, in: textView.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            guard index < textView.textStorage.length else { parent.onSeek?(); return }
            let glyphRect = textView.layoutManager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: textView.textContainer)
            guard glyphRect.contains(adjustedPoint) else { parent.onSeek?(); return }
            if let url = textView.textStorage.attribute(NativeTranscriptText.action, at: index, effectiveRange: nil) as? URL {
                if url.scheme == "wordahead-seek" { parent.onSeek?() }
                else if let word = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value { parent.onWord(word) }
            } else { parent.onSeek?() }
        }
        @objc func handleHold(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let textView = recognizer.view as? UITextView else { return }
            let point = recognizer.location(in: textView)
            let index = textView.layoutManager.characterIndex(for: point, in: textView.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            guard index < textView.textStorage.length,
                  textView.layoutManager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: textView.textContainer).contains(point),
                  (textView.textStorage.attribute(NativeTranscriptText.action, at: index, effectiveRange: nil) as? URL)?.scheme == "wordahead-seek" else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            parent.onStamp?()
        }
    }
}

// Use measured viewport coordinates so variable-height caption groups align exactly.
@MainActor
final class NativeScrollReference: ObservableObject {
    weak var view: UIScrollView?
    func align(top: CGFloat, offset: Double) {
        guard let view else { return }
        let lower = -view.adjustedContentInset.top
        let upper = max(lower, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        let target = max(lower, min(upper, view.contentOffset.y + top - CGFloat(offset)))
        if abs(view.contentOffset.y - target) > 0.5 { view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: false) }
    }
}
struct NativeScrollLocator: UIViewRepresentable {
    let reference: NativeScrollReference
    func makeUIView(context: Context) -> Locator { let view = Locator(); view.reference = reference; return view }
    func updateUIView(_ view: Locator, context: Context) { view.reference = reference; view.resolve() }
    final class Locator: UIView {
        weak var reference: NativeScrollReference?
        override func didMoveToWindow() { super.didMoveToWindow(); resolve() }
        func resolve() {
            var parent = superview
            while let current = parent {
                if let scroll = current as? UIScrollView { reference?.view = scroll; return }
                parent = current.superview
            }
        }
    }
}
