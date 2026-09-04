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

Home Assistant generates its own `configuration.yaml` on first boot inside the `homeassistant_data` volume — no manual pre-configuration needed.

On a genuinely fresh install, the container restarts itself once a few seconds into the very first boot — that's `entrypoint.sh` finishing a proxy-trust fix HA can't apply until it has written its own storage once (details in that file). If `https://homeassistant.EXIST_DOMAIN` blips or 400s for a moment right after `docker compose up -d`, that's this one-time restart; reload the page and it's gone for good.

## Network & Device Discovery

Home Assistant runs on the shared `exist` bridge network like every other
service, reached through Caddy at `https://homeassistant.EXIST_DOMAIN` — not
`network_mode: host`. That keeps it behind the same TLS/Caddy front door as
the rest of the stack, but it has a real cost: **HA's own Docker docs call
`--net=host` a requirement for zeroconf/mDNS and SSDP/UPnP discovery**, and a
Docker bridge does not forward multicast traffic out to the LAN. Devices and
services that rely on it to announce themselves — Chromecast, Sonos, HomeKit
accessories, ESPHome's auto-discovery, many network printers — will **not**
show up under Settings → Devices & Services → Discovered automatically on this
setup.

This doesn't block using them: add such a device with its integration's
manual/static-IP setup instead of relying on discovery. If you'd rather have
discovery and are fine with HA leaving `exist` (it becomes unreachable by
container name from anything else in the stack, and Caddy can no longer front
it since it isn't publishing 8123 on the bridge), switch to
`network_mode: host` in `docker-compose.yml` yourself and access it directly
on `:8123`.

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

## Voice

Home Assistant's Assist pipeline speaks the **Wyoming protocol** — a small,
line-oriented TCP protocol — not HTTP. That is why the stack ships two
purpose-built services for it rather than reusing WhisperX and Chatterbox,
which are HTTP services HA cannot drive:

| | Service | Port |
|---|---|---|
| Speech → text | [wyoming-whisper](../ai/wyoming-whisper) | `10300` |
| Text → speech | [wyoming-piper](../ai/wyoming-piper) | `10200` |

Both run on **CPU** by design. The GPU is already holding the chat model and
the embedding model; a GPU voice model would evict them mid-answer, and a
spoken reply needs to land immediately anyway.

### Wiring it up

Neither service has a web UI or a `<slug>.<domain>` hostname — Wyoming is raw
TCP, so there is nothing for Caddy to front. You add them inside HA:

1. **Settings → Devices & Services → Add Integration → Wyoming Protocol**
   - Host `wyoming-whisper`, port `10300`
   - Repeat for host `wyoming-piper`, port `10200`
2. **Settings → Voice assistants → Add assistant**
   - Speech-to-text: the wyoming-whisper entry
   - Text-to-speech: the wyoming-piper entry
   - Conversation agent: **Ollama**, pointed at `http://ollama:11434`

The models are chosen globally in `.env.shared` — `EXIST_MODEL_STT`,
`EXIST_MODEL_STT_LANGUAGE` and `EXIST_MODEL_TTS_VOICE`. See
[How it works](../how-it-works) for the full model-selection block.

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

## Backup

Not wired up yet. `homeassistant_data` (recorder SQLite DB + `configuration.yaml`
+ everything else in `/config`) has no `automation-backup` cron — unlike most other
services in this stack, nothing currently copies it off-box. To add one, copy a
`volume-backup` cron file (e.g. `mealie-volume-backup-nightly.md`/`-weekly.md`)
from `services/automation/backup/cron.example/` to a new
`homeassistant-volume-backup-*.md`, point its `VOLUMES:` block at
`homeassistant_data homeassistant`, drop it into
`services/automation/backup/cron/`, and restart `automation-backup`.

## Debugging

```bash
# Container logs
docker logs homeassistant

# Configuration check (run inside the container)
docker exec homeassistant python -m homeassistant --script check_config --config /config

# Recent HA log entries
docker exec homeassistant tail -n 100 /config/home-assistant.log
```
