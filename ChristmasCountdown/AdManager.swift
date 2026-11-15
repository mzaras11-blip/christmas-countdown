import Foundation
import SwiftUI
import Combine
import AppTrackingTransparency
import AdSupport
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// Returns the top-most view controller for presenting ads.
func topViewController() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first?.rootViewController else { return nil }
    var vc = root
    while let presented = vc.presentedViewController { vc = presented }
    return vc
}

/// Central ad coordinator for Santa Countdown Timer.
///
/// Ported from the SWISH ARCADE shell's AdManager (same publisher, same
/// flow): Google AdMob via the swift-package-manager-google-mobile-ads
/// SPM package; without the SDK it runs a clearly-labeled simulated flow
/// so the shell stays testable. This app uses two formats only:
///   * one banner pinned under the web view (shown only once a real ad
///     has loaded — an empty slot never takes screen space), and
///   * one rewarded ad behind the Advent calendar's "peek a day early".
///
/// Uses this app's own AdMob units (created 2026-11-15); the AdMob app
/// ID lives in Info.plist as GADApplicationIdentifier.
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    // MARK: Production ad units (AdMob account mzaras11@gmail.com)
    private let rewardedAdUnitID = "ca-app-pub-9461680459080238/6096085070"
    let bannerAdUnitID = "ca-app-pub-9461680459080238/2596803706"

    @Published var rewardedReady = false

    /// True only once a real banner ad has actually loaded. The banner
    /// strip exists on screen only while this is true (Michael's rule,
    /// 2026-10-19: show the ad only when there is an actual ad).
    @Published var bannerLoaded = false
    private var bannerHasLoaded = false

    #if canImport(GoogleMobileAds)
    private var rewardedAd: GADRewardedAd?
    private var rewardedCompletion: ((Bool) -> Void)?
    private var rewardedEarned = false
    #endif

    var adsAreReal: Bool {
        #if canImport(GoogleMobileAds)
        return true
        #else
        return false
        #endif
    }

    private var adFlowStarted = false

    private override init() {
        super.init()
        // Ads are NOT loaded here. Guideline 5.1.2(i): the App Tracking
        // Transparency request must come first — see beginAdFlow().
    }

    /// Entry point for the ad flow, called once from the app's init.
    /// Presents the ATT permission request (after a short settle delay so
    /// the first screen is on display); only after the user decides does
    /// the ads SDK start and the first ads load. A "no" still gets ads —
    /// they are simply not personalized.
    func beginAdFlow() {
        guard !adFlowStarted else { return }
        adFlowStarted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if #available(iOS 14, *) {
                ATTrackingManager.requestTrackingAuthorization { _ in
                    DispatchQueue.main.async { AdManager.shared.startAds() }
                }
            } else {
                AdManager.shared.startAds()
            }
        }
    }

    private func startAds() {
        #if canImport(GoogleMobileAds)
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        #endif
        loadRewarded()
    }

    // MARK: - Rewarded (watch ad -> peek at tomorrow's Advent door)

    func loadRewarded() {
        #if canImport(GoogleMobileAds)
        GADRewardedAd.load(withAdUnitID: rewardedAdUnitID, request: GADRequest()) { [weak self] ad, _ in
            DispatchQueue.main.async {
                self?.rewardedAd = ad
                self?.rewardedReady = (ad != nil)
            }
        }
        #else
        rewardedReady = true // mock ads are always "ready"
        #endif
    }

    /// Presents a rewarded ad. `completion` fires exactly once: `true`
    /// only when the reward was earned, `false` when no ad is available,
    /// the ad fails to present, or the viewer dismisses it early — so
    /// the web layer can always resolve the peek tap one way or the
    /// other (ARCADE's game bridge never calls back on dismissal; this
    /// app's peek needs the negative answer to show its "opens
    /// tomorrow" note, hence the full-screen delegate below).
    func showRewarded(from root: UIViewController, completion: @escaping (Bool) -> Void) {
        #if canImport(GoogleMobileAds)
        guard let ad = rewardedAd else { completion(false); return }
        rewardedAd = nil
        rewardedReady = false
        rewardedEarned = false
        rewardedCompletion = completion
        ad.fullScreenContentDelegate = self
        ad.present(fromRootViewController: root) { [weak self] in
            self?.rewardedEarned = true
        }
        #else
        // Simulated ad (SDK not linked): a beat of "watching", then the
        // reward is granted so the peek flow stays testable end to end.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { completion(true) }
        #endif
    }

    #if canImport(GoogleMobileAds)
    /// Settles the pending rewarded presentation exactly once and
    /// preloads the next ad.
    private func finishRewarded() {
        guard let completion = rewardedCompletion else { return }
        rewardedCompletion = nil
        let earned = rewardedEarned
        rewardedEarned = false
        loadRewarded()
        completion(earned)
    }
    #endif

    // MARK: - Banner

    #if canImport(GoogleMobileAds)
    private weak var bannerView: GADBannerView?

    func makeBanner(delegate: GADBannerViewDelegate?) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = bannerAdUnitID
        banner.delegate = delegate
        bannerView = banner
        banner.load(GADRequest())
        return banner
    }

    /// A real banner ad arrived — the strip may show.
    func noteBannerLoaded() {
        bannerHasLoaded = true
        bannerLoaded = true
    }

    /// A banner load failed (for example no ad available). Before the
    /// first success the strip stays hidden; afterwards the on-screen ad
    /// is kept. Either way, retry later so one empty moment does not
    /// disable banners for the whole session.
    func noteBannerFailed() {
        if !bannerHasLoaded { bannerLoaded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            self?.bannerView?.load(GADRequest())
        }
    }
    #endif
}

#if canImport(GoogleMobileAds)
extension AdManager: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        finishRewarded()
    }

    func ad(_ ad: GADFullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        finishRewarded()
    }
}

/// SwiftUI wrapper for an AdMob banner.
struct BannerAdView: UIViewRepresentable {
    func makeUIView(context: Context) -> GADBannerView {
        let banner = AdManager.shared.makeBanner(delegate: context.coordinator)
        banner.rootViewController = topViewController()
        return banner
    }
    func updateUIView(_ uiView: GADBannerView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, GADBannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            AdManager.shared.noteBannerLoaded()
        }
        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            AdManager.shared.noteBannerFailed()
        }
    }
}
#endif

/// The banner strip under the web view. It is always in the layout but
/// takes zero height (and ignores touches) until a real ad has loaded,
/// so the web content never hides behind an empty slot.
#if canImport(GoogleMobileAds)
struct AdBannerStrip: View {
    @ObservedObject private var adManager = AdManager.shared

    var body: some View {
        BannerAdView()
            .frame(height: adManager.bannerLoaded ? 50 : 0)
            .opacity(adManager.bannerLoaded ? 1 : 0)
            .allowsHitTesting(adManager.bannerLoaded)
            .clipped()
    }
}
#else
struct AdBannerStrip: View {
    var body: some View { EmptyView() }
}
#endif
