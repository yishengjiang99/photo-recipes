import Foundation

enum VoiceSettings {
    private static let autoOptimizeKey = "voice.autoOptimizeAfterVoice"

    /// When true, finishing a Camera dictate can kick off Auto Optimize. Default OFF.
    static var autoOptimizeAfterVoice: Bool {
        get { UserDefaults.standard.bool(forKey: autoOptimizeKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoOptimizeKey) }
    }
}
