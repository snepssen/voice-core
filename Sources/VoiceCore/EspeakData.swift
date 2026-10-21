import Foundation

/// espeak-ng's data, as every snepssen voice was trained with it: revision
/// 724808c's dictionaries, shipped once, in this package.
public enum EspeakData {
    /// The folder `EspeakPhonemizer` reads, inside this package's resources,
    /// or nil if the resource bundle is not where any app puts it.
    ///
    /// **Not `Bundle.module`.** SwiftPM generates that accessor per
    /// toolchain, and what it searches has changed: a current one looks in
    /// `Bundle.main.resourceURL`, the GitHub macOS runner's looked only at
    /// the `.app` root and its own absolute `/Users/runner/...` build path --
    /// and both end in `fatalError` rather than nil. Gateway Forge 5.3.1 was
    /// built there and quit on the first render on every Mac but the runner,
    /// while its own readiness check said the voice was ready. A local build
    /// cannot reproduce it, so the search is written here, where it is the
    /// same on every toolchain and can only ever return nil.
    public static var directory: URL? {
        for root in bundleRoots {
            let candidate = root.appending(path: bundleName)
            if let bundle = Bundle(url: candidate),
               let data = bundle.url(forResource: "espeak-ng-data", withExtension: nil) {
                return data
            }
        }
        return nil
    }

    /// SwiftPM's name for this target's resource bundle.
    static let bundleName = "VoiceCore_VoiceCore.bundle"

    /// Every folder an app, a framework, a command-line tool or a test run
    /// keeps this package's resource bundle in, most specific first:
    /// `Contents/Resources` in a macOS app and the app root on iOS (both are
    /// `resourceURL`), the `.app` root where an older toolchain expected it,
    /// beside the executable for `swift run`, and for a framework or a test
    /// bundle, inside it or beside it in the build products.
    static var bundleRoots: [URL] {
        let linked = Bundle(for: BundleFinder.self)
        return [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
            linked.resourceURL,
            linked.bundleURL.deletingLastPathComponent(),
        ].compactMap { $0 }
    }

    private final class BundleFinder {}
}
