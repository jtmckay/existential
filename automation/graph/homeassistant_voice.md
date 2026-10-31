# homeassistant_voice

Wire Wyoming speech-to-text and text-to-speech, and the chat model as the conversation agent, into Home Assistant's Assist pipeline.

Machine: [machines/homeassistant_voice.yml](../machines/homeassistant_voice.yml)

```mermaid
stateDiagram-v2
    [*] --> wait_for_homeassistant
    homeassistant_voice --> done: done
    homeassistant_voice --> failed: error (implicit)
    wait_for_homeassistant --> homeassistant_voice: done
    wait_for_homeassistant --> failed: error (implicit)
    done --> [*]
    failed --> [*]
```
