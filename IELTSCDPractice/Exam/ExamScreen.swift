import SwiftData
import SwiftUI
import WebKit

/// 全屏机考界面（界面本身由 ExamEngine 渲染，严格对照 IELTS 官方机考）。
struct ExamScreen: View {
    let session: ExamSession
    var onFinishMock: (UUID) -> Void = { _ in }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ProgressView("正在准备试题…")
                .controlSize(.large)
            ExamWebContainer(session: session, modelContext: modelContext, onFinishMock: onFinishMock) {
                dismiss()
            }
        }
        .ignoresSafeArea()
        .background(Color.white.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

private struct ExamWebContainer: UIViewRepresentable {
    let session: ExamSession
    let modelContext: ModelContext
    let onFinishMock: (UUID) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> ExamController {
        ExamController(session: session)
    }

    func makeUIView(context: Context) -> ExamWebView {
        let controller = context.coordinator
        controller.modelContext = modelContext
        controller.onClose = onClose
        controller.onFinishMock = onFinishMock

        let configuration = WKWebViewConfiguration()
        let engineRoot = Bundle.main.url(forResource: "ExamEngine", withExtension: nil)!
        configuration.setURLSchemeHandler(
            EngineSchemeHandler(engineRoot: engineRoot, contentRoot: ContentStore.shared.rootURL,
                                audioRoot: AudioStore.directory),
            forURLScheme: EngineSchemeHandler.scheme
        )
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(WeakMessageHandler(controller), name: "exam")
        configuration.dataDetectorTypes = []
        configuration.preferences.isTextInteractionEnabled = true
        // 官方机考没有任何写作辅助：关闭 Apple 写作工具
        if #available(iOS 18.0, *) {
            configuration.writingToolsBehavior = .none
        }

        let webView = ExamWebView(frame: .zero, configuration: configuration)
        webView.controller = controller
        webView.isOpaque = true
        webView.backgroundColor = .white
        webView.alpha = 0   // 引擎渲染完成后淡入
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        controller.webView = webView
        webView.load(URLRequest(url: EngineSchemeHandler.entryURL))
        return webView
    }

    func updateUIView(_ webView: ExamWebView, context: Context) {}

    static func dismantleUIView(_ webView: ExamWebView, coordinator: ExamController) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "exam")
        webView.controller = nil
    }
}
