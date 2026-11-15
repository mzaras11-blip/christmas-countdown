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

/// JS -> native ads bridge for the Advent "door peek". Web code calls:
///   window.webkit.messageHandlers.ads.postMessage({action: "peekDoor", door: N})
/// Native answers exactly once via:
///   window.onAdReward('peek')      — the rewarded ad was watched; open the door
///   window.onAdUnavailable('peek') — no ad / dismissed early; the web layer
///                                    shows its "opens tomorrow" note instead
/// Unlike ARCADE's hint bridge, a missing presenter or ad never grants
/// the reward silently — the peek is the ad's whole point.
final class AdsBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "ads",
              let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }
        guard action == "peekDoor" else { return }
        DispatchQueue.main.async { [weak self] in self?.showPeek() }
    }

    private func showPeek() {
        guard let vc = topViewController() else { notifyUnavailable(); return }
        AdManager.shared.showRewarded(from: vc) { [weak self] earned in
            if earned { self?.notifyReward() } else { self?.notifyUnavailable() }
        }
    }

    private func notifyReward() {
        webView?.evaluateJavaScript("if(window.onAdReward)window.onAdReward('peek')",
                                    completionHandler: nil)
    }

    private func notifyUnavailable() {
        webView?.evaluateJavaScript("if(window.onAdUnavailable)window.onAdUnavailable('peek')",
                                    completionHandler: nil)
    }
}

/// Holds all JS bridges for the web view's lifetime.
final class WebCoordinator: NSObject {
    let haptics = HapticsBridge()
    let ads = AdsBridge()
}

/// Full-screen web view hosting the bundled countdown page at web/index.html.
/// This is the entire app UI — a web-bridge shell whose only SDK is
/// Google Mobile Ads (banner + the Advent door-peek rewarded ad).
struct WebView: UIViewRepresentable {
    func makeCoordinator() -> WebCoordinator { WebCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator.haptics, name: "haptics")
        config.userContentController.add(context.coordinator.ads, name: "ads")

        let webView = WKWebView(frame: .zero, configuration: config)
        // Wire the ads bridge back to this web view for peek callbacks.
        context.coordinator.ads.webView = webView
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
/// background while the page loads. While a real banner ad is on screen
/// the web view lifts by the banner's height so the ad strip sits below
/// the app content — the page never hides behind it.
struct RootView: View {
    @ObservedObject private var adManager = AdManager.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            WebView()
                .ignoresSafeArea()
                .padding(.bottom, adManager.bannerLoaded ? 50 : 0)
                .animation(.easeInOut(duration: 0.25), value: adManager.bannerLoaded)
            AdBannerStrip()
        }
        .ignoresSafeArea(edges: .bottom)
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
    init() {
        // Ads start only after the App Tracking Transparency decision
        // (Guideline 5.1.2(i)): AdManager presents the ATT request
        // first, then starts the Google Mobile Ads SDK and loads the
        // first ads.
        AdManager.shared.beginAdFlow()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
