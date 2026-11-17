import SwiftUI
import UIKit

// MARK: spaced repetition + study stats
extension NativeLearningStore {
    private static let intervals: [Double] = [0, 1, 2, 4, 8, 16, 32]
    var dueWords: [LearningWord] {
        let now = Date().timeIntervalSince1970
        return words.filter { !$0.known && (($0.data["due"] as? Double) ?? 0) <= now }
    }
    func review(_ word: String, remembered: Bool) {
        guard let i = words.firstIndex(where: { $0.id == word }) else { return }
        let box = remembered ? min(Self.intervals.count - 1, (words[i].data["box"] as? Int ?? 0) + 1) : 0
        words[i].data["box"] = box
        words[i].data["due"] = Date().addingTimeInterval(remembered ? Self.intervals[box] * 86400 : 600).timeIntervalSince1970
        if remembered && box >= Self.intervals.count - 1 { words[i].data["status"] = "known"; known.insert(word) }
        persist(); recordStudy()
    }
    private static var dayFormatter: DateFormatter {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }
    func recordStudy() {
        let today = Self.dayFormatter.string(from: Date())
        var days = UserDefaults.standard.stringArray(forKey: "WordAheadStudyDays") ?? []
        if !days.contains(today) { days.append(today); UserDefaults.standard.set(Array(days.suffix(400)), forKey: "WordAheadStudyDays") }
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "WordAheadReviewedToday-\(today)") + 1, forKey: "WordAheadReviewedToday-\(today)")
        objectWillChange.send()
    }
    var reviewedToday: Int { UserDefaults.standard.integer(forKey: "WordAheadReviewedToday-\(Self.dayFormatter.string(from: Date()))") }
    var streak: Int {
        let days = Set(UserDefaults.standard.stringArray(forKey: "WordAheadStudyDays") ?? [])
        var date = Date(), count = 0
        if !days.contains(Self.dayFormatter.string(from: date)) { date = Calendar.current.date(byAdding: .day, value: -1, to: date)! }
        while days.contains(Self.dayFormatter.string(from: date)) { count += 1; date = Calendar.current.date(byAdding: .day, value: -1, to: date)! }
        return count
    }
}

extension NativeLearningStore {
    /// Video + start time of the caption segment that contains the word.
    func scene(for word: LearningWord) -> (video: LearningVideo, start: Double)? {
        guard let source = word.data["source"] as? String,
              let video = videos.first(where: { $0.title == source && $0.youtubeID != nil }) else { return nil }
        let hit = video.segments.first { ($0["text"] as? String)?.range(of: word.id, options: .caseInsensitive) != nil }
        return (video, hit?["start"] as? Double ?? position(video.id))
    }
    /// First sentence of the saved context that contains the word.
    func example(for word: LearningWord) -> String? {
        guard let text = word.data["context"] as? String, !text.isEmpty else { return nil }
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ".?!\n"))
        guard let hit = parts.first(where: { $0.range(of: word.id, options: .caseInsensitive) != nil })?.trimmingCharacters(in: .whitespaces), hit.count > word.id.count, hit.count < 220 else { return nil }
        return hit
    }
}

struct ReplayItem: Identifiable { let id: String }

struct NativeReviewView: View {
    @ObservedObject var store: NativeLearningStore
    @State private var queue: [LearningWord] = []
    @State private var started = false
    @State private var flipped = false
    @State private var done = 0
    @State private var remembered = 0
    @State private var replay: LearningVideo?
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                stats
                if !started { startCard } else if let word = queue.first { card(word) } else { summary }
            }.padding(18)
        }.background(WordAheadStyle.background).navigationTitle("복습")
        .fullScreenCover(item: Binding(get: { replay.map { ReplayItem(id: $0.id) } }, set: { if $0 == nil { replay = nil } })) { item in NavigationStack { NativeReaderView(store: store, videoID: item.id) } }
    }
    private var stats: some View {
        HStack(spacing: 10) {
            stat("flame.fill", "\(store.streak)", "연속 학습일", tint: WordAheadStyle.amber)
            stat("checkmark.circle.fill", "\(store.reviewedToday)", "오늘 복습")
            stat("clock.fill", "\(store.dueWords.count)", "복습 대기")
        }
    }
    private func stat(_ icon: String, _ value: String, _ label: LocalizedStringKey, tint: Color = WordAheadStyle.teal) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).font(.wa(22, .bold)).contentTransition(.numericText()).animation(.spring, value: value)
            Text(label).font(.wa(11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 14).glass(RoundedRectangle(cornerRadius: 16), interactive: false)
    }
    private var startCard: some View {
        VStack(spacing: 14) {
            Image(systemName: store.dueWords.isEmpty ? "party.popper" : "rectangle.stack.fill").font(.system(size: 44)).foregroundStyle(WordAheadStyle.teal)
            Text(store.dueWords.isEmpty ? LocalizedStringKey("오늘 복습할 단어가 없어요") : LocalizedStringKey("복습할 단어 \(min(20, store.dueWords.count))개")).font(.wa(18, .bold))
            Text("카드를 눌러 뜻을 확인하고, 기억나는지 골라 주세요.").font(.wa(13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !store.dueWords.isEmpty {
                Button { queue = Array(store.dueWords.shuffled().prefix(20)); done = 0; remembered = 0; flipped = false; withAnimation(.spring) { started = true } } label: {
                    Text("복습 시작").font(.wa(16, .bold)).foregroundStyle(WordAheadStyle.onAmber).frame(maxWidth: .infinity).frame(height: 48).background(WordAheadStyle.amber, in: Capsule())
                }.buttonStyle(PressableStyle())
            }
        }.padding(24).frame(maxWidth: .infinity).background(WordAheadStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private func card(_ word: LearningWord) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(done), total: Double(done + queue.count)).tint(WordAheadStyle.teal)
            Button { Haptic.tap(); withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { flipped.toggle() }; if flipped { store.speak(word.id) } } label: {
                VStack(spacing: 12) {
                    Text(word.id).font(.wa(30, .bold)).multilineTextAlignment(.center)
                    if flipped {
                        (word.definition.isEmpty ? Text("뜻을 찾지 못했습니다") : Text(verbatim: word.definition)).font(.wa(17)).multilineTextAlignment(.center).foregroundStyle(.secondary).transition(.opacity.combined(with: .scale(scale: 0.95)))
                        if let example = store.example(for: word) { Text(example).font(.wa(14)).italic().multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.top, 6) }
                        if let scene = store.scene(for: word) {
                            Button { store.setPosition(scene.video.id, time: scene.start); Haptic.tap(); replay = scene.video } label: { Label("이 장면 다시 보기", systemImage: "play.circle.fill").font(.wa(14, .semibold)).padding(.horizontal, 14).frame(height: 40).glass(Capsule(), tint: WordAheadStyle.teal.opacity(0.2)) }.buttonStyle(PressableStyle()).padding(.top, 8)
                        }
                    } else { Text("눌러서 뜻 보기").font(.wa(13)).foregroundStyle(.tertiary) }
                }.frame(maxWidth: .infinity, minHeight: 240).padding(20).background(WordAheadStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            }.buttonStyle(.plain).id(word.id).transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            if flipped {
                HStack(spacing: 12) {
                    answer("다시 볼게요", "arrow.counterclockwise", false, .orange)
                    answer("기억나요", "checkmark", true, WordAheadStyle.teal)
                }.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    private func answer(_ title: LocalizedStringKey, _ icon: String, _ ok: Bool, _ tint: Color) -> some View {
        Button {
            ok ? Haptic.success() : Haptic.tap()
            guard let word = queue.first else { return }
            store.review(word.id, remembered: ok)
            withAnimation(.spring) { queue.removeFirst(); done += 1; if ok { remembered += 1 }; flipped = false }
        } label: { Label(title, systemImage: icon).font(.wa(15, .bold)).frame(maxWidth: .infinity).frame(height: 48).glass(Capsule(), tint: tint.opacity(0.3)) }.buttonStyle(PressableStyle())
    }
    private var summary: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(WordAheadStyle.teal).onAppear { Haptic.success() }
            Text("복습 완료!").font(.wa(20, .bold))
            Text("\(done)개 중 \(remembered)개를 기억했어요").foregroundStyle(.secondary)
            Button("닫기") { withAnimation(.spring) { started = false } }.buttonStyle(.borderedProminent).tint(WordAheadStyle.teal)
        }.padding(24).frame(maxWidth: .infinity).background(WordAheadStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: design tokens + scalable fonts
extension Color {
    static func dynamic(light: UIColor, dark: UIColor) -> Color { Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light }) }
}
extension WordAheadStyle {
    static let background = Color.dynamic(light: UIColor(red: 0.980, green: 0.973, blue: 0.957, alpha: 1), dark: UIColor(red: 0.071, green: 0.125, blue: 0.114, alpha: 1))
    static let surface = Color.dynamic(light: .white, dark: UIColor(red: 0.106, green: 0.169, blue: 0.153, alpha: 1))
    static let amber = Color.dynamic(light: UIColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1), dark: UIColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 1))
    static let onAmber = Color(red: 0.24, green: 0.14, blue: 0.0)
    static let muted = Color.dynamic(light: UIColor(red: 0.40, green: 0.46, blue: 0.45, alpha: 1), dark: UIColor(red: 0.67, green: 0.73, blue: 0.72, alpha: 1))
    static let youtube = Color(red: 0.88, green: 0.40, blue: 0.35)
}
extension Font {
    /// System font scaled with Dynamic Type (capped so fixed layouts stay usable).
    static func wa(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let scaled = UIFontMetrics.default.scaledValue(for: size)
        return .system(size: min(scaled, size * 1.35), weight: weight)
    }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay(GeometryReader { g in
            LinearGradient(colors: [.clear, Color.white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: g.size.width * 0.6).offset(x: phase * g.size.width * 1.6)
        }.clipped()).onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}
extension NativeLearningStore {
    func addSample() {
        guard !videos.contains(where: { $0.id == "native-sample" }) else { return }
        videos.insert(LearningVideo(data: ["id": "native-sample", "title": "오늘의 작은 발견", "channel": "WordAhead 연습 자막", "text": "Learning a language begins with curiosity. Every small discovery brings us closer to understanding. Take your time and enjoy the journey."]), at: 0)
        persist()
    }
}
