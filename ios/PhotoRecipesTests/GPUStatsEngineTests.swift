import XCTest
@testable import PhotoRecipes

/// Phase 2 GPU stats tests.
///
/// The Metal kernel (`gpu_frame_stats` in GPUStats.metal) cannot execute on
/// CI (no GPU), so these tests verify:
///  1. parity — the CPU/vImage reference (`GPUStatsCore`, the shared algorithm
///     both paths implement) agrees with an independent naive implementation
///     on fixture images, within 1e-3;
///  2. mirror structure — the Swift-side constants the kernel must mirror
///     (64 bins, 13 ratios, geomspace table, kernel name);
///  3. graceful degradation — nil Metal device (CI/Simulator) still yields
///     full stats via the CPU reference; unsupported formats return nil
///     instead of crashing.
final class GPUStatsEngineTests: XCTestCase {

    // MARK: - fixture buffers

    /// 32BGRA pixel buffer filled by (x, y) -> (r, g, b) in 0…1.
    private func makeBuffer(
        width: Int, height: Int,
        fill: (Int, Int) -> (Float, Float, Float)
    ) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, nil, &pb)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!
            .assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = fill(x, y)
                let o = y * rowBytes + x * 4
                base[o] = UInt8(min(max(b, 0), 1) * 255)       // B
                base[o + 1] = UInt8(min(max(g, 0), 1) * 255)  // G
                base[o + 2] = UInt8(min(max(r, 0), 1) * 255)  // R
                base[o + 3] = 255                              // A
            }
        }
        return buffer
    }

    // MARK: - independent naive implementation

    private struct NaiveResult {
        var bins: [Int]
        var clip: Double
        var crush: Double
        var meanR: Double
        var meanG: Double
        var meanB: Double
        var contrast: Double
        var scores: [Double]
    }

    /// Straightforward reimplementation of the shared algorithm (plain loops,
    /// per-neighborhood linearization) — the parity target for GPUStatsCore.
    private func naiveStats(
        luma: [Float], rgb: [GPUStatsCore.RGB],
        width: Int, height: Int
    ) -> NaiveResult {
        let n = Double(width * height)
        var bins = [Int](repeating: 0, count: 64)
        var sum = 0.0, sumSq = 0.0
        var clip = 0.0, crush = 0.0
        for l in luma {
            let d = Double(l)
            bins[min(Int(d * 64), 63)] += 1
            sum += d
            sumSq += d * d
            if l > 0.95 { clip += 1 }
            if l < 0.05 { crush += 1 }
        }
        let mean = sum / n
        var sR = 0.0, sG = 0.0, sB = 0.0, valid = 0.0
        for p in rgb {
            let rd = Double(p.r), gd = Double(p.g), bd = Double(p.b)
            if max(rd, max(gd, bd)) < 0.98, min(rd, min(gd, bd)) > 0.02 {
                sR += rd; sG += gd; sB += bd; valid += 1
            }
        }
        let v = max(valid, 1)
        var scores = [Double](repeating: 0, count: 13)
        for (ri, ratio) in GPUStatsCore.gradientRatios.enumerated() {
            let r = Double(ratio)
            var s = 0.0
            for y in 0..<height {
                for x in 0..<width {
                    // 3x3 Sobel on the re-exposed neighborhood, clamp-to-edge.
                    var e = [Double](repeating: 0, count: 9)
                    for ky in -1...1 {
                        for kx in -1...1 {
                            let yy = min(max(y + ky, 0), height - 1)
                            let xx = min(max(x + kx, 0), width - 1)
                            let d = Double(luma[yy * width + xx])
                            e[(ky + 1) * 3 + (kx + 1)] =
                                pow(min(pow(d, 2.2) * r, 1.0), 1.0 / 2.2)
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
        return NaiveResult(
            bins: bins,
            clip: clip / n, crush: crush / n,
            meanR: valid > 0 ? sR / v : mean,
            meanG: valid > 0 ? sG / v : mean,
            meanB: valid > 0 ? sB / v : mean,
            contrast: sqrt(max(sumSq / n - mean * mean, 0)),
            scores: scores
        )
    }

    /// Full CPU pipeline (vImage downsample + reference) vs the naive
    /// implementation on the exact pixels the engine consumed.
    private func assertParity(
        buffer: CVPixelBuffer,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let engine = GPUStatsEngine(device: nil) // force the CPU reference
        guard let stats = engine.cpuReferenceAnalyze(buffer) else {
            XCTFail("cpuReferenceAnalyze returned nil", file: file, line: line)
            return
        }
        guard let small = GPUStatsEngine.downsampleBGRAExact(
            buffer, width: 256, height: 192),
            let (luma, rgb) = GPUStatsEngine.readBGRA(small)
        else {
            XCTFail("could not re-read downsampled pixels", file: file, line: line)
            return
        }
        let naive = naiveStats(luma: luma, rgb: rgb, width: 256, height: 192)

        XCTAssertEqual(stats.lumaHistogram64, naive.bins, file: file, line: line)
        XCTAssertEqual(Double(stats.clippedFraction), naive.clip, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(Double(stats.crushedFraction), naive.crush, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(Double(stats.meanR), naive.meanR, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(Double(stats.meanG), naive.meanG, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(Double(stats.meanB), naive.meanB, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(Double(stats.contrast), naive.contrast, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(stats.gradientScores.count, 13, file: file, line: line)
        for (a, b) in zip(stats.gradientScores, naive.scores) {
            // Gradient scores are large unnormalized sums (~1e5 over 49k
            // pixels); the reference output is Float32, whose rounding
            // (~1e-7 relative) dominates an absolute 1e-3. Assert relative
            // parity at 1e-5 with a 1e-3 floor for near-zero scores.
            XCTAssertEqual(Double(a), b, accuracy: max(1e-3, abs(b) * 1e-5),
                           "gradient score mismatch: \(a) vs \(b)", file: file, line: line)
        }
    }

    // MARK: - parity on fixture images

    func testParity_gradientFixture() {
        let buf = makeBuffer(width: 320, height: 240) { x, y in
            let v = Float(x) / 319.0
            let w = Float(y) / 239.0
            return (v, v * 0.5 + w * 0.25, 1.0 - v * 0.5)
        }
        assertParity(buffer: buf)
    }

    func testParity_checkerFixture() {
        let buf = makeBuffer(width: 320, height: 240) { x, y in
            let on = ((x / 16) + (y / 16)) % 2 == 0
            let v: Float = on ? 0.9 : 0.1
            return (v, v, v)
        }
        assertParity(buffer: buf)
    }

    func testParity_solidFixture_hasZeroContrastAndZeroGradients() {
        let buf = makeBuffer(width: 320, height: 240) { _, _ in (0.5, 0.5, 0.5) }
        assertParity(buffer: buf)
        let engine = GPUStatsEngine(device: nil)
        let stats = try! XCTUnwrap(engine.cpuReferenceAnalyze(buf))
        XCTAssertEqual(stats.contrast, 0, accuracy: 1e-6)
        XCTAssertTrue(stats.gradientScores.allSatisfy { $0 == 0 },
                      "flat field must produce zero gradient scores")
        // All pixels land in one histogram bin.
        XCTAssertEqual(stats.lumaHistogram64.max(), 256 * 192)
    }

    // MARK: - mirror structure (what the Metal kernel must match)

    func testMirrorStructure_constants() {
        XCTAssertEqual(GPUStatsEngine.histogramBins, 64)
        XCTAssertEqual(GPUStatsEngine.gradientRatioCount, 13)
        XCTAssertEqual(GPUStatsEngine.analysisWidth, 256)
        XCTAssertEqual(GPUStatsEngine.analysisHeight, 192)
        XCTAssertEqual(GPUStatsEngine.kernelFunctionName, "gpu_frame_stats")
        // geomspace(0.25, 4, 13) — the kernel's exposureRatio() must match.
        let ratios = GPUStatsCore.gradientRatios
        XCTAssertEqual(ratios.count, 13)
        XCTAssertEqual(ratios.first!, 0.25, accuracy: 1e-6)
        XCTAssertEqual(ratios.last!, 4.0, accuracy: 1e-6)
        for (i, r) in ratios.enumerated() {
            let expected = Float(0.25 * pow(16.0, Double(i) / 12.0))
            XCTAssertEqual(r, expected, accuracy: 1e-6, "ratio \(i)")
        }
    }

    // MARK: - graceful degradation

    func testNoGPUFallback_producesFullStats() async {
        // Simulates CI/Simulator: MTLCreateSystemDefaultDevice() == nil.
        let buf = makeBuffer(width: 320, height: 240) { x, y in
            (Float(x) / 319.0, Float(y) / 239.0, 0.4)
        }
        let engine = GPUStatsEngine(device: nil)
        let stats = try! XCTUnwrap(await engine.analyze(buf))
        XCTAssertEqual(stats.source, "cpu")
        XCTAssertEqual(stats.lumaHistogram64.count, 64)
        XCTAssertEqual(stats.lumaHistogram64.reduce(0, +), 256 * 192)
        XCTAssertEqual(stats.gradientScores.count, 13)
    }

    func test420f_graceful_noCrash() async {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 48,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &pb)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = pb!
        // Fill the Y plane with mid gray; CbCr left as-is (luma-only path).
        CVPixelBufferLockBaseAddress(buffer, [])
        let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!
            .assumingMemoryBound(to: UInt8.self)
        let yRowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let h = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let w = CVPixelBufferGetWidthOfPlane(buffer, 0)
        for y in 0..<h {
            memset(yBase.advanced(by: y * yRowBytes), 128, w)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let engine = GPUStatsEngine(device: nil)
        let stats = try! XCTUnwrap(await engine.analyze(buffer))
        XCTAssertEqual(stats.source, "cpu")
        XCTAssertEqual(stats.lumaHistogram64.reduce(0, +), 256 * 192)
        // Y=128 video range → (128−16)/219 ≈ 0.51 luma.
        XCTAssertEqual(stats.meanR, 0.51, accuracy: 0.05)
    }

    func testUnsupportedFormat_returnsNil_noCrash() async {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 48,
            kCVPixelFormatType_OneComponent8, nil, &pb)
        XCTAssertEqual(status, kCVReturnSuccess)
        let engine = GPUStatsEngine(device: nil)
        XCTAssertNil(await engine.analyze(pb!))
    }

    // MARK: - buffer ring (no per-call allocation on the hot path)

    func testBufferRing_noAllocationsOnFallbackPath() async {
        // CPU fallback path (CI/Simulator): repeated analyses must never
        // allocate buffer pairs — the hot path reuses the pre-allocated ring.
        let buf = makeBuffer(width: 320, height: 240) { x, y in
            (Float(x) / 319.0, Float(y) / 239.0, 0.4)
        }
        let engine = GPUStatsEngine(device: nil)
        XCTAssertEqual(engine.bufferPairAllocations, 0)
        for _ in 0..<3 {
            _ = await engine.analyze(buf)
        }
        XCTAssertEqual(engine.bufferPairAllocations, 0,
                       "fallback path must not allocate buffer pairs per call")
    }

    func testBufferRing_cyclesSlotsWithoutAllocating() {
        var ring = BufferRing<String>()
        ring.populate(["a", "b", "c"])
        XCTAssertEqual(ring.count, 3)
        var seen: [String] = []
        for _ in 0..<7 { seen.append(ring.next()!) }
        // Round-robin reuse: no growth, no per-checkout allocation.
        XCTAssertEqual(seen, ["a", "b", "c", "a", "b", "c", "a"])
        XCTAssertEqual(ring.count, 3)
    }

    func testBufferRing_empty_returnsNil() {
        var ring = BufferRing<String>()
        XCTAssertNil(ring.next())
    }
}
