# Training the recipe scorer (Create ML pipeline)

This directory is the home of the **trained** Core ML recipe scorer — the
future replacement for the hand-tuned `ios/PhotoRecipes/Resources/recipe-scorer-v1.json`.
Nothing here is wired into the app yet; the plumbing (`CoreMLRecipeScorer`,
behind the `RecipeScoring` protocol, opt-in via the Settings toggle
"Core ML recipe scorer") is already in place and falls back to the JSON
scorer when no model is bundled.

## Model contract (must not drift)

The iOS side (`CoreMLRecipeScorer`) expects exactly this:

- **Input**: one feature per `SceneFeatures.vectorFeatureNames`, **in that
  order** (currently 45 dims). New features are appended to the end and bump
  `SceneFeatures.currentSchemaVersion`; never reorder or remove.
- **Output**: a probability distribution over the auto-select candidate
  recipe ids (all bundled recipes except `exposure-triangle-cheatsheet`,
  which is a reference card and is never auto-selected). Either:
  - a classifier with a `classProbability` dictionary keyed by recipe id, or
  - a single multiarray output with one element per candidate, same order as
    `SceneFeatures.autoSelectCandidates`.
- The compiled model ships in the app bundle as `RecipeScorer.mlmodelc`
  (Xcode compiles a bundled `RecipeScorer.mlmodel` automatically at build
  time). **Never commit trained weights to git** — the `.mlmodel` is a build
  input, not a source file; keep it out of the repo like any other weight
  file.

## Training data

The training set is the telemetry the app already emits on
`auto_optimize_success`:

| field | meaning |
|---|---|
| `features_v` | `SceneFeatures` schema version — reject rows from older schemas |
| `feature_vector` | 45 comma-separated floats, 2-decimal quantized, in `vectorFeatureNames` order |
| `top3` | the JSON scorer's top-3 (id:probability) at the time — useful as a prior |
| `recipe_id` | the recipe that was applied |

Labels come from the outcome events on the same `run_id`:

- `optimize_photo_captured` ≤ 30 s after the run → **positive** for `recipe_id`
- `optimize_undone` → **negative** for `recipe_id`
- `optimize_dial_override` → **negative** (the solve missed)
- `optimize_recipe_switched` → **negative** for `from_recipe_id`, **positive** for `to_recipe_id`
- `also_try_tap` → weak positive for the runner-up

Suggested starting point: multinomial logistic regression (or a small
gradient-boosted tree) on the 45 features, with the JSON scorer's top-3
kept as a fallback prior for low-confidence predictions. Keep the model
tiny (< 100 KB) — it runs on every Auto Optimize tap.

## Suggested pipeline (Create ML / coremltools)

1. Export telemetry rows → CSV with columns `f0..f44,label` (`f{i}` in
   `vectorFeatureNames` order; `label` = winning recipe id).
2. Train in Create ML (Tabular Classifier) or sklearn, e.g.:
   ```python
   from sklearn.linear_model import LogisticRegression
   clf = LogisticRegression(multi_class="multinomial", max_iter=1000).fit(X, y)
   ```
3. Convert with coremltools to a classifier whose class labels are the
   recipe ids, so `classProbability` keys map directly:
   ```python
   import coremltools as ct
   mlmodel = ct.converters.sklearn.convert(
       clf, [f"f{i}" for i in range(45)])
   mlmodel.save("RecipeScorer.mlmodel")
   ```
4. Drop `RecipeScorer.mlmodel` into `ios/PhotoRecipes/Resources/` and add it
   to `project.yml` resources (Xcode compiles it to `RecipeScorer.mlmodelc`
   at build time).
5. Validate on-device: enable the Settings toggle, run the 8-scene manual
   table, and confirm the golden fixtures still score correctly. Only then
   consider flipping the default.

## Test dummy

`scripts/dev/generate-dummy-scorer-model.py` builds a random 45→5 softmax
with the MIL builder (the coremltools 9.0 sklearn converter is incompatible
with modern sklearn). It exists only so `CoreMLRecipeScorerTests` can verify
the load-and-predict plumbing. It is not a trained model and must never be
confused with one.
