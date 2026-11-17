import SwiftUI
import UIKit
import AVFoundation
import UserNotifications

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

extension View {
    /// Liquid Glass on iOS 26+, ultra-thin material on earlier systems.
    @ViewBuilder func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.tint(tint).interactive() : .regular.tint(tint), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(Color.white.opacity(0.18)))
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

enum TabAppearance {
    static func configure() {
        let item = UITabBarItemAppearance()
        item.normal.iconColor = .secondaryLabel; item.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        let a = UITabBarAppearance(); a.configureWithDefaultBackground()
        a.stackedLayoutAppearance = item; a.inlineLayoutAppearance = item; a.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = a; UITabBar.appearance().scrollEdgeAppearance = a
    }
}

enum PlaybackAudio {
    static func configure() { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: []); try? AVAudioSession.sharedInstance().setActive(true) }
}

enum StudyReminder {
    static let id = "wordahead.daily"
    static func localized(_ key: String) -> String {
        let code = UserDefaults.standard.string(forKey: "nativeAppLanguage") ?? "ko"
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    static func set(enabled: Bool, hour: Int, due: Int = 0) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled else { return true }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = "WordAhead"; content.body = Self.localized(due > 0 ? String(format: Self.localized("복습할 단어 %lld개가 기다리고 있어요."), Int(due)) : "오늘도 한 편, 내 영어로."); content.sound = .default
        var date = DateComponents(); date.hour = hour
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)))
        return true
    }
}

struct OnboardingView: View {
    let done: () -> Void
    var sample: () -> Void = {}
    @State private var page = 0
    private let pages: [(String, String, String)] = [
        ("play.rectangle.fill", "영상으로 시작해요", "YouTube 링크를 붙여넣으면 영어 자막을 모아 줍니다."),
        ("book.fill", "필요한 단어만 골라요", "자막을 읽다가 모르는 단어를 탭하면 한글 뜻을 바로 볼 수 있어요."),
        ("checkmark.seal.fill", "오프라인에서도 복습", "저장한 자막과 단어는 인터넷 없이 열 수 있어요.")
    ]
    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 18) {
                        Image(systemName: pages[i].0).font(.system(size: 64)).foregroundStyle(WordAheadStyle.teal).symbolEffect17()
                        Text(LocalizedStringKey(pages[i].1)).font(.title.bold())
                        Text(LocalizedStringKey(pages[i].2)).font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
                    }.tag(i)
                }
            }.tabViewStyle(.page)
            Button { if page < pages.count - 1 { withAnimation(.spring) { page += 1 } } else { Haptic.success(); done() } } label: {
                Text(LocalizedStringKey(page < pages.count - 1 ? "다음" : "시작하기")).font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50)
                    .background(WordAheadStyle.teal, in: Capsule())
            }.buttonStyle(PressableStyle()).padding(.horizontal, 24)
            Button("샘플로 먼저 체험하기") { Haptic.tap(); sample(); done() }.font(.subheadline.weight(.semibold)).foregroundStyle(WordAheadStyle.teal).opacity(page == pages.count - 1 ? 1 : 0).padding(.bottom, 16)
        }.interactiveDismissDisabled()
    }
}

private extension View {
    @ViewBuilder func symbolEffect17() -> some View {
        if #available(iOS 17.0, *) { self.symbolEffect(.pulse) } else { self }
    }
}

extension View {
    @ViewBuilder func zoomSource(id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { self.matchedTransitionSource(id: id, in: ns) } else { self }
    }
    @ViewBuilder func zoomTransition(id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { self.navigationTransition(.zoom(sourceID: id, in: ns)) } else { self }
    }
}
