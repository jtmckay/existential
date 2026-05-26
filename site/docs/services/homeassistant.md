---
sidebar_position: 10
---

# Home Assistant

- Source: https://github.com/home-assistant/core
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: openHAB, Domoticz, Node-RED

Open-source home automation platform. Integrates with thousands of devices and services, supports local processing, and serves as the event bus for voice-triggered automations.

## Features

- **Device Integrations**: 3,000+ integrations — lights, switches, sensors, media players, locks, cameras
- **Automations**: YAML or UI-based rules triggered by time, state, events, or webhooks
- **Dashboards**: Customizable Lovelace UI with cards for every device type
- **Voice Control**: Works with HAwake (custom wake words), Google Assistant, Alexa, and local voice pipelines
- **Local Processing**: Runs entirely on your network — no cloud required
- **Mobile Apps**: Companion apps for Android and iOS with location tracking and notifications
- **Developer Tools**: Event bus, template engine, REST and WebSocket APIs

## Getting Started

1. Enable the service in `.env.exist`:
   ```
   EXIST_IS_SERVICES_HOMEASSISTANT=true
   ```
2. Run `./existential.sh compose` to regenerate the compose file
3. Start the container:
   ```bash
   docker compose up -d homeassistant
   ```
4. Open `https://homeassistant.internal` and complete the onboarding wizard to create your admin account

Home Assistant generates its own `configuration.yaml` on first boot inside the `homeassistant_config` volume — no manual pre-configuration needed.

## Hardware Access

If you're connecting USB hardware (Zigbee sticks, Z-Wave controllers, etc.), uncomment `privileged: true` in `docker-compose.yml` and add the device path:

```yaml
devices:
  - /dev/ttyUSB0:/dev/ttyUSB0
```

Identify the device path on the host:
```bash
ls /dev/serial/by-id/
```

## Long-Lived Access Token

Many integrations (HAwake, Tasker via TaskerHA, external scripts) need a long-lived access token:

1. HA → Profile (bottom-left avatar) → **Long-Lived Access Tokens** → **Create Token**
2. Copy and store the token securely — it's only shown once

## Automations

HA automations are defined in YAML or via the UI under **Settings → Automations & Scenes**.

See [HAwake → Home Assistant → Tasker](../decree/hawake-homeassistant) for a complete example of using a custom wake word to trigger Tasker actions through HA.

## Services

| Endpoint | URL |
|---|---|
| Web Interface | https://homeassistant.internal |
| REST API | https://homeassistant.internal/api/ |

## Debugging

```bash
# Container logs
docker logs homeassistant

# Configuration check (run inside the container)
docker exec homeassistant python -m homeassistant --script check_config --config /config

# Recent HA log entries
docker exec homeassistant tail -n 100 /config/home-assistant.log
```
