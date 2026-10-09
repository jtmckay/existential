# homeassistant_onboarding

Complete Home Assistant's onboarding by creating the admin account from EXIST_USERNAME.

Machine: [machines/homeassistant_onboarding.yml](../machines/homeassistant_onboarding.yml)

```mermaid
stateDiagram-v2
    [*] --> wait_for_homeassistant
    homeassistant_onboarding --> done: done
    homeassistant_onboarding --> failed: error (implicit)
    wait_for_homeassistant --> homeassistant_onboarding: done
    wait_for_homeassistant --> failed: error (implicit)
    done --> [*]
    failed --> [*]
```
