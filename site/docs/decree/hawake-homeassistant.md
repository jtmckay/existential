---
sidebar_position: 11
---

# HAwake → Home Assistant → Tasker

Wire a custom wake word (trained with [HAwake](./hawake)) to Tasker actions on Android, routed through Home Assistant as the event bus.

---

## How it works

HAwake's "Speech Recognition Mode" setting is supposed to invoke HA's Assist pipeline for speech-to-text — but this is not fully implemented in Home Assistant and will fail. **That failure doesn't matter.** HAwake reliably fires a `hawake_wakeword` event to HA when the wake word is detected, and that event is all we need.

```
Wake word detected (HAwake on phone)
  → fires hawake_wakeword event to Home Assistant
    → HA automation fires taskerha_message event
      → TaskerHA plugin receives it in Tasker
        → Tasker task runs (e.g. start recording)
```

---

## Step 1 — Configure HAwake

In the HAwake Android app:

1. Connect it to your Home Assistant instance (URL + [long-lived access token](./homeassistant#long-lived-access-token))
2. Import the trained ONNX model (Opset 11 — see [HAwake training](./hawake#5-export-for-hawake-android))
3. Enable **"Send wake word event to HA"**

Speech Recognition Mode can remain configured — it just won't succeed. The wake word event fires regardless.

---

## Step 2 — Verify the event arrives

Before building the automation, confirm the event is reaching HA:

1. HA → **Developer Tools → Events**
2. Enter `*` in "Listen to events" → click **Start Listening**
3. Trigger your wake word on the phone
4. Confirm `hawake_wakeword` appears in the log

---

## Step 3 — Create the HA automation

Create an automation that listens for the wake word event and fires a Tasker-bound event:

```yaml
alias: Wake word → Tasker
description: ""
triggers:
  - trigger: event
    event_type: hawake_wakeword
conditions: []
actions:
  - event: taskerha_message
    event_data:
      type: some_type
      message: some message
mode: single
```

Set `type` and `message` to any values — just keep them consistent with what you configure in Tasker.

---

## Step 4 — Install TaskerHA

[TaskerHA](https://github.com/db1996/TaskerHa) is a Tasker plugin that subscribes to Home Assistant events.

1. Install the plugin from the GitHub releases page
2. Connect it to your HA instance (URL + long-lived access token)
3. **After installing or updating, fully exit Tasker and restart it** — the plugin may not load correctly otherwise

---

## Step 5 — Create Tasker tasks

### Task 1 — Wake Word Triggered (entry point)

Triggered by the `taskerha_message` event from TaskerHA (filter on the `type` you set in the HA automation).

| # | Action |
|---|--------|
| 1 | Vibrate 200ms |
| 2 | Stop Task: RecordingTimerTask |
| 3 | If `%IS_recording` neq `true` |
| 4 | Variable Set `%IS_recording` → `true` |
| 5 | Record Audio: `Recordings/%DATE_%TIME.mp4` |
| 6 | End If |
| 7 | Perform Task: RecordingTimerTask |

If already recording, this resets the watchdog timer without starting a new recording. If not recording, it starts one and starts the timer.

### Task 2 — RecordingTimerTask (auto-stop watchdog)

| # | Action |
|---|--------|
| 1 | Wait: 1 hour |
| 2 | Perform Task: RecordingStop |

Acts as a safety net — stops the recording after 1 hour if not stopped manually. Triggering the wake word again resets this timer (Task 1 kills and restarts it).

### Task 3 — RecordingStop

| # | Action |
|---|--------|
| 1 | Record Audio Stop |
| 2 | Variable Set `%IS_recording` → `false` |
| 3 | Vibrate 100ms |
| 4 | Wait 100ms |
| 5 | Vibrate 100ms |

Stops the recording and resets state. The double short vibrate distinguishes "stopped" from the single long "started" vibrate in Task 1.

---

## Vibration reference

| Pattern | Meaning |
|---------|---------|
| 1× 200ms | Wake word detected, recording started |
| 2× 100ms | Recording stopped |
