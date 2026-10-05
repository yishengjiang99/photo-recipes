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

extension Recipe {
    /// Short name for Camera chrome (badge / before-after chip). Never the long marketing title.
    var chromeTitle: String {
        switch id {
        case "sharp-front-to-back": return "Sharp Front to Back"
        case "blur-moving-subjects": return "Blur Motion"
        case "panning-sharp-subject": return "Panning"
        case "get-down-low": return "Low Angle"
        case "hdr-brights-darks": return "HDR"
        default:
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count <= 22 { return t }
            // Prefer clause before em/en dash or colon
            for sep in [" — ", " – ", " - ", ": "] {
                if let r = t.range(of: sep) {
                    let head = String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if (8...28).contains(head.count) { return head }
                }
            }
            return String(t.prefix(20)).trimmingCharacters(in: .whitespaces) + "…"
        }
    }

    static func chromeTitle(forStoredTitle title: String?, id: String?) -> String? {
        if let id, let recipe = BundledPresets.recipe(id: id) {
            return recipe.chromeTitle
        }
        guard let title, !title.isEmpty else { return nil }
        // Best-effort: match known full titles
        if let recipe = BundledPresets.all.first(where: { $0.title == title }) {
            return recipe.chromeTitle
        }
        if title.count <= 22 { return title }
        return String(title.prefix(20)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

