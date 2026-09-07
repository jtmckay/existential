# Existential Website Strategy (Dropbox Notes–Backed Version)

## Overview

Existential’s current public docs strongly explain architecture and implementation but under‑emphasize the core problems it solves and the concrete automations envisioned in internal notes. This report blends the existing docs with the `Existential LLC_Existential.md` Dropbox notes to give a designer or writer enough material to build a problem‑driven site that reflects the real vision.[^1][^2][^3]

The objective is a hand‑offable blueprint: what pains to foreground, how Existential’s approach addresses them, which flows and use cases to feature (from internal automation ideas), and what page changes are required.

## Internal Vision from Dropbox Notes

### Automation and AI use cases

The `Existential LLC_Existential.md` file lists concrete AI and automation ideas that clarify what Existential is meant to do in practice.[^1]

Key examples include:

- **Daily email → audio summary:** Summarize daily email into an audio file the user can listen to instead of reading a full inbox.[^1]
- **Book summaries:** Generate summaries of books, likely from notes or transcripts, to feed personal knowledge management (PKM).[^1]
- **SBIR bot:** An assistant that helps navigate SBIR (Small Business Innovation Research) opportunities, suggesting that Existential should support specialized research and grant workflows.[^1]
- **Meeting capture pipeline:** Record meetings, transcribe them into notes, summarize, extract action items, and add everything to a PKM knowledge base.[^1]
- **Jarvis‑style assistant:** A general household/business assistant that orchestrates multiple automations under a single persona.[^1]
- **Automation selection form:** A form that presents available automations in a hardcoded order, with options hidden when prerequisites are not met, so users can toggle flows on/off without touching YAML or code.[^1]
- **YouTube processing pipeline:** Download a transcription of a YouTube video, summarize and extract insights, convert key points to text‑to‑speech, generate video snippets from the original, and publish an event.[^1]

These ideas map directly onto the flows and AI spine described in the docs but give more concrete narratives that the website should surface.

### Implications for positioning

The notes show Existential as:

- A **personal and business automation hub** for information and media (email, meetings, YouTube, books) rather than only a generic self‑hosting stack.[^4][^1]
- A **PKM engine** where recordings, emails, and documents become structured notes and tasks in a durable knowledge base.[^4][^1]
- A **Jarvis‑like assistant with controls**, where users can explicitly choose which automations are active via a form, matching the four‑knob flow model (input, judgment, work, output).[^5][^1]

The public site should therefore talk about Existential as "the place where your raw digital streams become organized knowledge and action" rather than only "a way to run many containers."[^5][^1]

## Core Problem, Reframed with Notes

### Problem: fragmented digital streams and unpaid sysadmin work

Public self‑hosting writing repeatedly notes that the hardest part is not setup but the ongoing overhead of reverse proxies, TLS, DNS, backups, and monitoring, multiplied by every app. Users describe "surrendering" self‑hosting because maintaining many services becomes a part‑time job.[^2][^3][^6][^7][^8][^9][^10]

The internal notes add another dimension: even when services exist, **information remains fragmented** across email, meetings, videos, and books, with no reliable pipeline into PKM or action items.[^1]

Combined, the problem is:

> Running your digital life and AI locally means wiring many services together and then building ad‑hoc scripts for email, meetings, and media — turning into a job and still leaving information scattered.

### Problem: AI and memory scattered across tools

Community discussions highlight that local AI tools usually live in one app (browser chat, IDE assistant) and require separate configuration per surface, while cloud assistants can change behavior or lose memory after platform updates.[^11][^12][^13][^14]

The internal ideas — Jarvis, SBIR bot, meeting and YouTube pipelines — show a desire for **one assistant with durable memory and shared knowledge**, accessible via voice, email processing, PKM, and automations, not separate bots per app.[^1]

The problem becomes:

> There is no single, local assistant that sees your inbox, meetings, notes, and videos as one knowledge base and can act on it reliably over time.

## Existential’s Approach in Light of Notes

### Plumbing once, then flows

The docs already state that Existential solves hostnames, HTTPS, storage tiers, logging, secrets, backups, and automation once and applies it to everything. That platform layer is essential but invisible to end‑users.[^15][^4]

The Dropbox ideas show **what this plumbing enables**:

- Meeting pipelines depend on storage, transcription, and PKM indexing working seamlessly.[^16][^1]
- YouTube pipelines depend on downloads, speech‑to‑text, summarization, and event publishing as a single flow.[^5][^1]
- Daily email summaries depend on mail integration, text processing, audio generation, and delivery to a listening surface (phone, speaker).[^5][^1]

Thus, the approach section on the site should present plumbing as *the substrate* that makes these flows straightforward to configure, not as the primary value.

### One AI spine matched to Jarvis vision

Docs describe an AI spine with:

- Gateway (Hermes) as one OpenAI‑compatible endpoint and memory/skills host.[^15]
- Models (Ollama) as swap‑able weights.[^15]
- Knowledge store (OpenViking) and memory (Honcho) as durable context and per‑user memory.[^16][^15]
- Web reader (Firecrawl) and speech components (Wyoming Whisper/Piper) for input/output.[^15]

The internal Jarvis and SBIR bot concepts map directly onto this spine:

- Jarvis is essentially **Hermes + Honcho + OpenViking + decree**, with multiple surfaces (voice, editor, automations) calling the same brain.[^15][^1]
- SBIR bot is a specialized **Hermes skill** using OpenViking for research context and decree for follow‑up actions (calendar tasks, document drafting).[^5][^1]

Website copy should explicitly connect Jarvis‑style and SBIR‑style assistants to this architecture, showing that they are first‑class citizens, not side projects.

### Flows aligned with specific internal use cases

The flows model (input → judgment → work → output, controlled by four knobs) is ideal for the Dropbox pipeline ideas.[^5]

Examples for the site:

- **Meetings → notes → tasks**
  - Input: meeting recording file or live recording.
  - Judgment: is this recording worth processing (e.g., longer than N minutes, tagged as work)?[^5]
  - Work: transcribe, summarize, extract action items, link to related PKM notes; store in `workspace/`.[^16][^1]
  - Output: a note in PKM, tasks in a project list, and a notification.

- **Inbox → daily audio brief**
  - Input: all emails received in the last 24 hours.[^1]
  - Judgment: which messages matter (TRIAGE_CRITERIA prompt).[^5]
  - Work: summarize important messages into a narrative; generate audio via text‑to‑speech.[^15][^1]
  - Output: audio file accessible via phone or smart speaker.

- **YouTube → insight bundle**
  - Input: a YouTube URL.[^1]
  - Judgment: is this video worth processing (e.g., non‑short, specific playlists)?[^5]
  - Work: download transcription, summarize key points, extract insights; TTS for highlights; generate video snippets.[^1]
  - Output: PKM note with text, audio file, clips saved to storage, and an event in automation logs.[^16][^1]

These become compelling examples on the Flows page and in the Home/Why narrative.

### PKM and workspace emphasis

Docs already describe `workspace/` as the agent’s knowledgebase, indexed by OpenViking, synced via MinIO/Nextcloud, and triggering MinIO events for decree routines.[^16]

Dropbox notes reinforce that **PKM is central**, with meeting outputs and other processed content feeding into a knowledge base.[^1]

The site should:

- Market `workspace/` explicitly as "your notes and knowledge hub".
- Show how flows deposit outputs into PKM, making AI and automation feel like extensions of note‑taking rather than separate tools.[^16][^1]

## Proposed Page Map Using Dropbox Content

### Home / Why

Incorporate notes‑driven narrative:

- Headline: "Turn your inbox, meetings, and media into one local assistant with a memory."[^15][^1]
- Subtext: "Existential wires together open‑source services so email, meetings, YouTube, and notes all flow into a durable knowledge base and Jarvis‑style assistant — on your hardware, with no subscriptions."[^4][^1]
- Three illustrative tiles:
  - Daily email → audio brief.
  - Meeting → notes → tasks.
  - YouTube → insights, audio, and clips.[^5][^1]

### Flows / What It Does

Base it on `flows/index.md` but add internal use cases:[^5][^1]

- Section for **Information flows** (email, meetings, books).
- Section for **Media flows** (YouTube, podcasts).
- Section for **Specialized assistants** (SBIR bot, Jarvis persona).

Each example should list trigger, judgment, work, and output, with copy drawn from both docs and notes.[^5][^1]

### How It Works

Keep the architecture detail from `how-it-works.md` but add callouts:

- Hermès callout: "This is where Jarvis lives; every skill (SBIR bot, meeting processor, YouTube pipeline) is a configuration here, not a separate stack."[^15][^1]
- OpenViking/Honcho callout: "Where meeting notes and SBIR research live and where user memory persists."[^16][^15][^1]

### PKM / Workspace page (new or expanded)

Create a dedicated page or section explaining:

- `workspace/` as the central PKM directory.[^16]
- How flows deposit structured outputs there (meeting notes, summary files, insight docs).[^1]
- Integration paths from existing vaults (Obsidian, etc.), connecting to existing PKM docs if present.[^16]

### Automation Control page or component

Use the "Form with options for each automation" idea:[^1]

- Show a UI where automations (daily email summary, meeting pipeline, YouTube pipeline, SBIR bot) can be toggled.
- Explain that prerequisites (e.g., email integration, storage) control visibility.
- Tie this back to the flows four‑knob model: the form configures input and work without code.[^5][^1]

## FAQ / Objections with Notes-Informed Answers

Build FAQ answers from external pain points and internal vision:[^3][^6][^8][^10][^14][^1]

- **"Why not just use cloud AI and SaaS?"**
  - Answer: cloud tools do not see your full digital stream, can change behavior or lose memory, and accrue subscription costs; Existential’s Jarvis‑like assistant runs on your hardware with your data, and flows feed PKM in a durable way.[^12][^13][^14][^1]

- **"Isn’t this too complex to set up?"**
  - Answer: plumbing (TLS, DNS, storage, monitoring) is solved once; most user choices are at the automation form level (which flows to turn on), not at Docker YAML level.[^15][^16][^1]

- **"Does this only help homelab nerds?"**
  - Answer: meeting pipelines, email summaries, and SBIR‑style flows explicitly support small businesses and professionals who need PKM and automation, not only hobbyists.[^17][^1]

## Implementation Checklist for Site Creators

### Content tasks

- Extract and adapt narratives from `Existential LLC_Existential.md` into:
  - Home/Why example flows.
  - Flows page sections.
  - PKM/workspace and automation control copy.[^1]
- Reuse existing docs (`intro.md`, `how-it-works.md`, `getting-started.md`, `flows/index.md`) for technical detail but move them behind problem‑centric pages.[^4][^15][^16][^5]

### Design tasks

- Create visuals for daily email → audio brief, meeting → notes → tasks, and YouTube pipeline.
- Design an automation toggle form matching the notes description.[^1]
- Ensure architecture diagrams stay confined to "How It Works" and developer docs.

### Navigation tasks

- Make Home/Why the default landing page.
- Add top‑level links for Flows, PKM/Workspace, How It Works, Getting Started, and FAQ.
- Deep‑link from examples to relevant docs (e.g., meeting pipeline to flows detail pages).

With these changes, the website will present Existential not just as a sophisticated self‑hosting scaffold, but as the concrete realization of the automation and PKM vision captured in the Dropbox notes — a local Jarvis that turns the user’s real streams (email, meetings, media, grants) into organized knowledge and action, backed by robust plumbing.[^6][^3][^4][^15][^16][^5][^1]

---

## References

1. [Existential/Existential LLC_Existential.md](Existential/Existential LLC_Existential.md)

2. [I surrender : r/selfhosted](https://www.reddit.com/r/selfhosted/comments/1jbu4m1/i_surrender/) - Over the last years I started many private projects away from my homelab. Biking, car restoration, b...

3. [I finally understand the hardest part of self-hosting, and it's ...](https://www.xda-developers.com/the-hardest-part-of-self-hosting-is-not-the-setup/) - Your reverse proxy should be on the edge router/firewall IMO, not your actual hosting machine. And y...

4. [docs/intro.md](docs/intro.md)

5. [docs/flows/index.md](docs/flows/index.md)

6. [Things I Stopped Self-Hosting (And Why Cloud or ...](https://www.virtualizationhowto.com/2025/12/things-i-stopped-self-hosting-and-why-cloud-or-managed-won/) - What I stopped self hosting in my home lab and why cloud and managed services reduced stress, improv...

7. [Self-hosting without panic (9/12): Networking basics for ...](https://blog.stackademic.com/self-hosting-without-panic-9-12-networking-basics-for-self-hosters-dns-ports-reverse-proxy-0155323cdf8d) - Centralized TLS: The reverse proxy handles all certificate management. Your backend services don't n...

8. [The 6 excuses that stopped me from self-hosting my own ...](https://www.howtogeek.com/the-excuses-that-stopped-me-from-self-hosting-my-own-services-and-why-each-excuse-was-wrong/) - It's too hard to set up · The hardware costs a fortune · My electricity bill would skyrocket · Self-...

9. [Self-hosting like a final boss: what I actually run on my ...](https://dev.to/dev_tips/self-hosting-like-a-final-boss-what-i-actually-run-on-my-home-lab-and-why-48k1) - Then set up monitors for your services and get Telegram/email/Discord alerts when something dies (pr...

10. [Self-hosting is great, but I also see why people don't do it](https://www.xda-developers.com/why-people-dont-self-host/) - Explore the benefits and drawbacks of self-hosting, including privacy, convenience, technical challe...

11. [Are there any local AI clients that work across devices?](https://www.reddit.com/r/ChatGPTPro/comments/1jverhx/are_there_any_local_ai_clients_that_work_across/) - Hi everyone, It always intrigues me how there seems to be strange gaps in the otherwise humongous an...

12. [I Romanticized Running a Local LLM. Here's What Reality ...](https://blog.stackademic.com/i-romanticized-running-a-local-llm-heres-what-reality-taught-me-5704409d0d57) - The honest story of building a personal AI assistant on local LLMs — and what I actually learned alo...

13. [Challenges and Trade-offs of Local AI - DockYard](https://dockyard.com/blog/2025/04/03/challenges-trade-offs-local-ai) - Unlike cloud-based models that can leverage powerful servers and GPUs, local AI models run on device...

14. [Catastrophic Failures of ChatGpt that's creating major ...](https://community.openai.com/t/catastrophic-failures-of-chatgpt-thats-creating-major-problems-for-users/1156230) - After a backend memory architecture update, ChatGPT's long-term memory system silently broke. Some u...

15. [docs/how-it-works.md](docs/how-it-works.md)

16. [docs/getting-started.md](docs/getting-started.md)

17. [Why Self-host?](https://romanzipp.com/blog/why-a-homelab-why-self-host) - Self-hosting services can reduce or even completely mitigate the risk of being surveilled. But it al...

