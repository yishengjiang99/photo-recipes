import Foundation

enum VoiceSettings {
    /// Legacy key — Camera voice always runs Auto Optimize (shared apply path).
    private static let autoOptimizeKey = "voice.autoOptimizeAfterVoice"

    /// Camera dictate always calls runOptimize(); this flag is no longer a gate.
    static var autoOptimizeAfterVoice: Bool {
        get { true }
        set { UserDefaults.standard.set(newValue, forKey: autoOptimizeKey) }
    }
}
