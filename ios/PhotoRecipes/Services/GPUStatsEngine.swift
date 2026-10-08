import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import Accelerate
import Metal
import MetalPerformanceShaders
import os.log

// MARK: - GPU frame stats

/// One analysis of a viewfinder frame: a 64-bin luma histogram, clipped /
/// crushed fractions, gray-world RGB means over unclipped pixels, RMS luma
/// contrast, and the 13 synthetic re-exposure gradient scores (Sobel variant
/// of the Python `GradientAE.gradient_info` reference).
///
/// **Tone-mapping caveat:** preview frames are tone-mapped by the system, so
/// these stats are RELATIVE signals (which ratio maximizes detail, where the
/// histogram piles up). Absolute exposure stays with E_auto from Phase 1
/// (`ExposurePlanner`) — never derive an EV from these numbers.
struct GPUFrameStats: Codable, Equatable {
    var capturedAt: Date = Date()
    /// "metal" or "cpu" (the vImage reference fallback).
    var source: String = "cpu"
    var width: Int = 0
    var height: Int = 0
    /// 64-bin luma histogram, 0…1 luma range.
    var lumaHistogram64: [Int] = []
    /// Fraction of pixels with luma > 0.95.
    var clippedFraction: Float = 0
    /// Fraction of pixels with luma < 0.05.
    var crushedFraction: Float = 0
    /// Gray-world means over unclipped pixels (max channel < 0.98 and min
    /// channel > 0.02); fall back to the luma mean when no pixel qualifies.
    var meanR: Float = 0
    var meanG: Float = 0
    var meanB: Float = 0
    /// RMS contrast of luma: sqrt(E[x^2] − E[x]^2).
    var contrast: Float = 0
    /// One score per ratio in `GPUStatsCore.gradientRatios`.
    var gradientScores: [Float] = []
    /// Wall time of the analysis, milliseconds (device measurement pending).
    var analysisMs: Double = 0
}

// MARK: - Shared algorithm (pure Swift; the Metal kernel mirrors this)

/// The reference implementation both paths must agree with: the Metal kernel
/// (`gpu_frame_stats` in GPUStats.metal) is a line-for-line port of
/// `compute`/`gradientScores` below. The parity test
/// (`GPUStatsEngineTests`) checks this module against an independent naive
/// implementation — the Metal side is verified by structure (same bin count,
/// same ratio table) plus the CI Metal compile of GPUStats.metal.
enum GPUStatsCore {
    static let histogramBins = 64
    static let gradientRatioCount = 13
    static let analysisWidth = 256
    static let analysisHeight = 192

    /// geomspace(0.25, 4, 13) — must match `exposureRatio()` in GPUStats.metal.
    static var gradientRatios: [Float] {
        (0..<gradientRatioCount).map { 0.25 * pow(16, Float($0) / 12) }
    }

    struct RGB {
        var r: Float
        var g: Float
        var b: Float
    }

    struct Computed: Equatable {
        var bins: [Int]
        var clippedFraction: Float
        var crushedFraction: Float
        var meanR: Float
        var meanG: Float
        var meanB: Float
        var contrast: Float
        var gradientScores: [Float]
    }

    /// - Parameters:
    ///   - luma: row-major luma 0…1, `width * height` entries.
    ///   - rgb: per-pixel display RGB, or nil for luma-only sources (420f Y
    ///     plane) — gray-world means then fall back to the luma mean.
    static func compute(luma: [Float], rgb: [RGB]?, width: Int, height: Int) -> Computed {
        precondition(luma.count == width * height)
        let n = Double(max(width * height, 1))
        var bins = [Int](repeating: 0, count: histogramBins)
        var sum = 0.0
        var sumSq = 0.0
        var clip = 0
        var crush = 0
        for l in luma {
            let d = Double(l)
            bins[min(Int(d * Double(histogramBins)), histogramBins - 1)] += 1
            sum += d
            sumSq += d * d
            if l > 0.95 { clip += 1 }
            if l < 0.05 { crush += 1 }
        }
        let mean = sum / n
        let contrast = sqrt(max(sumSq / n - mean * mean, 0))

        var sR = 0.0, sG = 0.0, sB = 0.0
        var valid = 0
        if let rgb {
            for p in rgb {
                let mx = Double(max(p.r, max(p.g, p.b)))
                let mn = Double(min(p.r, min(p.g, p.b)))
                if mx < 0.98, mn > 0.02 {
                    sR += Double(p.r); sG += Double(p.g); sB += Double(p.b)
                    valid += 1
                }
            }
        }
        let vd = Double(max(valid, 1))
        return Computed(
            bins: bins,
            clippedFraction: Float(Double(clip) / n),
            crushedFraction: Float(Double(crush) / n),
            meanR: Float(valid > 0 ? sR / vd : mean),
            meanG: Float(valid > 0 ? sG / vd : mean),
            meanB: Float(valid > 0 ? sB / vd : mean),
            contrast: Float(contrast),
            gradientScores: gradientScores(luma: luma, width: width, height: height).map { Float($0) }
        )
    }

    /// 13 synthetic re-exposure gradient scores. Per ratio r: inverse-gamma
    /// expand the luma (display → linear, gamma 2.2), scale by r, clip to
    /// [0,1], re-encode; Sobel magnitude g of the re-encoded neighborhood
    /// accumulates log1p(100*g) for g > 0.01. Double accumulation keeps the
    /// parity test within 1e-3.
    static func gradientScores(luma: [Float], width: Int, height: Int) -> [Double] {
        precondition(luma.count == width * height)
        // Linearize once (the kernel does this per 3x3 tile; same values).
        var lin = [Double](repeating: 0, count: luma.count)
        for i in 0..<luma.count {
            lin[i] = pow(max(Double(luma[i]), 0), 2.2)
        }
        var scores = [Double](repeating: 0, count: gradientRatioCount)
        for (ri, ratio) in gradientRatios.enumerated() {
            let r = Double(ratio)
            var s = 0.0
            for y in 0..<height {
                for x in 0..<width {
                    var e = [Double](repeating: 0, count: 9)
                    for jy in 0..<3 {
                        let yy = min(max(y + jy - 1, 0), height - 1)
                        for jx in 0..<3 {
                            let xx = min(max(x + jx - 1, 0), width - 1)
                            e[jy * 3 + jx] = pow(min(lin[yy * width + xx] * r, 1.0), 1.0 / 2.2)
                        }
                    }
                    let gx = (e[2] + 2 * e[5] + e[8]) - (e[0] + 2 * e[3] + e[6])
                    let gy = (e[6] + 2 * e[7] + e[8]) - (e[0] + 2 * e[1] + e[2])
                    let g = sqrt(gx * gx + gy * gy)
                    if g > 0.01 { s += log1p(100 * g) }
                }
            }
            scores[ri] = s
        }
        return scores
    }
}

// MARK: - Engine

/// Fast on-device frame statistics (Phase 2).
///
/// - Metal path: wraps the sampled `CVPixelBuffer` as a zero-copy `MTLTexture`
///   via `CVMetalTextureCache`, downsamples to 256x192 with
///   `MPSImageBilinearScale`, and runs the single-pass `gpu_frame_stats`
///   kernel. Target <2 ms GPU time per analysis on A15 — **device measurement
///   pending** (no GPU on the build VM; CI macOS runners have no usable GPU
///   either, so the Metal path is exercised on-device only).
/// - CPU fallback: when `MTLCreateSystemDefaultDevice()` returns nil (CI VMs,
///   Simulator) the vImage reference below produces byte-comparable outputs
///   (`GPUFrameStats`), so the pipeline never depends on a GPU.
///
/// Thread-safe (internal lock + triple-buffered outputs). Called from the
/// sensor's vision queue — never the capture queue, never the main actor.
/// Pixel format: 32BGRA (what the session delivers); 420f is handled via the
/// Y plane (luma-exact, chroma-neutral); anything else returns nil — never
/// crashes.
final class GPUStatsEngine {
    static let shared = GPUStatsEngine()

    static let histogramBins = GPUStatsCore.histogramBins
    static let gradientRatioCount = GPUStatsCore.gradientRatioCount
    static let analysisWidth = GPUStatsCore.analysisWidth
    static let analysisHeight = GPUStatsCore.analysisHeight
    /// Must match the kernel name in GPUStats.metal.
    static let kernelFunctionName = "gpu_frame_stats"

    private let log = Logger(subsystem: "com.ragnus.mvp", category: "GPUStats")
    private let lock = NSLock()
    private let device: MTLDevice?
    private var textureCache: CVMetalTextureCache?
    private var pipeline: MTLComputePipelineState?
    private var commandQueue: MTLCommandQueue?
    private var metalFailed = false
    private var unsupportedFormatLogged = false
    /// Triple-buffered recent analyses (newest last).
    private var ring: [GPUFrameStats] = []

    /// - Parameter device: inject nil in tests to force the CPU reference path.
    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.device = device
    }

    /// Analyze one frame. Returns nil only for unsupported pixel formats.
    func analyze(_ pixelBuffer: CVPixelBuffer) -> GPUFrameStats? {
        let start = CFAbsoluteTimeGetCurrent()
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let stats: GPUFrameStats?
        if format == kCVPixelFormatType_32BGRA, ensureMetal() {
            stats = analyzeMetal(pixelBuffer) ?? cpuReferenceAnalyze(pixelBuffer)
        } else {
            stats = cpuReferenceAnalyze(pixelBuffer)
        }
        guard var s = stats else { return nil }
        s.analysisMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        lock.lock()
        ring.append(s)
        if ring.count > 3 { ring.removeFirst() }
        lock.unlock()
        return s
    }

    /// The CPU/vImage reference implementation with identical outputs to the
    /// Metal path. Also the graceful fallback when Metal is unavailable.
    func cpuReferenceAnalyze(_ pixelBuffer: CVPixelBuffer) -> GPUFrameStats? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if format == kCVPixelFormatType_32BGRA {
            guard let small = Self.downsampleBGRAExact(
                pixelBuffer, width: Self.analysisWidth, height: Self.analysisHeight),
                let (luma, rgb) = Self.readBGRA(small)
            else { return nil }
            let c = GPUStatsCore.compute(luma: luma, rgb: rgb, width: Self.analysisWidth, height: Self.analysisHeight)
            return Self.stats(from: c, source: "cpu")
        }
        if format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            return cpuReference420f(pixelBuffer)
        }
        lock.lock()
        let logged = unsupportedFormatLogged
        if !logged { unsupportedFormatLogged = true }
        lock.unlock()
        if !logged {
            log.error("GPUStats: unsupported pixel format \(format, privacy: .public) — stats unavailable")
        }
        return nil
    }

    /// Newest analysis no older than `maxAge`, else nil.
    func latestStats(maxAge: TimeInterval) -> GPUFrameStats? {
        lock.lock()
        defer { lock.unlock() }
        guard let s = ring.last,
              Date().timeIntervalSince(s.capturedAt) <= maxAge
        else { return nil }
        return s
    }

    // MARK: - Metal path

    private func ensureMetal() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let device else { return false }
        if metalFailed { return false }
        if pipeline != nil { return true }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache
        else {
            log.error("GPUStats: CVMetalTextureCacheCreate failed — CPU fallback")
            metalFailed = true
            return false
        }
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: Self.kernelFunctionName),
              let pipeline = try? device.makeComputePipelineState(function: function),
              let queue = device.makeCommandQueue()
        else {
            // Missing/broken metallib (e.g. GPUStats.metal not compiled into
            // the target) — fall back to CPU, don't crash.
            log.error("GPUStats: Metal pipeline setup failed — CPU fallback")
            metalFailed = true
            return false
        }
        textureCache = cache
        self.pipeline = pipeline
        commandQueue = queue
        return true
    }

    private func analyzeMetal(_ pixelBuffer: CVPixelBuffer) -> GPUFrameStats? {
        lock.lock()
        let cache = textureCache
        let pipeline = pipeline
        let queue = commandQueue
        let device = device
        lock.unlock()
        guard let device, let cache, let pipeline, let queue else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        guard w > 0, h > 0 else { return nil }

        // Zero-copy wrap of the sampled buffer.
        var cvTexture: CVMetalTexture?
        let wrapStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm, w, h, 0, &cvTexture)
        guard wrapStatus == kCVReturnSuccess,
              let src = cvTexture.flatMap(CVMetalTextureGetTexture)
        else {
            log.error("GPUStats: texture wrap failed — CPU fallback for this frame")
            return nil
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Self.analysisWidth, height: Self.analysisHeight,
            mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        guard let small = device.makeTexture(descriptor: desc),
              let commandBuffer = queue.makeCommandBuffer()
        else { return nil }

        MPSImageBilinearScale(device: device)
            .encode(commandBuffer: commandBuffer, sourceTexture: src, destinationTexture: small)

        let histLen = Self.histogramBins * MemoryLayout<UInt32>.size
        let accumLen = (9 + Self.gradientRatioCount) * MemoryLayout<UInt32>.size
        guard let histBuf = device.makeBuffer(length: histLen, options: .storageModeShared),
              let accumBuf = device.makeBuffer(length: accumLen, options: .storageModeShared)
        else { return nil }
        memset(histBuf.contents(), 0, histLen)
        memset(accumBuf.contents(), 0, accumLen)

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(small, index: 0)
        encoder.setBuffer(histBuf, offset: 0, index: 0)
        encoder.setBuffer(accumBuf, offset: 0, index: 1)
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        let groups = MTLSize(
            width: (Self.analysisWidth + 7) / 8,
            height: (Self.analysisHeight + 7) / 8,
            depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        let done = DispatchSemaphore(value: 0)
        commandBuffer.addCompletedHandler { _ in done.signal() }
        commandBuffer.commit()
        guard done.wait(timeout: .now() + 2.0) == .success else {
            log.error("GPUStats: Metal execution timed out — CPU fallback for this frame")
            return nil
        }

        let hist = histBuf.contents().assumingMemoryBound(to: UInt32.self)
        let acc = accumBuf.contents().assumingMemoryBound(to: UInt32.self)
        let count = max(Double(acc[2]), 1)
        let valid = Double(acc[8])
        var bins = [Int](repeating: 0, count: Self.histogramBins)
        for b in 0..<Self.histogramBins { bins[b] = Int(hist[b]) }
        let sumL = Double(acc[0]) / 1000.0
        let mean = sumL / count
        let contrast = sqrt(max(Double(acc[1]) / 1000.0 / count - mean * mean, 0))
        var scores: [Float] = []
        scores.reserveCapacity(Self.gradientRatioCount)
        for i in 0..<Self.gradientRatioCount {
            scores.append(Float(Double(acc[9 + i]) / 1000.0))
        }
        return GPUFrameStats(
            capturedAt: Date(),
            source: "metal",
            width: Self.analysisWidth,
            height: Self.analysisHeight,
            lumaHistogram64: bins,
            clippedFraction: Float(Double(acc[3]) / count),
            crushedFraction: Float(Double(acc[4]) / count),
            meanR: valid > 0 ? Float(Double(acc[5]) / 1000.0 / valid) : Float(mean),
            meanG: valid > 0 ? Float(Double(acc[6]) / 1000.0 / valid) : Float(mean),
            meanB: valid > 0 ? Float(Double(acc[7]) / 1000.0 / valid) : Float(mean),
            contrast: Float(contrast),
            gradientScores: scores,
            analysisMs: 0
        )
    }

    // MARK: - CPU reference

    private static func stats(from c: GPUStatsCore.Computed, source: String) -> GPUFrameStats {
        GPUFrameStats(
            capturedAt: Date(),
            source: source,
            width: analysisWidth,
            height: analysisHeight,
            lumaHistogram64: c.bins,
            clippedFraction: c.clippedFraction,
            crushedFraction: c.crushedFraction,
            meanR: c.meanR,
            meanG: c.meanG,
            meanB: c.meanB,
            contrast: c.contrast,
            gradientScores: c.gradientScores,
            analysisMs: 0
        )
    }

    /// 420f: luma-exact via the Y plane (video-range aware); chroma degrades
    /// gracefully to neutral (gray-world means fall back to the luma mean).
    private func cpuReference420f(_ pixelBuffer: CVPixelBuffer) -> GPUFrameStats? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        guard w > 0, h > 0 else { return nil }
        var src = vImage_Buffer(
            data: yBase,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
        let dw = Self.analysisWidth, dh = Self.analysisHeight
        guard let dstData = malloc(dw * dh) else { return nil }
        defer { free(dstData) }
        var dst = vImage_Buffer(
            data: dstData,
            height: vImagePixelCount(dh),
            width: vImagePixelCount(dw),
            rowBytes: dw)
        guard vImageScale_Planar8(&src, &dst, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
        let bytes = dstData.assumingMemoryBound(to: UInt8.self)
        let fullRange = CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        var luma = [Float](repeating: 0, count: dw * dh)
        for i in 0..<(dw * dh) {
            let y = Float(bytes[i])
            luma[i] = fullRange ? y / 255.0 : min(max((y - 16) / 219.0, 0), 1)
        }
        let c = GPUStatsCore.compute(luma: luma, rgb: nil, width: dw, height: dh)
        return Self.stats(from: c, source: "cpu")
    }

    /// Exact-size vImage downsample of a 32BGRA buffer (channel order is
    /// irrelevant — all four channels scale identically).
    static func downsampleBGRAExact(_ pb: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let srcBase = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let srcW = CVPixelBufferGetWidth(pb)
        let srcH = CVPixelBufferGetHeight(pb)
        guard srcW > 0, srcH > 0 else { return nil }
        var src = vImage_Buffer(
            data: srcBase,
            height: vImagePixelCount(srcH),
            width: vImagePixelCount(srcW),
            rowBytes: CVPixelBufferGetBytesPerRow(pb))
        var dstPB: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, nil, &dstPB) == kCVReturnSuccess,
            let dst = dstPB
        else { return nil }
        CVPixelBufferLockBaseAddress(dst, [])
        defer { CVPixelBufferUnlockBaseAddress(dst, []) }
        guard let dstBase = CVPixelBufferGetBaseAddress(dst) else { return nil }
        var dstBuf = vImage_Buffer(
            data: dstBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(dst))
        guard vImageScale_ARGB8888(&src, &dstBuf, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
        return dst
    }

    /// Row-major luma (Rec.709) + display RGB from a 32BGRA buffer.
    static func readBGRA(_ pb: CVPixelBuffer) -> (luma: [Float], rgb: [GPUStatsCore.RGB])? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 0, h > 0 else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        var luma = [Float](repeating: 0, count: w * h)
        var rgb = [GPUStatsCore.RGB](repeating: GPUStatsCore.RGB(r: 0, g: 0, b: 0), count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                let o = x * 4
                // 32BGRA memory order: B G R A.
                let b = Float(row[o]) / 255
                let g = Float(row[o + 1]) / 255
                let r = Float(row[o + 2]) / 255
                let i = y * w + x
                luma[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
                rgb[i] = GPUStatsCore.RGB(r: r, g: g, b: b)
            }
        }
        return (luma, rgb)
    }
}

// MARK: - Probe JPEG → pixel buffer (no-video-frames fallback)

/// Decodes a probe JPEG into a 32BGRA pixel buffer for the CPU feature path.
/// Used only when no video frames have arrived (session interruption, lens
/// switch) — the normal path analyzes live video buffers.
enum ProbeFrameDecoder {
    static func pixelBuffer(fromJPEG data: Data) -> CVPixelBuffer? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, w, h,
            kCVPixelFormatType_32BGRA, nil, &pb) == kCVReturnSuccess,
            let buffer = pb
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        // premultipliedFirst + little-endian 32 == BGRA memory order.
        guard let ctx = CGContext(
            data: base, width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buffer
    }
}
