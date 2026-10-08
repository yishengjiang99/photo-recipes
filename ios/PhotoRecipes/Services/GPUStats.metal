#include <metal_stdlib>
using namespace metal;

// MARK: - Phase 2 GPU frame statistics
//
// Single-pass compute kernel over the 256x192 downsampled viewfinder frame.
// One thread per pixel (32x24 threadgroups of 8x8). Each thread:
//   1. reads its BGRA pixel and computes Rec.709 luma;
//   2. votes into a threadgroup-local 64-bin luma histogram (merged once per
//      threadgroup into the global histogram via device atomics);
//   3. accumulates photometric sums (luma, luma^2, clipped/crushed counts,
//      gray-world RGB sums over unclipped pixels) with a threadgroup tree
//      reduction followed by fixed-point (x1000) device atomics;
//   4. computes the 13 synthetic re-exposure gradient scores: for each ratio
//      r in geomspace(0.25, 4, 13) the 3x3 luma neighborhood is inverse-gamma
//      expanded (display -> linear, gamma 2.2 to match the Python GradientAE
//      reference), scaled by r, clipped to [0,1], and re-encoded; the Sobel
//      magnitude g of the re-encoded luma accumulates log1p(100*g) for
//      g > 0.01.
//
// NOTE: the Python reference (scripts/camera-settings/
// camera_settings_framework.py::gradient_info) uses forward differences
// (np.diff); this kernel uses a 3x3 Sobel, which is less noise-sensitive on
// small tiles. The CPU reference (GPUStatsCore.gradientScores) implements the
// same Sobel variant, so the parity test holds.
//
// Preview frames are tone-mapped: every value here is a RELATIVE signal.
// Absolute exposure stays with E_auto (Phase 1, ExposurePlanner).

constant uint kBins = 64;
constant uint kRatios = 13;
// accum[] layout (atomic_uint; float fields are x1000 fixed point):
//   [0] sumLuma  [1] sumLumaSq  [2] pixelCount (unscaled)
//   [3] clippedCount (unscaled)  [4] crushedCount (unscaled)
//   [5] sumR  [6] sumG  [7] sumB  [8] unclippedCount (unscaled)
//   [9 .. 9+13) gradient scores
constant uint kAccumScoresBase = 9;

inline float rec709(float3 rgb) {
    return dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
}

inline float exposureRatio(uint i) {
    // geomspace(0.25, 4, 13) == 0.25 * 16^(i/12); must match
    // GPUStatsCore.gradientRatios in GPUStatsEngine.swift.
    return 0.25f * pow(16.0f, float(i) / 12.0f);
}

// Tree reduction of one per-thread float across a 64-thread threadgroup.
inline float reduceSum(float v, threadgroup float *scratch, uint flatTid) {
    scratch[flatTid] = v;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = 32; stride > 0; stride >>= 1) {
        if (flatTid < stride) {
            scratch[flatTid] += scratch[flatTid + stride];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    return scratch[0];
}

kernel void gpu_frame_stats(
    texture2d<float, access::read> src [[texture(0)]],
    device atomic_uint *histogram [[buffer(0)]],
    device atomic_uint *accum [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 tid [[thread_position_in_threadgroup]],
    uint2 tgid [[threadgroup_position_in_grid]],
    uint flatTid [[thread_index_in_threadgroup]])
{
    const uint W = src.get_width();
    const uint H = src.get_height();
    // Out-of-bounds threads (non-multiple-of-8 sizes) still participate in
    // the cooperative tile load and every barrier; they just contribute zero.
    const bool active = gid.x < W && gid.y < H;

    // 10x10 luma tile (8x8 work area + 1px halo), clamp-to-edge addressing.
    threadgroup float tile[10][10];
    threadgroup atomic_uint localHist[kBins];
    threadgroup float scratch[64];

    if (flatTid < kBins) {
        atomic_store_explicit(&localHist[flatTid], 0u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Cooperative tile load: 100 texels spread over the 64 threads.
    const uint ox = tgid.x * 8;
    const uint oy = tgid.y * 8;
    for (uint k = flatTid; k < 100; k += 64) {
        const uint lx = k % 10;
        const uint ly = k / 10;
        int sx = clamp(int(ox) + int(lx) - 1, 0, int(W) - 1);
        int sy = clamp(int(oy) + int(ly) - 1, 0, int(H) - 1);
        tile[ly][lx] = rec709(src.read(uint2(uint(sx), uint(sy))).rgb);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    float sumL = 0.0f, sumSq = 0.0f, clipC = 0.0f, crushC = 0.0f;
    float sumR = 0.0f, sumG = 0.0f, sumB = 0.0f, validC = 0.0f, count = 0.0f;
    float scores[kRatios];
    for (uint i = 0; i < kRatios; i++) { scores[i] = 0.0f; }

    if (active) {
        const float3 rgb = src.read(gid).rgb;
        const float l = rec709(rgb);
        const uint bin = min(uint(l * float(kBins)), kBins - 1);
        atomic_fetch_add_explicit(&localHist[bin], 1u, memory_order_relaxed);

        sumL = l;
        sumSq = l * l;
        count = 1.0f;
        clipC = (l > 0.95f) ? 1.0f : 0.0f;
        crushC = (l < 0.05f) ? 1.0f : 0.0f;
        // Gray world ignores clipped/dark pixels (mirrors the Python GrayWorldAWB).
        const float maxC = max(max(rgb.r, rgb.g), rgb.b);
        const float minC = min(min(rgb.r, rgb.g), rgb.b);
        if (maxC < 0.98f && minC > 0.02f) {
            sumR = rgb.r; sumG = rgb.g; sumB = rgb.b; validC = 1.0f;
        }

        // Gradient scores: linearize the 3x3 neighborhood once, Sobel per ratio.
        const uint lx = tid.x + 1;
        const uint ly = tid.y + 1;
        float lin[9];
        for (uint j = 0; j < 9; j++) {
            const float d = tile[ly - 1 + j / 3][lx - 1 + j % 3];
            lin[j] = pow(max(d, 0.0f), 2.2f);
        }
        for (uint i = 0; i < kRatios; i++) {
            const float r = exposureRatio(i);
            float e[9];
            for (uint j = 0; j < 9; j++) {
                e[j] = pow(min(lin[j] * r, 1.0f), 1.0f / 2.2f);
            }
            const float gx = (e[2] + 2.0f * e[5] + e[8]) - (e[0] + 2.0f * e[3] + e[6]);
            const float gy = (e[6] + 2.0f * e[7] + e[8]) - (e[0] + 2.0f * e[1] + e[2]);
            const float g = sqrt(gx * gx + gy * gy);
            if (g > 0.01f) {
                // Metal has no log1p; log(1+x) is identical for x > 0.
                scores[i] = log(1.0f + 100.0f * g);
            }
        }
    }

    // Reduce across the threadgroup, then publish via fixed-point atomics.
    const float tSumL = reduceSum(sumL, scratch, flatTid);
    const float tSumSq = reduceSum(sumSq, scratch, flatTid);
    const float tCount = reduceSum(count, scratch, flatTid);
    const float tClip = reduceSum(clipC, scratch, flatTid);
    const float tCrush = reduceSum(crushC, scratch, flatTid);
    const float tSumR = reduceSum(sumR, scratch, flatTid);
    const float tSumG = reduceSum(sumG, scratch, flatTid);
    const float tSumB = reduceSum(sumB, scratch, flatTid);
    const float tValid = reduceSum(validC, scratch, flatTid);
    float tScores[kRatios];
    for (uint i = 0; i < kRatios; i++) {
        tScores[i] = reduceSum(scores[i], scratch, flatTid);
    }

    if (flatTid == 0) {
        atomic_fetch_add_explicit(&accum[0], uint(tSumL * 1000.0f), memory_order_relaxed);
        atomic_fetch_add_explicit(&accum[1], uint(tSumSq * 1000.0f), memory_order_relaxed);
        atomic_fetch_add_explicit(&accum[2], uint(tCount), memory_order_relaxed);
        atomic_fetch_add_explicit(&accum[3], uint(tClip), memory_order_relaxed);
        atomic_fetch_add_explicit(&accum[4], uint(tCrush), memory_order_relaxed);
        atomic_fetch_add_explicit(&accum[5], uint(tSumR * 1000.0f), memory_order_relaxed);
        atomic_fetch_add_explicit(&accum[6], uint(tSumG * 1000.0f), memory_order_relaxed);
        atomic_fetch_add_explicit(&accum[7], uint(tSumB * 1000.0f), memory_order_relaxed);
        atomic_fetch_add_explicit(&accum[8], uint(tValid), memory_order_relaxed);
        for (uint i = 0; i < kRatios; i++) {
            atomic_fetch_add_explicit(&accum[kAccumScoresBase + i], uint(tScores[i] * 1000.0f), memory_order_relaxed);
        }
        for (uint b = 0; b < kBins; b++) {
            atomic_fetch_add_explicit(&histogram[b],
                atomic_load_explicit(&localHist[b], memory_order_relaxed),
                memory_order_relaxed);
        }
    }
}
