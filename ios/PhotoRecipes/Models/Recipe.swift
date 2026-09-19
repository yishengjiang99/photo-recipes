import Foundation

enum TechniqueTag: String, Codable, CaseIterable, Identifiable, Hashable {
    case hdr
    case motion
    case depthOfField = "depth-of-field"
    case composition

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hdr: return "HDR"
        case .motion: return "Motion"
        case .depthOfField: return "Depth of Field"
        case .composition: return "Composition"
        }
    }
}

enum GearItem: String, Codable, CaseIterable, Identifiable, Hashable {
    case camera, phone, tripod, remote, flash
    case wideAngle = "wide-angle"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camera: return "Camera"
        case .phone: return "Phone"
        case .tripod: return "Tripod"
        case .remote: return "Remote shutter"
        case .flash: return "Flash"
        case .wideAngle: return "Wide-angle lens"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: return "camera.fill"
        case .phone: return "iphone"
        case .tripod: return "camera.macro"
        case .remote: return "appletvremote.gen4.fill"
        case .flash: return "bolt.fill"
        case .wideAngle: return "camera.aperture"
        }
    }
}

enum CameraMode: String, Codable, Hashable {
    case aperturePriority = "aperture-priority"
    case shutterPriority = "shutter-priority"
    case manual
    case auto
    case phoneHdr = "phone-hdr"

    var label: String {
        switch self {
        case .aperturePriority: return "Aperture Priority (A/Av)"
        case .shutterPriority: return "Shutter Priority (S/Tv)"
        case .manual: return "Manual (M)"
        case .auto: return "Auto"
        case .phoneHdr: return "Phone HDR"
        }
    }
}

struct DialSettings: Codable, Hashable {
    var mode: CameraMode
    var aperture: String?
    var shutter: String?
    var iso: String?
    var evBracket: String?
    var notes: String?
}

struct SubVariant: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var description: String
    var dials: DialSettings
    var tips: [String]
}

struct Recipe: Codable, Identifiable, Hashable {
    var id: String
    var page: Int
    var title: String
    var blurb: String
    var whenToUse: String
    var tags: [TechniqueTag]
    var gear: [GearItem]
    var dials: DialSettings
    var steps: [String]
    var tips: [String]
    var equipmentChecklist: [String]
    var subVariants: [SubVariant]?
    var phoneTip: String?
    var advancedTip: String?
}

extension Recipe {
    /// Large “key setting” for library cards — prefer shutter / aperture / mode.
    var keySetting: String {
        if let shutter = dials.shutter, !shutter.isEmpty { return shutter }
        if let aperture = dials.aperture, !aperture.isEmpty { return aperture }
        if let iso = dials.iso, !iso.isEmpty { return "ISO \(iso)" }
        if let ev = dials.evBracket, !ev.isEmpty { return ev }
        return dials.mode.label
    }
}
