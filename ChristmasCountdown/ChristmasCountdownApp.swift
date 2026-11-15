import SwiftUI
import WebKit

/// JS -> native haptics bridge. Web code can call:
///   window.webkit.messageHandlers.haptics.postMessage("light" | "medium" | "heavy"
///       | "success" | "warning" | "error" | "selection")
final class HapticsBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "haptics" else { return }
        let style = (message.body as? String) ?? "light"
        DispatchQueue.main.async {
            switch style {
            case "heavy":
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            case "medium":
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case "success":
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "warning":
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case "error":
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case "selection":
                UISelectionFeedbackGenerator().selectionChanged()
            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}

/// Holds all JS bridges for the web view's lifetime.
final class WebCoordinator: NSObject {
    let haptics = HapticsBridge()
}

/// Full-screen web view hosting the bundled countdown page at web/index.html.
/// This is the entire app UI — a clean web-bridge shell with no SDKs.
struct WebView: UIViewRepresentable {
    func makeCoordinator() -> WebCoordinator { WebCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator.haptics, name: "haptics")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear

        if let url = Bundle.main.url(forResource: "index", withExtension: "html",
                                     subdirectory: "web") {
            // Bundled copy — works fully offline (the forecast is the only
            // network feature, and it degrades gracefully without a signal).
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Root layout. The web view fills the screen over the app's deep-green
/// festive gradient, so no gap can ever show a plain white window
/// background while the page loads.
struct RootView: View {
    var body: some View {
        WebView()
            .ignoresSafeArea()
            .background(
                LinearGradient(
                    colors: [Color(red: 0.03, green: 0.13, blue: 0.08),
                             Color(red: 0.05, green: 0.22, blue: 0.13),
                             Color(red: 0.02, green: 0.08, blue: 0.05)],
                    startPoint: .top, endPoint: .bottom)
            )
    }
}

@main
struct ChristmasCountdownApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
