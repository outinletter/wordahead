import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var sharedURL: URL?
    private let message = UILabel()
    private let openButton = UIButton(type:.system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        message.text = "YouTube 링크를 확인하고 있어요…"
        message.textAlignment = .center
        message.numberOfLines = 0
        message.font = .preferredFont(forTextStyle:.body)
        openButton.setTitle("WordAhead에 추가",for:.normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle:.headline)
        openButton.backgroundColor = UIColor(red:0.08,green:0.54,blue:0.47,alpha:1)
        openButton.tintColor = .white
        openButton.layer.cornerRadius = 12
        openButton.heightAnchor.constraint(equalToConstant:52).isActive = true
        openButton.isEnabled = false
        openButton.addTarget(self,action:#selector(saveLink),for:.touchUpInside)
        let stack = UIStackView(arrangedSubviews:[message,openButton])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:24),
            stack.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-24),
            stack.centerYAnchor.constraint(equalTo:view.centerYAnchor)
        ])
        findSharedURL()
    }

    private func findSharedURL() {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap{$0.attachments ?? []}
        guard !providers.isEmpty else {showInvalid();return}
        load(from:providers,index:0)
    }

    private func load(from providers:[NSItemProvider],index:Int) {
        guard index < providers.count else {showInvalid();return}
        let provider = providers[index]
        let types = [UTType.url.identifier,UTType.plainText.identifier]
        guard let type = types.first(where:provider.hasItemConformingToTypeIdentifier) else {load(from:providers,index:index+1);return}
        provider.loadItem(forTypeIdentifier:type,options:nil){[weak self] item,_ in
            let candidate = (item as? URL)?.absoluteString ?? (item as? String)
            DispatchQueue.main.async {
                guard let self else{return}
                if let candidate,let url=self.youtubeURL(in:candidate){self.sharedURL=url;self.message.text=url.absoluteString;self.openButton.isEnabled=true}
                else{self.load(from:providers,index:index+1)}
            }
        }
    }

    private func youtubeURL(in text:String)->URL? {
        let candidates = [text] + (text.matches(of:/https?:\/\/[^\s<>]+/).map{String($0.output)})
        for candidate in candidates {
            guard let url=URLComponents(string:candidate.trimmingCharacters(in:CharacterSet(charactersIn:".,);]"))),
                  ["youtube.com","www.youtube.com","m.youtube.com","youtu.be"].contains(url.host?.lowercased() ?? "") else{continue}
            let id = url.host?.lowercased()=="youtu.be" ? url.path.split(separator:"/").first.map(String.init) : (url.queryItems?.first(where:{$0.name=="v"})?.value ?? url.path.split(separator:"/").last.map(String.init))
            guard let id,id.range(of:"^[A-Za-z0-9_-]{11}$",options:.regularExpression) != nil,let valid=URL(string:candidate) else{continue}
            return valid
        }
        return nil
    }

    private func showInvalid(){message.text="YouTube 동영상 링크를 공유해주세요.";openButton.isEnabled=false}

    @objc private func saveLink(){
        guard let sharedURL,let defaults=UserDefaults(suiteName:"group.com.addvalue.wordahead") else{showInvalid();return}
        defaults.set(sharedURL.absoluteString,forKey:"pendingYouTubeURL")
        message.text="WordAhead에 저장했어요. 앱을 열면 영상이 바로 시작됩니다."
        openButton.isEnabled=false
        DispatchQueue.main.asyncAfter(deadline:.now()+0.45){[weak self] in self?.extensionContext?.completeRequest(returningItems:nil)}
    }
}
