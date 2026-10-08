"""
Auto camera-settings framework (skeleton).

Pipeline:  preview frame -> stats -> controllers (AE / AWB / AF) -> settings planner -> camera
Training:  RAW dataset -> exposure/noise simulator -> self-supervised targets -> learned controllers

Maps to the literature:
  - GradientAE          ~ Shim et al. 2014 (maximize image gradient information)
  - LearnedAE           ~ Tomasi et al. 2021 (regress exposure/gain from frame)
  - RL AE (stub)        ~ Lee et al. CVPR 2024 (policy over exposure deltas)
  - TaskMetric          ~ Onzon et al. CVPR 2021 (optimize for a downstream task)
  - LearnedAWB          ~ FFCC (Barron & Tsai 2017), log-chroma illuminant estimate
  - SettingsPlanner     ~ HDR+/Night Sight (split total exposure into shutter/gain by motion)
"""
from __future__ import annotations
from dataclasses import dataclass, replace
from typing import Protocol, Callable
import numpy as np

# ---------------------------------------------------------------- data types
@dataclass
class Settings:
    shutter_s: float = 1 / 60
    iso: float = 100
    aperture_f: float = 2.8
    wb_gains: tuple = (1.0, 1.0, 1.0)   # R, G, B
    focus_pos: float = 0.5               # normalized lens position

    @property
    def exposure(self) -> float:         # relative scene-referred exposure
        return self.shutter_s * (self.iso / 100) / (self.aperture_f ** 2)


@dataclass
class Frame:
    linear: np.ndarray                   # HxWx3, linear, [0,1], pre-WB
    settings: Settings
    motion: float = 0.0                  # e.g. from gyro / optical flow, px/s


# ---------------------------------------------------------------- camera backends
class Camera(Protocol):
    def preview(self) -> Frame: ...
    def apply(self, s: Settings) -> None: ...

# Real backends: wrap Picamera2/libcamera controls, gphoto2, Android Camera2, etc.


class SimulatedCamera:
    """Re-exposes a linear RAW 'scene' — the training/eval workhorse."""
    def __init__(self, scene_radiance: np.ndarray, read_noise=0.002, shot_k=0.01, seed=0):
        self.scene, self.read, self.k = scene_radiance, read_noise, shot_k
        self.s = Settings()
        self.rng = np.random.default_rng(seed)

    def apply(self, s: Settings) -> None:
        self.s = s

    def preview(self) -> Frame:
        signal = self.scene * self.s.exposure * 100   # scale constant is arbitrary
        gain = self.s.iso / 100
        noise = self.rng.normal(0, 1, signal.shape) * np.sqrt(
            self.k * signal + (self.read * gain) ** 2)
        return Frame(np.clip(signal + noise, 0, 1), self.s)


# ---------------------------------------------------------------- stats
def stats(f: Frame, bins=64) -> dict:
    y = f.linear.mean(-1)
    hist = np.histogram(y, bins=bins, range=(0, 1))[0] / y.size
    return {"hist": hist, "mean": y.mean(), "clipped": (y > 0.98).mean(),
            "dark": (y < 0.02).mean()}


# ---------------------------------------------------------------- objectives
Metric = Callable[[np.ndarray], float]   # takes display-referred image, returns score

def gradient_info(img: np.ndarray) -> float:
    y = img.mean(-1)
    gx, gy = np.diff(y, axis=1), np.diff(y, axis=0)
    g = np.sqrt(gx[:-1] ** 2 + gy[:, :-1] ** 2)
    g = g[g > 0.01]
    return float(np.log1p(g * 100).sum())   # Shim-style log weighting

def orb_feature_count(img: np.ndarray) -> float:          # task-driven example
    import cv2
    g = (img.mean(-1) * 255).astype(np.uint8)
    return float(len(cv2.ORB_create(1000).detect(g, None)))

def to_display(lin: np.ndarray, wb=(1, 1, 1)) -> np.ndarray:
    return np.clip(lin * np.asarray(wb), 0, 1) ** (1 / 2.2)


# ---------------------------------------------------------------- controllers
class AEController(Protocol):
    def step(self, f: Frame) -> float: ...   # returns multiplicative exposure change

class GradientAE:
    """Synthetically re-expose the current frame, pick the best-scoring ratio."""
    def __init__(self, metric: Metric = gradient_info, ratios=np.geomspace(0.25, 4, 13)):
        self.metric, self.ratios = metric, ratios

    def step(self, f: Frame) -> float:
        # Under-exposure can be simulated; clipped pixels can't be recovered, so
        # also penalize clipping to push toward shorter exposures when saturated.
        scores = [self.metric(to_display(np.clip(f.linear * r, 0, 1)))
                  - 1e4 * (f.linear * r > 0.98).mean() for r in self.ratios]
        return float(self.ratios[int(np.argmax(scores))])

class LearnedAE:
    """Small net: (downsampled frame, histogram, log exposure) -> log exposure delta."""
    def __init__(self, model):              # torch.nn.Module, trained offline
        self.model = model

    def step(self, f: Frame) -> float:
        import torch
        x = torch.from_numpy(f.linear[::8, ::8]).permute(2, 0, 1)[None].float()
        h = torch.from_numpy(stats(f)["hist"])[None].float()
        e = torch.tensor([[np.log(f.settings.exposure)]]).float()
        with torch.no_grad():
            return float(torch.exp(self.model(x, h, e)).item())

# RL variant (Lee et al.): same interface; the policy outputs the delta and is trained
# in SimulatedCamera with reward = metric(frame_t+1) - convergence/flicker penalties.


class GrayWorldAWB:
    def step(self, f: Frame) -> tuple:
        m = f.linear.reshape(-1, 3)
        m = m[(m.max(1) < 0.98) & (m.min(1) > 0.02)]   # ignore clipped/dark
        mean = m.mean(0) + 1e-6
        return tuple(mean[1] / mean)                    # normalize to green

class LearnedAWB:
    """FFCC-style: predict illuminant in log-chroma (u=log G/R, v=log G/B)."""
    def __init__(self, model):
        self.model = model

    def step(self, f: Frame) -> tuple:
        u, v = self.model(f.linear)                     # trained on Gehler/Cube+/NUS
        return (float(np.exp(u)), 1.0, float(np.exp(v)))

class ContrastAF:
    """Baseline sweep; swap for a learned dual-pixel model (Herrmann et al. 2020)."""
    def sharpness(self, f: Frame) -> float:
        y = f.linear.mean(-1)
        return float(np.var(np.diff(y, 2, axis=0)) + np.var(np.diff(y, 2, axis=1)))


# ---------------------------------------------------------------- settings planner
@dataclass
class Limits:
    min_shutter: float = 1 / 8000
    max_shutter_static: float = 1 / 4       # tripod-ish
    blur_px_budget: float = 1.0             # Night Sight-style motion metering
    iso_range: tuple = (100, 6400)

def plan(target_exposure: float, cur: Settings, motion_px_s: float, L=Limits()) -> Settings:
    """Split total exposure into shutter + ISO (aperture held fixed here).
    Prefer long shutter (less noise) up to the motion-blur limit, then add gain."""
    max_shutter = L.max_shutter_static if motion_px_s <= 0 else min(
        L.max_shutter_static, L.blur_px_budget / motion_px_s)
    base = target_exposure * cur.aperture_f ** 2       # = shutter * iso/100
    shutter = float(np.clip(base, L.min_shutter, max_shutter))
    iso = float(np.clip(100 * base / shutter, *L.iso_range))
    return replace(cur, shutter_s=shutter, iso=iso)


# ---------------------------------------------------------------- control loop
class AutoCamera:
    def __init__(self, cam: Camera, ae: AEController, awb, smoothing=0.5):
        self.cam, self.ae, self.awb, self.a = cam, ae, awb, smoothing

    def tick(self) -> Settings:
        f = self.cam.preview()
        ratio = self.ae.step(f) ** self.a                # damp to avoid oscillation
        s = plan(f.settings.exposure * ratio, f.settings, f.motion)
        s = replace(s, wb_gains=self.awb.step(f))
        self.cam.apply(s)
        return s

    def converge(self, max_iters=10, tol=0.05) -> Settings:
        s = self.cam.preview().settings
        for _ in range(max_iters):
            new = self.tick()
            if abs(np.log(new.exposure / s.exposure)) < tol:
                return new
            s = new
        return s


# ---------------------------------------------------------------- training data
def make_ae_targets(scenes, metric: Metric = gradient_info, ratios=np.geomspace(1/16, 16, 41)):
    """Self-supervised labels: for each RAW scene and random start exposure, the
    oracle best exposure ratio under `metric`. Train LearnedAE to regress log(ratio)."""
    rng = np.random.default_rng(0)
    for scene in scenes:                   # e.g. MIT-Adobe FiveK RAWs via rawpy, linear
        cam = SimulatedCamera(scene)
        start = replace(Settings(), shutter_s=float(rng.choice(np.geomspace(1/2000, 1/8, 9))))
        cam.apply(start)
        f = cam.preview()
        best_r, best = 1.0, -np.inf
        for r in ratios:
            cam.apply(plan(start.exposure * r, start, 0.0))
            sc = metric(to_display(cam.preview().linear))
            if sc > best:
                best_r, best = r, sc
        yield f, np.log(best_r)


if __name__ == "__main__":
    scene = np.random.default_rng(1).gamma(0.6, 0.05, (240, 320, 3))   # stand-in for RAW
    auto = AutoCamera(SimulatedCamera(scene), GradientAE(), GrayWorldAWB())
    print(auto.converge())
