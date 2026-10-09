# homeassistant_wyoming_hermes

Wire Wyoming speech-to-text and text-to-speech, and Hermes as the conversation agent, into Home Assistant's Assist pipeline.

Machine: [machines/homeassistant_wyoming_hermes.yml](../machines/homeassistant_wyoming_hermes.yml)

```mermaid
stateDiagram-v2
    [*] --> wait_for_homeassistant
    homeassistant_wyoming_hermes --> done: done
    homeassistant_wyoming_hermes --> failed: error (implicit)
    wait_for_homeassistant --> homeassistant_wyoming_hermes: done
    wait_for_homeassistant --> failed: error (implicit)
    done --> [*]
    failed --> [*]
```
