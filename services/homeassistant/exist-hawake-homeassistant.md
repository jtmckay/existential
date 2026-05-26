# HAwake → Home Assistant → Tasker Integration

Full end-to-end setup for using a custom wake word to trigger Tasker actions (e.g. audio recording) via Home Assistant.

For training the wake word model itself, see [exist-README.md](exist-README.md) — it covers installation, the required patches, and how to export the correct model file for HAwake.

---

## How it works

HAwake has a "Speech Recognition Mode" setting that is supposed to use HA's assist pipeline for speech-to-text — but this is not fully implemented in Home Assistant and will fail. **That failure doesn't matter.** What HAwake *does* reliably do is fire a `hawake_wakeword` event to HA when the wake word is detected. That event is all we need.

Flow:
```
Wake word detected (HAwake on phone)
  → fires hawake_wakeword event to Home Assistant
    → HA automation fires taskerha_message event
      → TaskerHA plugin receives it in Tasker
        → Tasker task runs (e.g. start recording)
```

---

## Step 1: HAwake app

In the HAwake Android app:
- Connect it to your Home Assistant instance (URL + long-lived access token)
- Enable **"Send wake word event to HA"**
- Speech Recognition Mode can be set but will likely fail — that's fine, the event still fires

---

## Step 2: Verify the event in Home Assistant

Before building the automation, confirm the event is arriving:

1. HA → **Developer Tools → Events**
2. Type `*` in "Listen to events" → click **Start Listening**
3. Trigger your wake word on the phone
4. Confirm `hawake_wakeword` appears in the log

---

## Step 3: Home Assistant automation

Create an automation that listens for the wake word event and fires a Tasker-bound event:

```yaml
alias: Wake word test
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

The `type` and `message` values are what Tasker will match on — you can set them to anything, just keep them consistent with what you configure in Tasker.

---

## Step 4: Install TaskerHA

TaskerHA is a Tasker plugin that connects Tasker on Android to Home Assistant events.

- GitHub: https://github.com/db1996/TaskerHa
- Install the plugin and connect it to your HA instance
- **After installing or updating, fully exit and restart Tasker** — the plugin may not load correctly otherwise

---

## Step 5: Tasker tasks

Create three tasks in Tasker.

### Task 1 — Wake Word Triggered (entry point)

This task is triggered by the `taskerha_message` event from TaskerHA (match on the `type` you set in the HA automation).

| # | Action |
|---|--------|
| 1 | Vibrate 200ms |
| 2 | Stop Task: RecordingTimerTask |
| 3 | If `%IS_recording` neq `true` |
| 4 | Variable Set `%IS_recording` → `true` |
| 5 | Record Audio: `Recordings/%DATE_%TIME.mp4` |
| 6 | End If |
| 7 | Perform Task: RecordingTimerTask |

**Logic:** The vibrate confirms the wake word fired. If already recording, it resets the timer (stops and restarts `RecordingTimerTask`) without starting a new recording. If not recording, it starts one and then starts the timer.

### Task 2 — RecordingTimerTask (auto-stop timer)

| # | Action |
|---|--------|
| 1 | Wait: 1 hour |
| 2 | Perform Task: RecordingStop |

**Logic:** Acts as a watchdog. If the recording hasn't been stopped manually, this stops it after 1 hour. Waking the wake word again resets this timer (Task 1 kills and restarts it).

### Task 3 — RecordingStop

| # | Action |
|---|--------|
| 1 | Record Audio Stop |
| 2 | Variable Set `%IS_recording` → `false` |
| 3 | Vibrate 100ms |
| 4 | Wait 100ms |
| 5 | Vibrate 100ms |

**Logic:** Stops the recording and resets the state variable. The double short vibrate distinguishes "stopped" from the single long "started" vibrate in Task 1.

---

## Vibration pattern reference

| Pattern | Meaning |
|---------|---------|
| 1× 200ms | Wake word detected, recording started |
| 2× 100ms | Recording stopped |
