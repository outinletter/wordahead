import SwiftUI
import StoreKit
import UniformTypeIdentifiers
import Combine

struct NativeAppView: View {
    @ObservedObject var store: NativeLearningStore
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("selectedTab") private var tab = 0
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("nativeAppLanguage") private var language = "ko"
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { NativeHomeView(store: store) }.tabItem { Label("홈", systemImage: "house.fill") }.tag(0)
            NavigationStack { NativeReviewView(store: store) }.tabItem { Label("복습", systemImage: "rectangle.stack.fill") }.badge(store.dueWords.count).tag(1)
            NavigationStack { NativeVocabularyView(store: store) }.tabItem { Label("단어장", systemImage: "book.fill") }.tag(2)
            NavigationStack { NativeSettingsView(store: store) }.tabItem { Label("설정", systemImage: "gearshape.fill") }.tag(3)
        }.tint(WordAheadStyle.teal)
        .onChange(of: scenePhase) { phase in if phase == .background, UserDefaults.standard.bool(forKey: "reminderOn") { Task { _ = await StudyReminder.set(enabled: true, hour: UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 20, due: store.dueWords.count) } } }
        .sheet(isPresented: Binding(get: { !didOnboard }, set: { _ in })) { OnboardingView(done: { didOnboard = true }, sample: { store.addSample() }) }
        .alert("안내", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("확인", role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: store.sharedURL) { value in
            if !value.isEmpty {
                store.handleSharedURL(value)
            }
        }
        .task {
            if !store.sharedURL.isEmpty {
                store.handleSharedURL(store.sharedURL)
            }
            await store.refreshBilling()
        }
    }
}

struct NativeHomeView: View {
    @ObservedObject var store: NativeLearningStore
    @AppStorage("nativeAppLanguage") private var language = "ko"
    @State private var showImport = false
    @State private var showInput = false
    @Environment(\.horizontalSizeClass) private var hSize
    @AppStorage("selectedTab") private var tab = 0
    @Namespace private var zoom
    @State private var showSettings = false
    @State private var filter: String?
    @State private var address = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var importedID: String?
    @Environment(\.colorScheme) private var scheme
    private var surface: Color { WordAheadStyle.surface }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image("Brand").resizable().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("WordAhead").font(.wa(26, .bold)).tracking(-0.8)
                    Spacer()
                    Button { showSettings = true } label: { Image(systemName: "gearshape").font(.wa(18)).foregroundStyle(WordAheadStyle.teal).frame(width: 44, height: 44).glass(Circle()).frame(width: 44, height: 44) }.accessibilityLabel(Text("환경설정"))
                }.padding(.vertical, 10).overlay(alignment: .bottom) { Divider() }
                VStack(alignment: .leading, spacing: 6) {
                    Text("오늘도 한 편, 내 영어로.").font(.wa(26, .bold)).tracking(-1)
                    Text("영상 자막을 읽고, 내게 필요한 단어를 모아보세요.").font(.wa(14)).foregroundStyle(.secondary)
                }
                if store.dueWords.count > 0 {
                    Button { Haptic.tap(); withAnimation(.spring) { tab = 1 } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.stack.fill").font(.wa(20)).foregroundStyle(WordAheadStyle.amber)
                            VStack(alignment: .leading, spacing: 2) { Text("복습 대기 \(store.dueWords.count)개").font(.wa(15, .bold)); Text("지금 복습하면 기억이 오래가요").font(.wa(13)).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(14).glass(RoundedRectangle(cornerRadius: 20), tint: WordAheadStyle.amber.opacity(0.22))
                    }.buttonStyle(PressableStyle()).transition(.scale(scale: 0.96).combined(with: .opacity))
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.up.right").foregroundStyle(WordAheadStyle.teal).frame(width: 32, height: 32).background(WordAheadStyle.mint, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("보고 싶은 영상으로 시작하기").font(.wa(17, .bold))
                            Text("YouTube 영상 링크를 붙여넣어 시작하세요. 자막 자동 수집은 영상·지역에 따라 제한될 수 있습니다.").font(.wa(12)).foregroundStyle(.secondary).lineSpacing(4)
                        }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.wa(14)).foregroundStyle(WordAheadStyle.youtube)
                        SelectAllURLField(text: $address, placeholder: "YouTube 영상 링크 붙여넣기", onSubmit: { addVideo() }).frame(height: 24).frame(maxWidth: .infinity, alignment: .leading)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if address.isEmpty {
                            PasteButton(payloadType: String.self) { items in if let v = items.first { withAnimation(.spring) { address = v }; Haptic.tap() } }.labelStyle(.titleOnly).buttonBorderShape(.capsule).tint(WordAheadStyle.teal).transition(.scale.combined(with: .opacity))
                        } else {
                            Button { address = "" } label: { Image(systemName: "xmark.circle.fill").font(.wa(18)).foregroundStyle(.secondary) }
                                .buttonStyle(.plain).accessibilityLabel("입력 지우기")
                        }
                    }.padding(.horizontal, 14).frame(minHeight: 48).background(WordAheadStyle.teal.opacity(0.035), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(WordAheadStyle.teal.opacity(0.24)))
                    Button {
                        addVideo()
                    } label: { HStack { if busy { ProgressView().tint(.white) }; Text("영상 추가").font(.wa(15, .bold)); Image(systemName: "arrow.right") }.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46).background(WordAheadStyle.teal, in: RoundedRectangle(cornerRadius: 12)) }.disabled(busy || NativeLearningStore.youtubeID(address) == nil)
                    if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
                }.padding(.horizontal, 16).padding(.vertical, 18).background(surface, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.12)))
                .frame(maxHeight: (store.videos.isEmpty || showInput) ? nil : 0).clipped().opacity((store.videos.isEmpty || showInput) ? 1 : 0)
                HStack { Text("학습할 영상").font(.wa(20, .bold)); Spacer()
                    if !store.videos.isEmpty { Button { Haptic.tap(); withAnimation(.spring) { showInput.toggle() } } label: { Label(LocalizedStringKey(showInput ? "닫기" : "영상 추가"), systemImage: showInput ? "xmark" : "plus").font(.wa(14, .semibold)).padding(.horizontal, 14).frame(height: 40).glass(Capsule()) }.buttonStyle(PressableStyle()) }
                }.padding(.top, 8)
                if store.videos.isEmpty { VStack(spacing: 10) { Image(systemName: "play.rectangle.on.rectangle").font(.wa(40)).foregroundStyle(WordAheadStyle.teal.opacity(0.7)); Text("영상이나 자막을 추가해 첫 학습을 시작하세요.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 28).transition(.opacity) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: hSize == .regular ? 2 : 1), spacing: 16) {
                ForEach(store.videos) { video in
                    NavigationLink { NativeReaderView(store: store, videoID: video.id) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            if let id = video.youtubeID, let url = URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") {
                                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(WordAheadStyle.teal.opacity(0.12)).modifier(Shimmer()).overlay(Image(systemName: "play.rectangle").font(.largeTitle)) }.frame(height: 180).clipped()
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(video.channel).font(.wa(12)).foregroundStyle(.secondary)
                                if video.title == "YouTube 자막 수집 중…" {
                                    Text("YouTube 자막 수집 중…").font(.wa(16, .semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                } else {
                                    Text(video.title).font(.wa(16, .semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                }
                                Divider()
                                if video.text.isEmpty {
                                    Label("자막 수집 필요", systemImage: "network").font(.wa(12)).foregroundStyle(WordAheadStyle.teal)
                                } else {
                                    Label("자막 저장됨 · 오프라인 복습", systemImage: "checkmark.circle").font(.wa(12)).foregroundStyle(WordAheadStyle.teal)
                                }
                            }.padding(14)
                        }.background(surface, in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.13)))
                    }.buttonStyle(PressableStyle()).zoomSource(id: video.id, in: zoom).overlay(alignment: .topTrailing) { Menu { Button("영상 삭제", role: .destructive) { Haptic.tap(); withAnimation { store.removeVideo(video.id) } } } label: { Image(systemName: "ellipsis").font(.wa(16, .bold)).foregroundStyle(.primary).frame(width: 44, height: 44).glass(Circle()) }.padding(8).accessibilityLabel("더보기") }.transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity)).contextMenu { Button("영상 삭제", role: .destructive) { Haptic.tap(); withAnimation { store.removeVideo(video.id) } } }
                }
                }
            }.padding(.horizontal, 18).padding(.bottom, 30).frame(maxWidth: hSize == .regular ? 1000 : 720).frame(maxWidth: .infinity).animation(.spring(response: 0.45, dampingFraction: 0.82), value: store.videos.map(\.id))
        }.background(WordAheadStyle.background)
        .buttonStyle(.plain).toolbar(.hidden, for: .navigationBar).scrollDismissesKeyboard(.interactively).refreshable { await store.refreshBilling() }
        .simultaneousGesture(TapGesture().onEnded { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) })
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("닫기") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
        .sheet(isPresented: $showImport) {
            NativeImportView(store: store, initialMode: 1)
                .environment(\.locale, Locale(identifier: language))
                .id(language)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                NativeSettingsView(store: store)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { showSettings = false } } }
            }
            .environment(\.locale, Locale(identifier: language))
        }
        .fullScreenCover(item: Binding(get: { filter.map { VocabularyFilter(id: $0) } }, set: { filter = $0?.id })) { item in
            NavigationStack {
                NativeVocabularyView(store: store, initialFilter: item.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { filter = nil } } }
            }
            .environment(\.locale, Locale(identifier: language))
            .id(language)
        }
        .navigationDestination(isPresented: Binding(get: { importedID != nil }, set: { if !$0 { importedID = nil } })) { if let importedID { NativeReaderView(store: store, videoID: importedID) } }
    }
    private func addVideo() {
        guard !busy, NativeLearningStore.youtubeID(address) != nil else { return }
        Task { busy = true; failure = nil; defer { busy = false }; do { let value = address; importedID = try await store.importYouTube(value); address = ""; showInput = false; Haptic.success() } catch { failure = error.localizedDescription; Haptic.error() } }
    }
    private func eyebrow(_ title: LocalizedStringKey) -> some View { Text(title).font(.wa(12, .bold)).tracking(1.6).foregroundStyle(WordAheadStyle.muted) }
    private func metric(_ title: String, count: Int, filter value: String) -> some View {
        Button { filter = value } label: {
            HStack(spacing: 8) { Text(LocalizedStringKey(title)).font(.wa(14, .semibold)).foregroundStyle(.secondary); Text("\(count)").font(.wa(20, .bold)).contentTransition(.numericText()).animation(.spring, value: count).foregroundStyle(WordAheadStyle.teal) }.frame(maxWidth: .infinity, alignment: .center).padding(.horizontal, 10).padding(.vertical, 12).background(value == "learning" ? WordAheadStyle.teal.opacity(0.14) : surface, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(WordAheadStyle.teal.opacity(value == "learning" ? 0.45 : 0.15)))
        }.buttonStyle(.plain)
    }
}

private struct SelectAllURLField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var onSubmit: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onSubmit: onSubmit) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: 16)
        field.keyboardType = .URL
        field.returnKeyType = .go
        field.delegate = context.coordinator
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let tripleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectAll(_:)))
        tripleTap.numberOfTapsRequired = 3
        tripleTap.cancelsTouchesInView = false
        field.addGestureRecognizer(tripleTap)
        return field
    }
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: 24)
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text; context.coordinator.onSubmit = onSubmit
        if field.text != text { field.text = text }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>; var onSubmit: () -> Void
        init(text: Binding<String>, onSubmit: @escaping () -> Void) { self.text = text; self.onSubmit = onSubmit }
        func textFieldShouldReturn(_ field: UITextField) -> Bool { field.resignFirstResponder(); onSubmit(); return true }
        @objc func changed(_ field: UITextField) { text.wrappedValue = field.text ?? "" }
        @objc func selectAll(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let field = gesture.view as? UITextField, !(field.text ?? "").isEmpty else { return }
            field.becomeFirstResponder()
            field.selectAll(nil)
        }
    }
}
struct VocabularyFilter: Identifiable { let id: String }

struct NativeImportView: View {
    @ObservedObject var store: NativeLearningStore
    var initialURL = ""
    var initialMode = 0
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var title = ""
    @State private var text = ""
    @State private var mode = 0
    @State private var busy = false
    @State private var failure: String?
    @State private var importedID: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker("추가 방법", selection: $mode) { Text("YouTube 링크").tag(0); Text("자막 직접 입력").tag(1) }.pickerStyle(.segmented)
                if mode == 0 {
                    Section("영상 주소") {
                        TextField("https://youtu.be/…", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        PasteButton(payloadType: String.self) { strings in if let value = strings.first { address = value } }
                    }
                    Text("수집 가능한 영어 자막을 저장합니다. 제한된 영상은 자막을 직접 입력할 수 있습니다.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Section("내 자막") {
                        TextField("제목", text: $title)
                        TextEditor(text: $text).frame(minHeight: 200).accessibilityLabel(Text("영어 자막 본문"))
                    }
                    Text("직접 작성했거나 사용 권한이 있는 자막을 입력하세요.").font(.footnote).foregroundStyle(.secondary)
                }
                if let failure { Section { Text(failure).foregroundStyle(.red); Button("자막 직접 입력하기") { mode = 1 } } }
                Section {
                    Button {
                        Task {
                            busy = true; failure = nil
                            defer { busy = false }
                            do {
                                if mode == 0 { importedID = try await store.importYouTube(address) }
                                else { importedID = store.addTranscript(title: title, text: text, youtubeID: NativeLearningStore.youtubeID(address)) }
                            } catch { failure = error.localizedDescription }
                        }
                    } label: {
                        HStack {
                            if busy { ProgressView() }
                            if mode == 0 {
                                Text("자막 가져오기")
                            } else {
                                Text("자막 저장하기")
                            }
                        }
                    }
                    .disabled(busy || (mode == 0 ? NativeLearningStore.youtubeID(address) == nil : text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }.navigationTitle("영상·자막 추가").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { store.sharedURL = ""; dismiss() } } }
            .navigationDestination(isPresented: Binding(get: { importedID != nil }, set: { if !$0 { importedID = nil } })) { if let importedID { NativeReaderView(store: store, videoID: importedID) } }
        }.onAppear { address = initialURL; mode = initialMode }
    }
}

enum WordAheadStyle {
    static let teal = Color(red: 0.086, green: 0.537, blue: 0.471)
    static let sheet = Color(red: 0.161, green: 0.212, blue: 0.231)
    static let mint = Color(red: 0.918, green: 0.961, blue: 0.945)
}

private struct CaptionFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { _, next in next } }
}

struct NativeReaderView: View {
    @ObservedObject var store: NativeLearningStore
    let videoID: String
    @AppStorage("nativeAppLanguage") private var language = "ko"
    @AppStorage("nativeReaderFontSize") private var fontSize = 20.0
    @State private var selected: WordMeaning?
    @State private var showPreview = false
    @State private var player: NativePlayerModel?
    @State private var loading = false
    @State private var failure: String?
    @State private var activeLine: Int?
    @State private var selectedLine: Int?
    @State private var frames: [Int: CGRect] = [:]
    @State private var pendingAlignment: Int?
    @StateObject private var scrollReference = NativeScrollReference()
    @State private var showTools = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    private var video: LearningVideo? { store.videos.first { $0.id == videoID } }
    var body: some View {
        Group {
            if let video {
                if hSize == .regular {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if let player { NativeYouTubePlayer(model: player).frame(height: 250) }
                            Spacer(minLength: 0)
                        }.frame(width: 460)
                        Rectangle().fill(WordAheadStyle.teal.opacity(0.18)).frame(width: 2)
                        VStack(spacing: 0) { content(video) }
                    }
                } else {
                    VStack(spacing: 0) {
                        if let player { NativeYouTubePlayer(model: player).frame(height: min(290, max(230, UIScreen.main.bounds.width * 9 / 16 + 32))) }
                        content(video)
                    }
                }
            } else { Text("자막을 찾을 수 없습니다.").foregroundStyle(.secondary) }
        }
        .background(WordAheadStyle.surface)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(selected != nil)
        .interactiveDismissDisabled(selected != nil)
        .simultaneousGesture(DragGesture(minimumDistance: 15).onChanged { value in
            if value.startLocation.x < 30, value.translation.width > 45,
               abs(value.translation.height) < value.translation.width * 0.5 {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { dismiss() }
            }
        })
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selected {
                NativeMeaningView(
                    store: store,
                    word: selected.id,
                    context: selected.definition,
                    source: video?.title ?? "",
                    onSpeak: {
                        let wasPlaying = player?.isPlaying ?? false
                        player?.command("pause")
                        store.speak(selected.id) {
                            if wasPlaying {
                                player?.command("play")
                            }
                        }
                    },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.2)) { self.selected = nil }
                    }
                )
                .id(selected.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $showPreview) {
            if let video {
                NativePreviewView(store: store, video: video)
                    .environment(\.locale, Locale(identifier: language))
                    .id(language)
            }
        }
        .task {
            guard let video else { return }
            if let id = video.youtubeID { player = NativePlayerModel(videoID: id, start: store.position(videoID)) }
            if video.text.isEmpty, let id = video.youtubeID {
                loading = true; defer { loading = false }
                do { _ = try await store.importYouTube("https://youtu.be/\(id)") } catch { failure = error.localizedDescription }
            }
        }
        .onDisappear { if let player { player.command("pause"); store.setPosition(videoID, time: player.time) } }
        .onChange(of: scenePhase) { phase in
            if phase == .background, let player { player.command("pause"); store.setPosition(videoID, time: player.time) }
            else if phase == .active { player?.command("resume") }
        }
    }
    @ViewBuilder private func content(_ video: LearningVideo) -> some View {
        header(video)
        Rectangle().fill(WordAheadStyle.teal.opacity(0.18)).frame(height: 2)
        if loading { ProgressView("자막을 가져오는 중…").padding() }
        if let failure { VStack { Text(failure).font(.footnote); NavigationLink("자막 직접 입력") { NativeImportView(store: store, initialURL: video.youtubeID.map { "https://youtu.be/\($0)" } ?? "") } }.padding() }
        transcript(video)
    }
    private func header(_ video: LearningVideo) -> some View {
        HStack(spacing: 4) {
            Button { if selected != nil { withAnimation { selected = nil } } else { dismiss() } } label: { Image(systemName: "arrow.left").font(.wa(21)).frame(width: 44, height: 44) }.accessibilityLabel(Text("이전 화면으로 돌아가기"))
            Button { showPreview = true } label: {
                HStack(spacing: 8) { Image(systemName: "book"); Text("먼저 살펴볼 단어").font(.wa(14, .semibold)); Text("\(store.previewWords(video).count)").font(.wa(12, .bold)).padding(.horizontal, 7).padding(.vertical, 3).background(WordAheadStyle.teal.opacity(0.12), in: Capsule()) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Button { fontSize = max(16, fontSize - 1) } label: {
                    Image(systemName: "minus").font(.wa(14, .bold)).frame(width: 40, height: 40).glass(Circle())
                }.accessibilityLabel(Text("글자 작게"))
                Button { fontSize = min(32, fontSize + 1) } label: {
                    Image(systemName: "plus").font(.wa(14, .bold)).frame(width: 40, height: 40).glass(Circle())
                }.accessibilityLabel(Text("글자 크게"))
            }
        }.buttonStyle(.plain).foregroundStyle(WordAheadStyle.teal).padding(.horizontal, 8).frame(height: 58)
    }
    private func transcript(_ video: LearningVideo) -> some View {
        GeometryReader { geometry in
            let measure = NativeCaptionMeasure(width: geometry.size.width - 36, size: fontSize)
            let lines = store.lines(video, layoutKey: "\(geometry.size.width)-\(fontSize)", fits: measure.fits)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: fontSize * 0.35) {
                        ForEach(lines) { line in
                            NativeTranscriptText(text: line.text, fontSize: fontSize, known: store.known, saved: Set(store.words.map(\.id)), start: line.start, estimated: line.estimated, onSeek: { if let start = line.start { player?.command("seek", value: start) } }) { word in
                                selectedLine = line.id
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                    selected = store.quickMeaning(word) ?? WordMeaning(id: word, definition: line.text)
                                }
                            }
                            .padding(.leading, activeLine == line.id ? 9 : 0)
                            .background(alignment: .leading) { if activeLine == line.id { Rectangle().fill(WordAheadStyle.teal).frame(width: 3) } }
                            .background(activeLine == line.id ? (scheme == .dark ? Color(red: 0.149, green: 0.282, blue: 0.239) : Color(red: 0.91, green: 0.957, blue: 0.937)) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .id(line.id)
                            .background(GeometryReader { frame in Color.clear.preference(key: CaptionFrameKey.self, value: [line.id: frame.frame(in: .named("transcript"))]) })
                        }
                    }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, geometry.size.height * 0.7)
                    .background(NativeScrollLocator(reference: scrollReference).frame(width: 0, height: 0))
                }.coordinateSpace(name: "transcript")
                .onPreferenceChange(CaptionFrameKey.self) { values in
                    frames = values
                    if let id = pendingAlignment, let frame = values[id], scrollReference.view != nil {
                        pendingAlignment = nil
                        scrollReference.align(top: frame.minY, offset: fontSize * 1.65 * 2 + 12)
                    }
                }
                .onReceive(player?.$time.eraseToAnyPublisher() ?? Just(0).eraseToAnyPublisher()) { time in
                    guard let next = lines.last(where: { ($0.start ?? .greatestFiniteMagnitude) <= time })?.id else { activeLine = nil; return }
                    guard next != activeLine else { return }; activeLine = next
                    let offset = fontSize * 1.65 * 2 + 12
                    if let frame = frames[next], scrollReference.view != nil {
                        scrollReference.align(top: frame.minY, offset: offset)
                    } else {
                        pendingAlignment = next
                        proxy.scrollTo(next, anchor: .top)
                    }
                }
                .onChange(of: geometry.size.height) { height in
                    if selected != nil, let id = selectedLine, let frame = frames[id], frame.maxY > height - 12 { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }
}

private struct NativePanelCorners: Shape {
    func path(in rect: CGRect) -> Path { Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 12, height: 12)).cgPath) }
}

struct NativeMeaningView: View {
    @ObservedObject var store: NativeLearningStore
    let word: String
    var context = ""
    var source = ""
    var onSpeak: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    @State private var meaning: WordMeaning?
    @State private var loading = true
    @State private var width = 353.0
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    private var definition: String { loading ? "사전에서 뜻을 찾는 중…" : meaning?.definition.isEmpty == false ? meaning!.definition : "오프라인 사전 미수록 · 다시 조회" }
    private let height: Double = 80
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(word).font(.wa(20, .bold)).lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
                Text(meaning?.phonetic ?? "").font(.wa(12)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1).frame(maxWidth: width * 0.35, alignment: .leading)
                Spacer(minLength: 0)
                Button { if let meaning { store.save(meaning, context: context, source: source) } } label: {
                    Image(systemName: store.words.contains { $0.id == word } ? "checkmark" : "plus").font(.wa(18, .medium)).foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.39)).frame(width: 26, height: 26).background(Color(red: 0.84, green: 0.94, blue: 0.90), in: RoundedRectangle(cornerRadius: 6))
                }.disabled(meaning?.definition.isEmpty != false).accessibilityLabel(Text("단어 저장"))
                if let part = meaning?.part, !part.isEmpty { Text(part).font(.wa(12, .semibold)).tracking(0.3).foregroundStyle(Color(red: 0.61, green: 0.76, blue: 0.71)).lineLimit(1).frame(maxWidth: 44) }
                Button {
                    if let onSpeak { onSpeak() } else { store.speak(word) }
                } label: { Image(systemName: "speaker.wave.2.fill").font(.wa(12)).foregroundStyle(Color(red: 0.33, green: 0.42, blue: 0.44)).frame(width: 30, height: 30).background(Color(red: 0.96, green: 0.97, blue: 0.96), in: Circle()) }.accessibilityLabel(Text("발음 듣기"))
                Button(action: close) { Image(systemName: "xmark").font(.wa(12, .bold)).foregroundStyle(Color(red: 0.33, green: 0.42, blue: 0.44)).frame(width: 30, height: 30).background(Color(red: 0.96, green: 0.97, blue: 0.96), in: Circle()) }.accessibilityLabel(Text("사전 닫기"))
            }.frame(height: 30)
            ScrollView {
                Group {
                    if loading {
                        Text("사전에서 뜻을 찾는 중…").font(.wa(14)).lineSpacing(2.6).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .topLeading).padding(.leading, 8)
                    } else if let def = meaning?.definition, !def.isEmpty {
                        Text(def).font(.wa(14)).lineSpacing(2.6).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .topLeading).padding(.leading, 8).textSelection(.enabled)
                    } else {
                        Text("오프라인 사전 미수록 · 다시 조회").font(.wa(14)).lineSpacing(2.6).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .topLeading).padding(.leading, 8)
                            .onTapGesture { Task { await lookup() } }
                    }
                }
            }.frame(height: height - 43, alignment: .top).padding(.top, 5)
        }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 4)
        .frame(height: height, alignment: .top).foregroundStyle(.white)
        .background(GeometryReader { geometry in Color.clear.onAppear { width = geometry.size.width - 40 }.onChange(of: geometry.size.width) { width = $0 - 40 } })
        .background { WordAheadStyle.sheet.clipShape(NativePanelCorners()).ignoresSafeArea(edges: .bottom) }
        .offset(y: max(0, dragOffset))
        .task(id: word) {
            if let quick = store.quickMeaning(word) {
                meaning = quick; loading = false
            }
            await lookup()
        }
    }
    private func close() { if let onClose { onClose() } else { dismiss() } }
    private func lookup() async {
        loading = true
        let value = await store.meaning(word)
        guard !Task.isCancelled else { return }; meaning = value; loading = false
    }
}

struct NativeVocabularyView: View {
    @ObservedObject var store: NativeLearningStore
    var initialFilter = "learning"
    @State private var filter = "learning"
    @State private var query = ""
    @AppStorage("nativeVocabularySort") private var sort = "script"
    private var filtered: [LearningWord] {
        let values = store.words.filter { (filter == "all" || ($0.known ? "known" : "learning") == filter) && (query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) || $0.definition.localizedCaseInsensitiveContains(query)) }
        return sort == "alphabetical" ? values.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending } : values
    }
    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Picker("단어 상태", selection: $filter) { Text("익히는 중").tag("learning"); Text("알고 있어요").tag("known") }.pickerStyle(.segmented)
                Menu {
                    Picker("단어 정렬", selection: $sort) {
                        Text("스크립트 순서").tag("script")
                        Text("알파벳 순서").tag("alphabetical")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").frame(width: 34, height: 32).background(WordAheadStyle.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }.accessibilityLabel(Text("단어 정렬"))
            }.padding(.horizontal)
            GeometryReader { geometry in
                let wordColumnWidth = min(170, max(125, (geometry.size.width - 82) * 0.43))
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 34, height: 1)
                        Text("단어").frame(width: wordColumnWidth, alignment: .leading)
                        Text("뜻").frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.wa(12, .bold)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 6)
                    Divider().padding(.horizontal, 16)
            List {
                if filtered.isEmpty { Text("저장한 단어가 없습니다.").foregroundStyle(.secondary) }
                ForEach(filtered) { word in
                    HStack(alignment: .center, spacing: 8) {
                        Button { store.mark(word.id, known: !word.known) } label: { Image(systemName: word.known ? "checkmark.square.fill" : "square").font(.wa(17)).foregroundStyle(word.known ? WordAheadStyle.teal : Color.gray).frame(width: 34, height: 36, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(Text(word.known ? "익히는 중으로 변경" : "알고 있는 단어로 변경"))
                        HStack(alignment: .center, spacing: 6) {
                            Text(word.id).font(.wa(16, .bold)).lineLimit(2).minimumScaleFactor(0.85).frame(maxWidth: .infinity, alignment: .leading)
                            Button { store.speak(word.id) } label: { Image(systemName: "speaker.wave.2.fill").font(.wa(12)).foregroundStyle(WordAheadStyle.teal).frame(width: 28, height: 28).background(Color.gray.opacity(0.06), in: Circle()) }.buttonStyle(.plain).accessibilityLabel(Text("발음"))
                        }.frame(width: wordColumnWidth, alignment: .leading)
                        Group {
                            if word.definition.isEmpty {
                                Text("뜻을 찾지 못했습니다").font(.wa(16)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(word.definition).font(.wa(16)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.padding(.vertical, 1).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)).swipeActions { Button("삭제", role: .destructive) { store.removeWord(word.id) } }
                    .task(id: word.id) {
                        if word.definition.isEmpty {
                            let meaning = await store.meaning(word.id, online: false)
                            if !Task.isCancelled, store.words.contains(where: { $0.id == word.id }), !meaning.definition.isEmpty { store.save(meaning) }
                        }
                    }
                }
            }.listStyle(.plain).environment(\.defaultMinListRowHeight, 0)
                }
            }
        }.tint(WordAheadStyle.teal).navigationTitle("내 단어장").searchable(text: $query, prompt: "단어 또는 한글 뜻 검색")
        .onAppear { filter = initialFilter == "known" ? "known" : "learning" }
    }
}

struct NativePreviewView: View {
    @ObservedObject var store: NativeLearningStore
    let video: LearningVideo
    @AppStorage("nativePreviewFontSize") private var fontSize = 16.0
    @State private var checked: Set<String> = []
    @State private var showMoveConfirmation = false
    @State private var moving = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("먼저 살펴볼 단어").font(.wa(20, .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Button { fontSize = max(14, fontSize - 1) } label: { Image(systemName: "minus").frame(width: 30, height: 32) }.accessibilityLabel(Text("글자 작게"))
                Button { fontSize = min(28, fontSize + 1) } label: { Image(systemName: "plus").frame(width: 30, height: 32) }.accessibilityLabel(Text("글자 크게"))
                Button { close() } label: { HStack(spacing: 2) { Text("닫기"); Text("×") } }.font(.wa(14)).padding(.horizontal, 12).frame(height: 40).background(WordAheadStyle.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 14)
            Divider().padding(.horizontal, 16)
            GeometryReader { geometry in
                let availableWidth = geometry.size.width - 32
                let wordColumnWidth = min(170, max(125, (availableWidth - 28) * 0.43))
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("").frame(width: 34)
                        Text("단어").font(.wa(12, .bold)).foregroundStyle(.secondary).frame(width: wordColumnWidth, alignment: .leading)
                        Text("뜻").font(.wa(12, .bold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
                    Divider().padding(.horizontal, 16)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.previewWords(video), id: \.self) { word in
                                NativePreviewRow(store: store, word: word, fontSize: fontSize, wordColumnWidth: wordColumnWidth, checked: Binding(get: { checked.contains(word) }, set: { value in if value { checked.insert(word) } else { checked.remove(word) } }))
                                Divider()
                            }
                        }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 20)
                    }
                }
            }
        }.tint(WordAheadStyle.teal)
        .interactiveDismissDisabled(!checked.isEmpty)
        .alert("선택한 단어를 알고 있어요로 표시할까요?", isPresented: $showMoveConfirmation) {
            Button("알고 있어요로 표시") { moveAndClose() }
            Button("표시하지 않고 닫기", role: .destructive) { dismiss() }
            Button("취소", role: .cancel) { }
        } message: { Text("선택한 단어 \(checked.count)개를 알고 있는 단어로 한글 뜻과 함께 저장합니다.") }
        .disabled(moving)
    }
    private func close() {
        if checked.isEmpty { dismiss() } else { showMoveConfirmation = true }
    }
    private func moveAndClose() {
        moving = true
        Task {
            let ordered = store.previewWords(video).filter(checked.contains)
            await store.savePreviewWords(ordered, video: video)
            moving = false
            dismiss()
        }
    }
}
struct NativePreviewRow: View {
    @ObservedObject var store: NativeLearningStore
    let word: String
    let fontSize: Double
    let wordColumnWidth: Double
    @Binding var checked: Bool
    @State private var meaning: WordMeaning?
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { checked.toggle() } label: {
                Image(systemName: checked ? "checkmark.square.fill" : "square").font(.wa(17)).foregroundStyle(checked ? WordAheadStyle.teal : Color.gray).frame(width: 34, height: 36, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Text(checked ? "선택 해제" : "단어 저장 선택"))
            HStack(alignment: .center, spacing: 6) {
                Text(word).font(.wa(fontSize, .bold)).lineLimit(2).minimumScaleFactor(0.85).frame(maxWidth: .infinity, alignment: .leading)
                Button { store.speak(word) } label: { Image(systemName: "speaker.wave.2.fill").font(.wa(12)).foregroundStyle(Color(red: 0.33, green: 0.42, blue: 0.44)).frame(width: 28, height: 28).background(Color.gray.opacity(0.06), in: Circle()) }.buttonStyle(.plain).accessibilityLabel(Text("발음"))
            }.frame(width: wordColumnWidth, alignment: .leading)
            Group {
                if let meaning {
                    if meaning.definition.isEmpty {
                        Text("뜻을 찾지 못했습니다").font(.wa(fontSize)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(meaning.definition).font(.wa(fontSize)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("저장된 뜻 확인 중…").font(.wa(fontSize)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.buttonStyle(.plain)
        }.padding(.vertical, 1)
        .task(id: word) {
            if let quick = store.quickMeaning(word) { meaning = quick }
            meaning = await store.meaning(word, online: true)
        }
    }
}

struct KnownWordsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct NativeSettingsView: View {
    @State private var showSubscription = false
    @ObservedObject var store: NativeLearningStore
    @AppStorage("nativeAppearance") private var appearance = "system"
    @AppStorage("nativeAppLanguage") private var language = "ko"
    @State private var showReset = false
    @State private var importing = false
    @State private var exporting = false
    @State private var document = KnownWordsDocument(data: Data())
    @State private var purchasing = false
    @AppStorage("reminderOn") private var reminderOn = false
    @AppStorage("reminderHour") private var reminderHour = 20
    var body: some View {
        Form {
            Section("학습 알림") {
                Toggle("매일 학습 알림", isOn: $reminderOn)
                if reminderOn { Picker("알림 시간", selection: $reminderHour) { ForEach(6..<24, id: \.self) { Text("\($0)시").tag($0) } } }
            }.onChange(of: reminderOn) { on in Task { if await StudyReminder.set(enabled: on, hour: reminderHour) == false { reminderOn = false } } }
            .onChange(of: reminderHour) { h in Task { _ = await StudyReminder.set(enabled: reminderOn, hour: h) } }
            Section("화면") {
                Picker("앱 표시 언어", selection: $language) {
                    ForEach([("ko", "한국어"), ("en", "English"), ("de", "Deutsch"), ("ja", "日本語"), ("zh-Hans", "简体中文"), ("es-MX", "Español"), ("fr-FR", "Français"), ("it", "Italiano"), ("pt-BR", "Português"), ("ru", "Русский"), ("nl", "Nederlands"), ("th", "ไทย")], id: \.0) { item in Text(item.1).tag(item.0) }
                }
                Picker("화면 모드", selection: $appearance) { Text("시스템 설정").tag("system"); Text("밝게").tag("light"); Text("어둡게").tag("dark") }
                Text("자막과 먼저 살펴볼 단어의 글자 크기는 해당 화면에서 조절할 수 있습니다.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("오프라인 학습") { Label("내장 영한 사전 49,527개", systemImage: "checkmark.seal"); Text("저장한 자막, 단어와 한글 뜻은 인터넷 없이 열 수 있습니다. 영상 재생과 최초 자막 수집은 인터넷이 필요합니다.").font(.footnote).foregroundStyle(.secondary) }
            Section("WordAhead Plus") {
                Text("새 영상의 단어 분석·단어장 생성을 제한 없이 이용하세요.")
                Text("무료로 하루 새 영상 2개를 분석할 수 있습니다. 기존 자막·단어장 복습과 영상 재생은 계속 이용할 수 있습니다.").font(.footnote).foregroundStyle(.secondary)
                if store.billing["premium"] as? Bool == true { Label("Plus 이용 중", systemImage: "checkmark.seal.fill") }
                else if #available(iOS 17.0, *) {
                    Button("연간 구독") { showSubscription = true }
                }
                else if store.billing["available"] as? Bool == true {
                    Button { purchase("purchase") } label: {
                        HStack(spacing: 4) {
                            Text("연간 구독")
                            if let price = store.billing["price"] as? String, !price.isEmpty {
                                Text("· \(price)")
                            }
                        }
                    }.disabled(purchasing)
                } else {
                    Button("연간 구독 · 상품 다시 확인") { Task { purchasing = true; await store.refreshBilling(); purchasing = false } }.disabled(purchasing)
                    Text("App Store에서 구독 상품을 불러오고 있습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.").font(.footnote)
                    if let detail = store.billing["catalogError"] as? String, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Button("구매 복원") { purchase("restore") }.disabled(purchasing)
                Link("구독 관리", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                if purchasing { ProgressView() }
                Text("자동 갱신 구독이며 취소 전까지 매년 갱신됩니다. 결제 금액은 Apple 결제 화면에서 확인하세요.").font(.caption).foregroundStyle(.secondary)
                Link("이용약관", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            Section("학습 데이터") {
                Button("알고 있는 단어 내보내기") { do { document = KnownWordsDocument(data: try store.backup()); exporting = true } catch { store.error = error.localizedDescription } }
                Button("알고 있는 단어 가져오기") { importing = true }
                Button("학습 데이터 삭제", role: .destructive) { showReset = true }
            }
            Section("정보") {
                Link("개인정보처리방침", destination: URL(string: "https://outinletter.github.io/wordahead/privacy.html")!)
                Link("도움말 및 문의", destination: URL(string: "https://outinletter.github.io/wordahead/support.html")!)
                NavigationLink("오픈소스 사전 출처·라이선스") { NativeLicenseView().environment(\.locale, Locale(identifier: language)).id(language) }
                HStack(spacing: 4) {
                    Text("버전")
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                }.foregroundStyle(.secondary)
            }
        }.navigationTitle("설정")
        .sheet(isPresented: $showSubscription, onDismiss: { Task { await store.refreshBilling() } }) {
            if #available(iOS 17.0, *) {
                SubscriptionStoreView(groupID: WordAheadSubscriptionService.groupID)
                    .storeButton(.visible, for: .restorePurchases)
                    .subscriptionStorePolicyDestination(url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!, for: .termsOfService)
                    .subscriptionStorePolicyDestination(url: URL(string: "https://outinletter.github.io/wordahead/privacy.html")!, for: .privacyPolicy)
            }
        }
        .environment(\.locale, Locale(identifier: language))
        .task { await store.refreshBilling() }
        .confirmationDialog("저장한 자막과 단어장, 학습 기록을 모두 삭제할까요?", isPresented: $showReset, titleVisibility: .visible) { Button("모두 삭제", role: .destructive) { store.reset() }; Button("취소", role: .cancel) {} }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "WordAhead-known-words") { result in if case .failure(let error) = result { store.error = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }; try store.importBackup(Data(contentsOf: url)) } catch { store.error = error.localizedDescription }
        }
    }
    private func purchase(_ action: String) { Task { purchasing = true; await store.purchase(action); purchasing = false } }
}
struct NativeLicenseView: View {
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) { ForEach(["NOTICE.md", "MPL-2.0.txt"], id: \.self) { file in if let root = Bundle.main.url(forResource: "Web", withExtension: nil), let text = try? String(contentsOf: root.appendingPathComponent("dictionary/\(file)")) { Text(text).font(.footnote).textSelection(.enabled) } } }.padding() }.navigationTitle("오픈소스 라이선스")
    }
}
