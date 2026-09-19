import Foundation
import CoreGraphics

struct RecommendResponse: Codable, Hashable {
    var presetId: String?
    var reason: String?
    var tips: [String]?
    var preset: Recipe?
    var model: String?
    var vision: Bool?
    var error: String?
    var code: String?

    var teachWhy: String?
    var phoneTargets: PhoneTargets?
    var coachOnly: CoachOnly?
    var panCue: PanCue?
    var senseSummary: String?
}

/// Wire format locked to server PR #21 / main — all keys optional; unknown keys ignored.
struct PhoneTargets: Codable, Hashable {
    var shutter: String?
    var exposureDurationSec: Double?
    var iso: String?
    var ev: String?
    var whiteBalance: WhiteBalanceTarget?
    var focusMode: String?
    var zoom: Double?
    var focusPoint: FocusPointNorm?
    var lensPosition: Double?
    var torch: TorchTarget?
    var flash: String?
    var lowLightBoost: Bool?
    var videoHDR: Bool?
    var cameraDevice: String?
    var frameRate: Double?
    var preferFormatHint: String?
    var bracket: BracketTarget?
    var monitorSubjectAreaChange: Bool?
    var maxPhotoDimensions: MaxPhotoDimensions?
    var previewLUT: String?
    var simulatedAperture: Double?

    enum CodingKeys: String, CodingKey {
        case shutter, exposureDurationSec, iso, ev, whiteBalance, focusMode, zoom, focusPoint
        case lensPosition, torch, flash, lowLightBoost, videoHDR, cameraDevice
        case frameRate, preferFormatHint, bracket, monitorSubjectAreaChange
        case maxPhotoDimensions, previewLUT, simulatedAperture
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shutter = try c.decodeIfPresent(String.self, forKey: .shutter)
        exposureDurationSec = Self.dbl(c, .exposureDurationSec)
        iso = Self.strOrNum(c, .iso)
        ev = Self.strOrNum(c, .ev)
        whiteBalance = try c.decodeIfPresent(WhiteBalanceTarget.self, forKey: .whiteBalance)
        focusMode = try c.decodeIfPresent(String.self, forKey: .focusMode)
        focusPoint = try c.decodeIfPresent(FocusPointNorm.self, forKey: .focusPoint)
        zoom = Self.decodeZoom(c)
        lensPosition = Self.dbl(c, .lensPosition)
        torch = try c.decodeIfPresent(TorchTarget.self, forKey: .torch)
        flash = try c.decodeIfPresent(String.self, forKey: .flash)
        lowLightBoost = try c.decodeIfPresent(Bool.self, forKey: .lowLightBoost)
        videoHDR = try c.decodeIfPresent(Bool.self, forKey: .videoHDR)
        cameraDevice = try c.decodeIfPresent(String.self, forKey: .cameraDevice)
        frameRate = Self.dbl(c, .frameRate)
        preferFormatHint = try c.decodeIfPresent(String.self, forKey: .preferFormatHint)
        bracket = try c.decodeIfPresent(BracketTarget.self, forKey: .bracket)
        monitorSubjectAreaChange = try c.decodeIfPresent(Bool.self, forKey: .monitorSubjectAreaChange)
        maxPhotoDimensions = try c.decodeIfPresent(MaxPhotoDimensions.self, forKey: .maxPhotoDimensions)
        previewLUT = try c.decodeIfPresent(String.self, forKey: .previewLUT)
        simulatedAperture = Self.dbl(c, .simulatedAperture)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(shutter, forKey: .shutter)
        try c.encodeIfPresent(exposureDurationSec, forKey: .exposureDurationSec)
        try c.encodeIfPresent(iso, forKey: .iso)
        try c.encodeIfPresent(ev, forKey: .ev)
        try c.encodeIfPresent(whiteBalance, forKey: .whiteBalance)
        try c.encodeIfPresent(focusMode, forKey: .focusMode)
        try c.encodeIfPresent(zoom, forKey: .zoom)
        try c.encodeIfPresent(focusPoint, forKey: .focusPoint)
        try c.encodeIfPresent(lensPosition, forKey: .lensPosition)
        try c.encodeIfPresent(torch, forKey: .torch)
        try c.encodeIfPresent(flash, forKey: .flash)
        try c.encodeIfPresent(lowLightBoost, forKey: .lowLightBoost)
        try c.encodeIfPresent(videoHDR, forKey: .videoHDR)
        try c.encodeIfPresent(cameraDevice, forKey: .cameraDevice)
        try c.encodeIfPresent(frameRate, forKey: .frameRate)
        try c.encodeIfPresent(preferFormatHint, forKey: .preferFormatHint)
        try c.encodeIfPresent(bracket, forKey: .bracket)
        try c.encodeIfPresent(monitorSubjectAreaChange, forKey: .monitorSubjectAreaChange)
        try c.encodeIfPresent(maxPhotoDimensions, forKey: .maxPhotoDimensions)
        try c.encodeIfPresent(previewLUT, forKey: .previewLUT)
        try c.encodeIfPresent(simulatedAperture, forKey: .simulatedAperture)
    }

    private static func decodeZoom(_ c: KeyedDecodingContainer<CodingKeys>) -> Double? {
        if let d = dbl(c, .zoom) { return d }
        guard let s = try? c.decodeIfPresent(String.self, forKey: .zoom) else { return nil }
        let cleaned = s.lowercased()
            .replacingOccurrences(of: "×", with: "")
            .replacingOccurrences(of: "x", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func dbl(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func strOrNum(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) {
            return d == d.rounded() ? String(Int(d)) : String(d)
        }
        return nil
    }
}

struct TorchTarget: Codable, Hashable {
    var mode: String
    var level: Double?

    enum CodingKeys: String, CodingKey { case mode, level }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "off"
        if let d = try? c.decodeIfPresent(Double.self, forKey: .level) {
            level = d
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .level) {
            level = Double(i)
        } else {
            level = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(level, forKey: .level)
    }
}

struct BracketTarget: Codable, Hashable {
    var stops: [Double]?
    var count: Int?

    enum CodingKeys: String, CodingKey { case stops, count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let arr = try? c.decodeIfPresent([Double].self, forKey: .stops) {
            stops = arr
        } else if let ints = try? c.decodeIfPresent([Int].self, forKey: .stops) {
            stops = ints.map(Double.init)
        } else {
            stops = nil
        }
        count = try c.decodeIfPresent(Int.self, forKey: .count)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(stops, forKey: .stops)
        try c.encodeIfPresent(count, forKey: .count)
    }
}

struct MaxPhotoDimensions: Codable, Hashable {
    var width: Double
    var height: Double
}

enum WhiteBalanceTarget: Codable, Hashable {
    case mode(String)
    case temperatureTint(temperature: Double?, tint: Double?)
    case gains(redGain: Double?, greenGain: Double?, blueGain: Double?)

    private enum ObjectKeys: String, CodingKey {
        case temperature, tint, redGain, greenGain, blueGain
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let s = try? single.decode(String.self) {
            self = .mode(s)
            return
        }
        let c = try decoder.container(keyedBy: ObjectKeys.self)
        let temp = try c.decodeIfPresent(Double.self, forKey: .temperature)
        let tint = try c.decodeIfPresent(Double.self, forKey: .tint)
        let r = try c.decodeIfPresent(Double.self, forKey: .redGain)
        let g = try c.decodeIfPresent(Double.self, forKey: .greenGain)
        let b = try c.decodeIfPresent(Double.self, forKey: .blueGain)
        let hasGains = r != nil || g != nil || b != nil
        let hasTT = temp != nil || tint != nil
        if hasGains {
            self = .gains(redGain: r, greenGain: g, blueGain: b)
        } else if hasTT {
            self = .temperatureTint(temperature: temp, tint: tint)
        } else {
            self = .mode("auto")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .mode(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .temperatureTint(let temperature, let tint):
            var c = encoder.container(keyedBy: ObjectKeys.self)
            try c.encodeIfPresent(temperature, forKey: .temperature)
            try c.encodeIfPresent(tint, forKey: .tint)
        case .gains(let redGain, let greenGain, let blueGain):
            var c = encoder.container(keyedBy: ObjectKeys.self)
            try c.encodeIfPresent(redGain, forKey: .redGain)
            try c.encodeIfPresent(greenGain, forKey: .greenGain)
            try c.encodeIfPresent(blueGain, forKey: .blueGain)
        }
    }
}

struct FocusPointNorm: Codable, Hashable {
    var x: Double
    var y: Double
    var cgPoint: CGPoint {
        CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

struct CoachOnly: Codable, Hashable {
    var aperture: String?
    var nd: String?
    var tripod: Bool?
    var notes: String?
}

struct PanCue: Codable, Hashable {
    var direction: String?
    var note: String?
}

struct RecommendRequest: Encodable {
    var message: String
    var favorites: [String]
    var image: String?
}
