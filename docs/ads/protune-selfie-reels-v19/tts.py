#!/usr/bin/env python3
"""Local voiceover TTS: Kokoro-82M (ONNX, Apache-2.0) + espeak-ng phonemes.

No API key or PyPI packages needed beyond numpy + onnxruntime + soundfile-free WAV writing.
Model files (GitHub releases, thewh1teagle/kokoro-onnx model-files-v1.0):
  kokoro-v1.0.onnx, voices-v1.0.bin
espeak-ng library + data: the piper linux release tarball (rhasspy/piper 2023.11.14-2),
  which ships libespeak-ng.so and espeak-ng-data/.
Vocab: kokoro-onnx src/kokoro_onnx/config.json.

Usage: python3 tts.py --models DIR --espeak DIR --vocab config.json \
          --voice am_michael --speed 1.05 --text "Hello." --out line.wav
"""
from __future__ import annotations
import argparse, ctypes, json, re, wave
from pathlib import Path
import numpy as np
import onnxruntime as ort

SR = 24000

class Espeak:
    def __init__(self, root: Path):
        self.lib = ctypes.cdll.LoadLibrary(str(root / "libespeak-ng.so.1"))
        self.lib.espeak_Initialize.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        if self.lib.espeak_Initialize(1, 0, str(root).encode(), 0) <= 0:
            raise RuntimeError("espeak init failed")
        self.lib.espeak_SetVoiceByName(b"en-us")
        self.lib.espeak_TextToPhonemes.restype = ctypes.c_char_p
        self.lib.espeak_TextToPhonemes.argtypes = [ctypes.POINTER(ctypes.c_char_p), ctypes.c_int, ctypes.c_int]

    def ipa(self, text: str) -> str:
        buf = ctypes.c_char_p(text.encode())
        out = []
        while buf.value:
            r = self.lib.espeak_TextToPhonemes(ctypes.byref(buf), 1, 0x02)
            if r: out.append(r.decode())
        return " ".join(out)

def phonemize(es: Espeak, text: str) -> str:
    # keep punctuation (the model uses it for prosody), phonemize the words between
    parts = re.split(r"([.,!?;:—…])", text)
    out = ""
    for p in parts:
        if not p.strip(): continue
        if re.fullmatch(r"[.,!?;:—…]", p): out = out.rstrip() + p + " "
        else: out += es.ipa(p.strip()).replace("͡", "") + " "
    return out.strip()

def synth(text, voice, speed, models: Path, es: Espeak, vocab: dict) -> np.ndarray:
    sess = ort.InferenceSession(str(models / "kokoro-v1.0.onnx"), providers=["CPUExecutionProvider"])
    voices = np.load(models / "voices-v1.0.bin")
    ph = phonemize(es, text)
    toks = [vocab[c] for c in ph if c in vocab]
    names = {i.name: i for i in sess.get_inputs()}
    tok_name = "input_ids" if "input_ids" in names else "tokens"
    tok_dtype = np.int64
    speed_dtype = np.float32 if "float" in names["speed"].type else np.int32
    style = voices[voice][min(len(toks), len(voices[voice])) - 1]
    audio = sess.run(None, {tok_name: np.array([[0, *toks, 0]], tok_dtype),
                            "style": style.astype(np.float32),
                            "speed": np.array([speed], speed_dtype)})[0].ravel()
    return ph, audio.astype(np.float32)

def write_wav(path, a):
    a = np.clip(a, -1, 1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((a * 32767).astype(np.int16).tobytes())

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    for k in ("models", "espeak", "vocab", "voice", "text", "out"): ap.add_argument("--" + k, required=True)
    ap.add_argument("--speed", type=float, default=1.0)
    a = ap.parse_args()
    vocab = json.loads(Path(a.vocab).read_text())["vocab"]
    ph, audio = synth(a.text, a.voice, a.speed, Path(a.models), Espeak(Path(a.espeak)), vocab)
    print(ph); write_wav(a.out, audio)
