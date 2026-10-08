#!/usr/bin/env python3
"""One-shot generator for recipe-scorer-v1.json and golden test fixtures.

The feature order below MUST match SceneFeatures.vectorFeatureNames (Swift).
Run: python3 scripts/dev/generate-scorer-fixtures.py  (outputs committed)
"""
import json, os

REPO = os.path.expanduser("~/workspace/photo-recipes")
RES = os.path.join(REPO, "ios/PhotoRecipes/Resources")
FIX = os.path.join(REPO, "ios/PhotoRecipesTests/Resources/Fixtures/scene-features")

FEATURE_ORDER = [
    "sem.person","sem.animal","sem.vehicle","sem.bicycleOrSport","sem.water","sem.food",
    "sem.landscape","sem.sky","sem.sunsetOrSunrise","sem.nightOrLights","sem.architecture",
    "sem.plantOrFlower","sem.indoor",
    "subject.present","subject.kind.face","subject.kind.human","subject.kind.animal",
    "subject.kind.salientObject","subject.areaFraction","subject.centerX","subject.centerY",
    "motion.logSubjectSpeed","motion.logBackgroundSpeed","motion.logRelativeSpeed",
    "motion.panMatchesSubject","motion.directionX","motion.directionY",
    "light.ev100n","light.highlightClip","light.shadowCrush","light.spreadStopsN",
    "light.subjectDeltaStopsN","light.warmBias",
    "pose.elevationN","pose.shakeLog",
    "intent.sharp-front-to-back","intent.blur-moving-subjects","intent.panning-sharp-subject",
    "intent.get-down-low","intent.hdr-brights-darks","intent.portrait-pop",
    "intent.sharp-and-in-focus","intent.leading-lines","intent.minimalist-photos",
    "intent.exposure-triangle-cheatsheet",
]
assert len(FEATURE_ORDER) == 45, len(FEATURE_ORDER)

RECIPES = {
    # Hand-tuned v1 logits. Positive weight = feature votes FOR the recipe.
    # (Tuned 2026-10-07 against the golden fixtures; see sim in PR notes.)
    "sharp-front-to-back": {"bias": 0.2, "weights": {
        "sem.landscape": 2.0, "sem.architecture": 1.0, "sem.sky": 0.6,
        "light.ev100n": 0.5,
        "motion.logSubjectSpeed": -1.2, "motion.logBackgroundSpeed": -1.0,
        "motion.logRelativeSpeed": -0.8}},
    "blur-moving-subjects": {"bias": -1.5, "weights": {
        "sem.water": 1.2, "sem.nightOrLights": 1.2, "sem.vehicle": 0.8,
        "motion.logSubjectSpeed": 2.5, "motion.logRelativeSpeed": 1.2,
        "motion.logBackgroundSpeed": -1.0, "light.ev100n": -2.0, "pose.shakeLog": -1.2}},
    "panning-sharp-subject": {"bias": -1.0, "weights": {
        "motion.logSubjectSpeed": 1.0, "motion.panMatchesSubject": 2.4,
        "motion.logBackgroundSpeed": 1.0, "subject.present": 0.8,
        "sem.person": 0.6, "sem.animal": 0.6, "sem.vehicle": 0.6,
        "sem.bicycleOrSport": 0.8, "pose.shakeLog": -0.6}},
    "get-down-low": {"bias": -0.8, "weights": {
        "pose.elevationN": 2.8, "subject.centerY": 2.0,
        "sem.animal": 1.0, "sem.plantOrFlower": 1.2,
        "subject.areaFraction": -1.0, "subject.present": 0.8}},
    "hdr-brights-darks": {"bias": -0.8, "weights": {
        "light.highlightClip": 2.5, "light.shadowCrush": 2.2,
        "light.spreadStopsN": 2.0, "sem.sunsetOrSunrise": 1.8,
        "light.subjectDeltaStopsN": -1.5}},
    "portrait-pop": {"bias": -0.5, "weights": {
        "subject.kind.face": 3.0, "subject.areaFraction": 1.5,
        "sem.person": 1.2, "light.subjectDeltaStopsN": -0.8}},
    "sharp-and-in-focus": {"bias": -0.8, "weights": {
        "subject.present": 1.5, "subject.kind.face": 1.0, "subject.kind.human": 1.2,
        "subject.kind.animal": 1.2, "sem.animal": 0.8,
        "motion.logSubjectSpeed": -0.8, "motion.logRelativeSpeed": -0.6,
        "light.spreadStopsN": -1.0, "pose.elevationN": -1.5}},
    "leading-lines": {"bias": -1.0, "weights": {
        "sem.architecture": 2.4, "sem.landscape": 1.2, "subject.present": 0.8,
        "motion.logSubjectSpeed": -0.8}},
    "minimalist-photos": {"bias": -0.8, "weights": {
        "sem.nightOrLights": 2.5, "light.ev100n": -2.0, "sem.sky": 0.8,
        "subject.present": 1.0, "subject.areaFraction": -1.5,
        "light.spreadStopsN": -0.8}},
    # exposure-triangle-cheatsheet: reference card — NEVER auto-selected.
    # No entry here on purpose (scorer only scores autoSelectCandidates).
}
scorer = {
    "_comment": "Hand-tuned v1 recipe scorer (softmax over logits, temperature below). "
                "Feature order MUST match SceneFeatures.vectorFeatureNames. "
                "exposure-triangle-cheatsheet is intentionally absent: it is a reference "
                "card and must never be auto-selected.",
    "schemaVersion": 1,
    "temperature": 1.0,
    "intentBonus": 4.0,
    "featureOrder": FEATURE_ORDER,
    "recipes": RECIPES,
}
os.makedirs(RES, exist_ok=True)
with open(os.path.join(RES, "recipe-scorer-v1.json"), "w") as f:
    json.dump(scorer, f, indent=2)
    f.write("\n")
print("wrote recipe-scorer-v1.json")

# ---------------- fixtures ----------------
def F(sem=None, kind=None, box=None, area=0.0,
      subj_spd=0, bg_spd=0, rel_spd=0, dx=1, dy=0,
      ev=12, hi=0.0, lo=0.0, spread=5, delta=None, warm=0.0,
      elev=0, shake=0.01, intent=None, meter_t=1/60, meter_iso=100, ap=1.8):
    d = {
        "schemaVersion": 2,
        "semanticGroups": sem or {},
        "subjectKind": kind,
        "subjectBox": ({"x": box[0], "y": box[1], "width": box[2], "height": box[3]}
                       if box else None),
        "subjectAreaFraction": area,
        "subjectSpeedPxPerSec": subj_spd,
        "backgroundSpeedPxPerSec": bg_spd,
        "subjectRelativeSpeedPxPerSec": rel_spd,
        "motionDirectionX": dx, "motionDirectionY": dy,
        "meteredExposureSeconds": meter_t, "meteredISO": meter_iso,
        "lensAperture": ap, "exposureTargetOffset": 0, "exposureWasCustom": False,
        "sceneEV100": ev,
        "highlightClipFraction": hi, "shadowCrushFraction": lo,
        "percentileSpreadStops": spread, "subjectDeltaStops": delta,
        "warmBias": warm,
        "cameraElevationDegrees": elev, "handShakeRadPerSec": shake,
        "recipeIntent": ({"recipeId": intent[0], "matchedPhrase": intent[1]} if intent else None),
    }
    return d

FACE = (0.42, 0.30, 0.16, 0.20)   # UI-space face box, centered-ish

fixtures = {
    # sharp-front-to-back
    "mountain-vista": (F(sem={"landscape": 0.9, "sky": 0.7},
                          ev=14, spread=6, shake=0.008), "sharp-front-to-back"),
    "city-architecture-still": (F(sem={"architecture": 0.85, "sky": 0.4},
                                  ev=13, spread=7, shake=0.008), "sharp-front-to-back"),
    # blur-moving-subjects
    "waterfall-tripod": (F(sem={"water": 0.9}, subj_spd=900, bg_spd=30, rel_spd=880,
                              ev=13, shake=0.004, spread=5), "blur-moving-subjects"),
    "night-traffic-trails": (F(sem={"nightOrLights": 0.8, "vehicle": 0.7},
                               subj_spd=600, bg_spd=20, rel_spd=590,
                               ev=2, shake=0.004, spread=8), "blur-moving-subjects"),
    # panning-sharp-subject
    "cyclist-panning": (F(sem={"person": 0.8, "bicycleOrSport": 0.85}, kind="human",
                          box=(0.35, 0.35, 0.3, 0.4), area=0.12,
                          subj_spd=1500, bg_spd=1400, rel_spd=120, dx=1, dy=0.05,
                          ev=13, shake=0.05, spread=5), "panning-sharp-subject"),
    "runner-panning": (F(sem={"person": 0.75}, kind="human",
                         box=(0.4, 0.3, 0.2, 0.45), area=0.09,
                         subj_spd=900, bg_spd=850, rel_spd=80, dx=-1, dy=0,
                         ev=12, shake=0.05, spread=5), "panning-sharp-subject"),
    # get-down-low
    "flower-low-angle": (F(sem={"plantOrFlower": 0.8}, kind="salientObject",
                           box=(0.4, 0.62, 0.2, 0.18), area=0.036,
                           ev=12, elev=35, shake=0.02, spread=5), "get-down-low"),
    "dog-low-angle": (F(sem={"animal": 0.85, "person": 0.2}, kind="animal",
                        box=(0.35, 0.6, 0.3, 0.25), area=0.075,
                        ev=11, elev=22, shake=0.02, spread=5), "get-down-low"),
    # hdr-brights-darks
    "sunset-silhouette": (F(sem={"sunsetOrSunrise": 0.85, "sky": 0.7}, kind="face",
                             box=FACE, area=0.032,
                             ev=10, hi=0.08, lo=0.12, spread=11, delta=-2.5,
                             warm=0.2, shake=0.01), "hdr-brights-darks"),
    "backlit-window": (F(sem={"indoor": 0.7, "architecture": 0.4}, kind="human",
                         box=(0.35, 0.25, 0.3, 0.5), area=0.15,
                         ev=9, hi=0.10, lo=0.10, spread=9, delta=-2.0,
                         shake=0.01), "hdr-brights-darks"),
    # portrait-pop
    "face-closeup-daylight": (F(sem={"person": 0.9}, kind="face",
                               box=(0.3, 0.2, 0.4, 0.45), area=0.18,
                               ev=12, spread=5, delta=-0.5, shake=0.01), "portrait-pop"),
    "face-backlit": (F(sem={"person": 0.85}, kind="face",
                       box=FACE, area=0.032,
                       ev=11, hi=0.06, spread=8, delta=-2.2, shake=0.01), "portrait-pop"),
    # sharp-and-in-focus
    "dog-portrait": (F(sem={"animal": 0.9}, kind="animal",
                       box=(0.35, 0.3, 0.3, 0.35), area=0.105,
                       ev=12, spread=5, shake=0.015), "sharp-and-in-focus"),
    "bird-perched": (F(sem={"animal": 0.8, "plantOrFlower": 0.5}, kind="animal",
                       box=(0.45, 0.35, 0.15, 0.15), area=0.0225,
                       ev=13, spread=5, shake=0.015), "sharp-and-in-focus"),
    # leading-lines
    "bridge-lines": (F(sem={"architecture": 0.9}, kind="salientObject",
                       box=(0.4, 0.4, 0.2, 0.2), area=0.04,
                       ev=12, spread=6, shake=0.01), "leading-lines"),
    "road-vanishing": (F(sem={"architecture": 0.9, "landscape": 0.2}, kind="salientObject",
                         box=(0.45, 0.45, 0.1, 0.1), area=0.01,
                         ev=13, spread=6, shake=0.01), "leading-lines"),
    # minimalist-photos (sparse, dim, single small subject — no sky/landscape
    # for sharp-front-to-back to steal)
    "neon-sign-night": (F(sem={"nightOrLights": 0.9, "indoor": 0.3}, kind="salientObject",
                          box=(0.4, 0.35, 0.2, 0.2), area=0.08,
                          ev=3, spread=6, shake=0.01), "minimalist-photos"),
    "candle-dark": (F(sem={"nightOrLights": 0.8, "indoor": 0.5}, kind="salientObject",
                      box=(0.45, 0.4, 0.1, 0.15), area=0.015,
                      ev=1, spread=5, shake=0.01), "minimalist-photos"),
    # ambiguous: walking person at sunset — motion says pan, light says HDR
    "street-mixed": (F(sem={"person": 0.6, "sunsetOrSunrise": 0.6, "architecture": 0.4},
                       kind="human", box=(0.4, 0.3, 0.2, 0.45), area=0.09,
                       subj_spd=150, bg_spd=30, rel_spd=120,
                       ev=10, spread=8, hi=0.04, lo=0.05, warm=0.15,
                       shake=0.02), None),
    # spec case: upright portrait of a still person in daylight — NOT get-down-low
    "person-standing-daylight": (F(sem={"person": 0.9}, kind="face",
                                  box=(0.38, 0.15, 0.24, 0.3), area=0.072,
                                  ev=13, spread=5, shake=0.01, elev=2), "portrait-pop"),
}

os.makedirs(FIX, exist_ok=True)
manifest = {}
for name, (feat, expected) in fixtures.items():
    with open(os.path.join(FIX, name + ".json"), "w") as f:
        json.dump(feat, f, indent=2)
        f.write("\n")
    manifest[name] = expected
with open(os.path.join(FIX, "expected.json"), "w") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
    f.write("\n")
print(f"wrote {len(fixtures)} fixtures + expected.json")
