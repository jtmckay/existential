---
sidebar_position: 12
---

# AutoVoice — Voice Triggers via Tasker

[AutoVoice](https://joaoapps.com/autovoice/) is a Tasker plugin by João Dias that uses Android's speech recognition to trigger Tasker profiles from voice commands — no custom model training required.

AutoVoice supports both on-demand (tap-to-activate) and always-on hotword modes. Use it as an alternative to [HAwake](./hawake) when you want to skip custom model training and rely on Android's built-in speech stack instead.

---

## How it differs from HAwake

| | HAwake | AutoVoice |
|---|---|---|
| Trigger method | Always-on wake word (custom trained ONNX model) | On-demand tap, hotword, or continuous — your choice |
| Setup effort | Model training + HAwake app config | Tasker plugin only |
| Latency | Instant (fully on-device) | Instant in hotword mode; tap-first in on-demand mode |
| Privacy | Fully local | Uses Android speech recognition (may send audio to Google) |
| Best for | Hands-free with a custom phrase, no Google dependency | Faster setup; hotword mode for always-on without model training |

---

## Setup

### 1. Install AutoVoice

Install from the [Play Store](https://play.google.com/store/apps/details?id=com.joaomgcd.autovoice) and grant microphone and accessibility permissions.

### 2. Create a Tasker profile

1. In Tasker: **+ → Event → Plugin → AutoVoice → Recognized**
2. Tap the pencil icon to configure the AutoVoice event
3. Set **Command Filter** to match your phrase — e.g. `start recording`
4. Save the profile and attach your task (see example below)

AutoVoice supports partial matching and regex filters, so `start.*recording` would match "start recording", "start a recording", etc.

### 3. Trigger recognition

AutoVoice can be triggered several ways:

- **AutoVoice widget or shortcut**: tap to activate recognition
- **AutoVoice Screen**: show a listening overlay on screen
- **AutoVoice Hotword**: always-on wake word detection — configure a trigger phrase in **AutoVoice Settings → Hotword**; AutoVoice listens for it and starts full recognition on match (uses Android's built-in hotword engine, no custom model)
- **AutoVoice Continuous**: always-on recognition without a wake word — every utterance is processed (highest battery cost; enable in AutoVoice settings)
- **Another Tasker task**: `Plugin → AutoVoice → Start Listening`

---

## Example: voice → Home Assistant → recording

This mirrors the [HAwake → HA → Tasker flow](./hawake-homeassistant) but uses AutoVoice as the trigger instead of a wake word.

### Tasker profile

- **Event**: AutoVoice Recognized — Command Filter: `start recording`

### Task — Send HA webhook

Instead of waiting for an event from HA, you can call the HA REST API directly from Tasker:

| # | Action | Detail |
|---|--------|--------|
| 1 | HTTP Request | Method: POST, URL: `https://homeassistant.internal/api/webhook/voice_start_recording`, Headers: `Authorization: Bearer <token>` |
| 2 | Vibrate | 200ms |
| 3 | Variable Set | `%IS_recording` → `true` |
| 4 | Record Audio | `Recordings/%DATE_%TIME.mp4` |
| 5 | Perform Task | RecordingTimerTask |

### HA webhook automation

In HA, create an automation triggered by the webhook:

```yaml
alias: AutoVoice → start recording
triggers:
  - trigger: webhook
    webhook_id: voice_start_recording
    allowed_methods:
      - POST
conditions: []
actions:
  - event: taskerha_message
    event_data:
      type: recording_start
      message: voice triggered
```

Register the webhook ID (`voice_start_recording` above) under **Settings → Automations → trigger: Webhook** in HA. The webhook ID becomes the last segment of the URL.

---

## Listening modes

**On-demand** (recommended to start): activate recognition via a widget or shortcut when you want to give a command. Lowest battery use, no background process.

**Hotword** (`AutoVoice Settings → Hotword`): configure a trigger phrase and AutoVoice listens for it using Android's built-in hotword engine. When detected it starts full recognition — functionally equivalent to HAwake's always-on behavior, but without custom model training. Battery impact is low-to-moderate depending on the device.

**Continuous** (`Settings → Continuous Recognition` in AutoVoice): AutoVoice processes every utterance without a wake phrase. Highest battery cost; useful when you want to trigger commands from ambient audio.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| AutoVoice not recognized in Tasker profiles | Fully restart Tasker after installing or updating AutoVoice |
| Recognition never fires | Check that AutoVoice has microphone permission and isn't blocked by battery optimization |
| HTTP request to HA fails | Confirm the long-lived token is valid; test the webhook URL with `curl` from a terminal |
| Command filter doesn't match | Enable **Partial Match** in the AutoVoice event config, or use a broader regex |
