---
sidebar_position: 10
---

# Home Assistant

- Source: https://github.com/home-assistant/core
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: openHAB, Domoticz, Node-RED

Open-source home automation platform. Integrates with thousands of devices and services, supports local processing, and serves as the event bus for voice-triggered automations.

Home Assistant is a [complementary service](../how-it-works#core-vs-complementary-services) — nothing else in the stack talks to it, so it can run on its own machine or its own schedule without affecting anything. That matters more here than for most: if you're using a Zigbee or Z-Wave stick, HA needs to live on the machine that stick is plugged into, which may not be the machine running the rest of the stack. It still comes up from the repo root with everything else (`./existential.sh && docker compose up -d`) — being complementary means you *can* move it, not that it needs separate commands.

See the blog post [Optimizing my life, now with Home Assistant](/blog/optimizing-my-life-home-assistant) for a real-world setup walkthrough.

## Getting Started

1. Enable the service in `.env.shared`:
   ```
   EXIST_IS_SERVICES_HOMEASSISTANT=true
   ```
2. Run `./existential.sh` to render templates and regenerate the compose file
3. Start the container:
   ```bash
   docker compose up -d homeassistant
   ```
4. Open `https://homeassistant.EXIST_DOMAIN` and complete the onboarding wizard to create your admin account

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

See [HAwake → Home Assistant → Tasker](../flows/hawake-homeassistant) for a complete example of using a custom wake word to trigger Tasker actions through HA.

## Services

| Endpoint | URL |
|---|---|
| Web Interface | https://homeassistant.EXIST_DOMAIN |
| REST API | https://homeassistant.EXIST_DOMAIN/api/ |

## Debugging

```bash
# Container logs
docker logs homeassistant

# Configuration check (run inside the container)
docker exec homeassistant python -m homeassistant --script check_config --config /config

# Recent HA log entries
docker exec homeassistant tail -n 100 /config/home-assistant.log
```
