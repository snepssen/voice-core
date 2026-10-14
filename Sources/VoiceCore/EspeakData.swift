import Foundation

/// espeak-ng's data, as every snepssen voice was trained with it: revision
/// 724808c's dictionaries, shipped once, in this package.
public enum EspeakData {
    /// The folder `EspeakPhonemizer` reads, inside this package's resources.
    public static var directory: URL? { Bundle.module.url(forResource: "espeak-ng-data", withExtension: nil) }
}
