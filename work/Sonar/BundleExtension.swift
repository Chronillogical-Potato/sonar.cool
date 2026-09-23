import Foundation

// Bundle.sonarResources resolves to Bundle.module in SPM builds (where resources
// live in a generated Sonar_Sonar.bundle) and Bundle.main in script builds (where
// the build script copies them directly into Contents/Resources/).
#if SWIFT_PACKAGE
extension Bundle {
    static let sonarResources: Bundle = .module
}
#else
extension Bundle {
    static let sonarResources: Bundle = .main
}
#endif
