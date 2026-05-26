---
sidebar_position: 10
---

# HAwake — Custom Wake Word Training

Train a custom wake word model for the [HAwake](https://github.com/IT-BAER/hawake-wakeword) Android app using [openWakeWord](https://github.com/dscripka/openWakeWord). The trained ONNX model runs entirely on-device — no cloud, no always-on microphone upload.

Once trained, see [HAwake → Home Assistant → Tasker](./hawake-homeassistant) to wire the wake word to actual automations.

---

## Requirements

- Linux host with Python 3.11 (exactly — see below)
- 4 GB+ RAM for training; 16 GB+ if using the large features file
- ~30 min for a basic model; more with the large features file

---

## 1. Install

### Python 3.11 is required

Python 3.12+ breaks on Linux because `piper-phonemize` has no wheels for 3.12. The install script checks this and aborts if the version is wrong.

```bash
# Fedora/RHEL
sudo dnf install python3.11 python3.11-devel

# Ubuntu/Debian
sudo apt install python3.11 python3.11-venv python3.11-dev
```

Verify before proceeding:
```bash
python3.11 --version  # must print 3.11.x
```

Clone and install:
```bash
git clone https://github.com/IT-BAER/hawake-wakeword.git
cd hawake-wakeword
chmod +x install.sh && ./install.sh
```

### Optional: large features file (better quality)

`openwakeword_features_ACAV100M_2000_hrs_16bit.npy` contains pre-computed embeddings from 2,000 hours of diverse audio. It gives the trainer a much richer pool of hard negatives, which reduces false positives in real-world use. The file is memory-mapped during training so the full 16 GB is never loaded into RAM at once.

```bash
HAWAKE_DOWNLOAD_LARGE_FEATURES=1 ./install.sh
```

Or download manually:
```bash
curl -L -o openwakeword_features_ACAV100M_2000_hrs_16bit.npy \
  https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main/openwakeword_features_ACAV100M_2000_hrs_16bit.npy
```

---

## 2. Apply the torchaudio patch

**Required — do this after every fresh install.** The patch is in the repo but not applied automatically by `install.sh`. Without it, training crashes during audio augmentation:

```
AttributeError: module 'torchaudio' has no attribute 'info'
```

```bash
python patch_torch_audiomentations.py
```

This patches `torch_audiomentations/utils/io.py` inside the venv to use `librosa` instead of the removed `torchaudio.info()` API (removed in torchaudio 2.1+). It backs up the original and only needs to run once per install.

---

## 3. Launch the web UI

```bash
./run_webui.sh
```

Open the URL it prints (typically `http://localhost:7860`).

---

## 4. Train

1. Enter your wake word phrase — e.g. `Hello Computer`
2. Set **number of examples**: 5,000–20,000 recommended
3. Set **training steps**: 5,000+ recommended
4. Click **Start Training**

Training is resumable. If it crashes, re-running detects existing clips and features and skips regeneration.

### Output files

Training creates a folder named after your model (e.g. `Hello_Computer/`):

| Path | Contents |
|---|---|
| `Hello_Computer/positive_train/` | Synthetic wake word clips (training set) |
| `Hello_Computer/positive_test/` | Synthetic wake word clips (validation set) |
| `Hello_Computer/negative_train/` | Background audio (training set) |
| `Hello_Computer/negative_test/` | Background audio (validation set) |
| `Hello_Computer/Hello_Computer.onnx` | Trained model |
| `Hello_Computer/Hello_Computer.tflite` | TFLite conversion (if successful) |

---

## 5. Export for HAwake Android

### Download Model (Opset 11) — this is what HAwake needs

Use the **Download Model (Opset 11)** button in the web UI. This produces an ONNX file patched for Android ONNX Runtime compatibility:

- Opset 11 (Android 8+ support)
- IR version 7 (ONNX Runtime Android ≤ 1.14.0 requires IR ≤ 8)
- `allowzero` stripped from Reshape nodes (unsupported by older runtimes)

**Import this file into HAwake.** The `.tflite` export is for TFLite runtimes and is not used by HAwake.

---

## Troubleshooting

| Error | Fix |
|---|---|
| `high <= 0` crash at start of training | `positive_test/` was empty when training sampled clip durations. Re-run — if clips are present it will proceed. |
| `AttributeError: module 'torchaudio' has no attribute 'info'` | Run `python patch_torch_audiomentations.py` (step 2 above). |
| `weights_only` error | Run `python patch_dp.py`. |
