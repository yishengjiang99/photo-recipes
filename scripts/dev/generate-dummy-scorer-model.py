#!/usr/bin/env python3
"""Generate a tiny dummy Core ML recipe scorer for the test bundle.

This is plumbing only — NOT a trained model. It exists so
`CoreMLRecipeScorerTests` can verify the model loads and returns five
probabilities without shipping real weights.

Built with the MIL builder (the coremltools 9.0 sklearn converter is
incompatible with modern sklearn, and this avoids the dependency):
  input:  one fp32 multiarray "features" of shape (45,),
          in SceneFeatures.vectorFeatureNames order
  output: one fp32 multiarray of shape (5,), softmaxed (name varies by
          converter backend — CoreMLRecipeScorer accepts any 5-wide
          multiarray output)

The production contract (scripts/train-recipe-scorer/README.md) also
accepts a classifier with a "classProbability" dict; CoreMLRecipeScorer
handles both output forms.

Run: /tmp/coreml-venv/bin/python scripts/dev/generate-dummy-scorer-model.py
Output: ios/PhotoRecipesTests/Resources/DummyScorer.mlmodel
"""
import numpy as np
import coremltools as ct
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.mil import types

rng = np.random.default_rng(7)
W = rng.normal(scale=0.1, size=(5, 45)).astype(np.float32)
b = rng.normal(scale=0.1, size=(5,)).astype(np.float32)


@mb.program(
    input_specs=[mb.TensorSpec(shape=(45,), dtype=types.fp32)]
)
def prog(features):
    logits = mb.linear(x=features, weight=W, bias=b)
    probs = mb.softmax(x=logits, axis=-1)
    return probs


mlmodel = ct.convert(
    prog,
    convert_to="neuralnetwork",
    inputs=[ct.TensorType(name="features", shape=(45,), dtype=np.float32)],
    outputs=[ct.TensorType(name="probabilities", dtype=np.float32)],
)
mlmodel.author = "Photo Recipes (dummy test model — not trained)"
mlmodel.license = "Test plumbing only"
mlmodel.short_description = (
    "Dummy 45-feature softmax for CoreMLRecipeScorerTests. "
    "Input 'features' (45,) in SceneFeatures.vectorFeatureNames order; "
    "output 'probabilities' (5,). NOT a trained recipe scorer."
)

out = "ios/PhotoRecipesTests/Resources/DummyScorer.mlmodel"
mlmodel.save(out)
print("wrote", out)
spec = mlmodel.get_spec()
print("inputs:", [(i.name, list(i.type.multiArrayType.shape)) for i in spec.description.input])
print("outputs:", [(o.name, list(o.type.multiArrayType.shape)) for o in spec.description.output])
