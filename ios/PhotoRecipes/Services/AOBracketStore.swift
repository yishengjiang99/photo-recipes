import Foundation

// MARK: - Phase 3 local bracket store
//
// On-device only: Application Support/ao-brackets/<runId>/ holds the
// downsampled bracket JPEGs + a meta.json sidecar (offsets, EXIF, stats).
// Caps: max 20 sets / 64 MB — oldest evicted first.
//
// Nothing here touches the network. The explicit-consent upload gate lives in
// Settings ("Review & upload my bracket captures"): tap + confirmation builds
// an upload manifest via `pendingUploadManifest()`. The actual transport is a
// declared stub until the server endpoint exists — Phase 3 ships the gate and
// the local store, never an upload.

final class AOBracketStore: Sendable {
    static let shared = AOBracketStore()

    static let directoryName = "ao-brackets"
    static let defaultMaxSets = 20
    static let defaultMaxBytes: Int64 = 64 * 1024 * 1024

    struct BracketSetInfo: Equatable, Sendable {
        var id: String // runId
        var capturedAt: Date
        var recipeId: String
        var frameCount: Int
        var bytes: Int64
    }

    let baseURL: URL
    let maxSets: Int
    let maxBytes: Int64

    init(
        baseURL: URL? = nil,
        maxSets: Int = defaultMaxSets,
        maxBytes: Int64 = defaultMaxBytes
    ) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            self.baseURL = appSupport.appendingPathComponent(
                Self.directoryName, isDirectory: true)
        }
        self.maxSets = maxSets
        self.maxBytes = maxBytes
    }

    // MARK: - Write

    /// Store one bracket run: downsample each frame, label EV offsets from
    /// EXIF exposure times (order-independent), write JPEGs + meta.json,
    /// then enforce the count/size caps. Synchronous — call off the main actor.
    func storeBracketSync(manifest: AOBracketManifest, frames: [Data]) throws {
        try FileManager.default.createDirectory(
            at: baseURL, withIntermediateDirectories: true)
        let setURL = baseURL.appendingPathComponent(manifest.runId, isDirectory: true)
        try FileManager.default.createDirectory(
            at: setURL, withIntermediateDirectories: true)

        // True EV offset per frame from EXIF (median exposure == 0 EV).
        let exposures = frames.map { AOBracketDownsampler.exifExposure($0)?.exposureSeconds }
        let sorted = exposures.compactMap { $0 }.sorted()
        let median = sorted.isEmpty ? nil : sorted[sorted.count / 2]

        var frameEntries: [[String: Any]] = []
        for (i, data) in frames.enumerated() {
            guard let small = AOBracketDownsampler.downsampleJPEG(data) else { continue }
            let offset: Double = {
                if let t = exposures[i], let m = median, m > 0 {
                    return (log2(t / m) * 10).rounded() / 10
                }
                // EXIF missing — fall back to the requested −2…+2 order.
                let fallback = AOBracketCapture.evOffsets
                return i < fallback.count ? Double(fallback[i]) : 0
            }()
            let name = String(format: "frame_ev%+.1f.jpg", offset)
            try small.write(to: setURL.appendingPathComponent(name))
            var entry: [String: Any] = ["file": name, "evOffset": offset]
            if let exif = AOBracketDownsampler.exifExposure(data) {
                entry["exposureSeconds"] = exif.exposureSeconds
                entry["iso"] = exif.iso
            }
            frameEntries.append(entry)
        }

        let meta: [String: Any] = [
            "runId": manifest.runId,
            "recipeId": manifest.recipeId,
            "capturedAt": manifest.capturedAt.timeIntervalSince1970,
            "coachOnly": manifest.coachOnly,
            "frames": frameEntries,
            "stats": [
                "gpuSource": manifest.gpuSource as Any,
                "highlightClipFraction": manifest.highlightClipFraction,
                "shadowCrushFraction": manifest.shadowCrushFraction,
                "lumaContrast": manifest.lumaContrast as Any,
                "grayWorldR": manifest.grayWorldR as Any,
                "grayWorldG": manifest.grayWorldG as Any,
                "grayWorldB": manifest.grayWorldB as Any,
                "faceCount": manifest.faceCount as Any,
                "handShakeRadPerSec": manifest.handShakeRadPerSec,
            ],
            "sceneLabels": (manifest.sceneLabels ?? []).map {
                ["id": $0.identifier, "confidence": $0.confidence]
            },
        ]
        let metaData = try JSONSerialization.data(
            withJSONObject: meta, options: [.sortedKeys])
        try metaData.write(to: setURL.appendingPathComponent("meta.json"))
        enforceCaps()
    }

    // MARK: - Read

    /// Newest-first set infos (tolerant: a set without meta.json is skipped).
    func pendingSets() -> [BracketSetInfo] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: baseURL, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var infos: [BracketSetInfo] = []
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let metaURL = dir.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let jpgs = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]))?
                .filter { $0.pathExtension.lowercased() == "jpg" } ?? []
            let bytes: Int64 = jpgs.reduce(0) { acc, url in
                acc + (Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
            }
            infos.append(BracketSetInfo(
                id: meta["runId"] as? String ?? dir.lastPathComponent,
                capturedAt: Date(timeIntervalSince1970: meta["capturedAt"] as? Double ?? 0),
                recipeId: meta["recipeId"] as? String ?? "",
                frameCount: jpgs.count,
                bytes: bytes
            ))
        }
        return infos.sorted { $0.capturedAt > $1.capturedAt }
    }

    func totalBytes() -> Int64 {
        pendingSets().reduce(0) { $0 + $1.bytes }
    }

    /// Manifest of what an explicit-consent upload WOULD send (set ids,
    /// counts, bytes, meta — never pixels in the manifest itself; the frames
    /// upload separately). The transport is a declared stub until the server
    /// endpoint exists.
    func pendingUploadManifest() -> Data? {
        let sets = pendingSets()
        let manifest: [String: Any] = [
            "sets": sets.map { [
                "id": $0.id,
                "recipeId": $0.recipeId,
                "capturedAt": $0.capturedAt.timeIntervalSince1970,
                "frameCount": $0.frameCount,
                "bytes": $0.bytes,
            ] },
            "totalBytes": totalBytes(),
        ]
        return try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    }

    // MARK: - Delete

    func deleteSet(id: String) {
        try? FileManager.default.removeItem(at: baseURL.appendingPathComponent(id))
    }

    func clearAll() {
        for set in pendingSets() { deleteSet(id: set.id) }
    }

    // MARK: - Caps

    private func enforceCaps() {
        var sets = pendingSets() // newest first
        while sets.count > maxSets, let oldest = sets.popLast() {
            deleteSet(id: oldest.id)
        }
        var bytes = sets.reduce(0) { $0 + $1.bytes }
        while bytes > maxBytes, let oldest = sets.popLast() {
            deleteSet(id: oldest.id)
            bytes -= oldest.bytes
        }
    }
}
