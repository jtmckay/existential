/**
 * The service tour catalog — what /tour scrolls through.
 *
 * CORE FIRST, EVERYTHING ELSE BEHIND THE DIVIDER. The page is headed "What you actually
 * get", so a card for something Core does not install must never sit among the ones it
 * does — that is how portainer, pihole, uptime-kuma and eight add-ons came to read as
 * part of the system. "It ships in some quest" is not the test.
 *
 * `tier: 'core'` is the Core *experience*, which is slightly wider than the compose file:
 * every hosted service in `src/quests/00-core.md`'s `services:` block, plus the client
 * apps that complete it — Obsidian opens the run, and the devices section closes it.
 * Those carry `kind: 'recommended'` because you install them yourself, but they are Core's
 * story, not add-ons. Everything else is `tier: 'extra'`.
 *
 * ORDER IS LOAD-BEARING and asserted by the renderer's divider: Obsidian first, the hosted
 * Core sections, then "Also on your devices" as the last Core section — and only then the
 * extras, behind a full-width divider, each carrying its own badge. The page header counts
 * the tiers separately. Adding a service to Core means moving its card up into a 'core'
 * section; the tiers are not decoration. Note `hermes-agent-dashboard` is core `hermes`.
 *
 * Blurbs and section grouping otherwise follow `services/dashy/dashy-conf.exist.yml`,
 * the stack's existing source of truth for "which services have a web UI worth linking
 * to"; `source` comes from each service's docs page.
 *
 * Kept as hand-written TS rather than parsed from the Dashy YAML on purpose: the site
 * build has no YAML dependency (`js-yaml` runs in the adhoc container, not in
 * Docusaurus), and every other section of this site declares its content inline the
 * same way — see HomepageLevels.
 *
 * `docs` paths must resolve to a real page: the site sets `onBrokenLinks: 'throw'`,
 * so a typo here fails `npm run build`. Note the docs tree uses `storage/` where the
 * repo uses `nas/`, and the Open WebUI page is `ai/open-web-ui`.
 *
 * `shot` is optional. Leave it off until the image lands in
 * `site/static/img/services/` — the tour renders a labeled placeholder tile instead.
 */

export type TourService = {
  /** Matches the Caddy hostname: https://<slug>.<domain> */
  slug: string;
  name: string;
  /** One line. Lifted from the Dashy tile's `description:`. */
  blurb: string;
  /** What you'd actually use it for, in a couple of sentences. */
  what: string;
  /** '/img/services/<slug>.webp' — omit until the file exists. */
  shot?: string;
  /**
   * What the frame's title bar shows. Hosted services get
   * `<slug>.yourdomain.com` derived from the slug; set this for anything the
   * stack doesn't front over HTTP. Obsidian is a desktop app with no container
   * and no hostname — see site/docs/services/obsidian.md.
   */
  chrome?: string;
  /** Must resolve to a real docs page. */
  docs: string;
  /** Upstream project, for the screenshot credit. Omitted where a card covers several. */
  source?: string;
  /**
   * Not open source. Flips the link label to "Website" and shows `note`.
   * Obsidian is the stack's one deliberate exception.
   */
  proprietary?: boolean;
  /** Short pill under the blurb, for a caveat worth seeing at a glance. */
  tag?: string;
  /** Small caveat line under the description. */
  note?: string;
  /**
   * This card groups several apps rather than being one thing you install, so
   * it doesn't count toward the tour header's tally. `mobile` is the only one.
   */
  summary?: boolean;
};

export type TourSection = {
  name: string;
  kicker: string;
  /**
   * 'hosted'      — Existential runs it: it's in the compose file and has a
   *                 <slug>.<domain> hostname. Every one of these is FOSS.
   * 'recommended' — a client you install yourself. Not deployed by the stack,
   *                 and not necessarily open source.
   */
  kind: 'hosted' | 'recommended';
  /**
   * 'core'  — part of the Core experience: the hosted services the Core quest
   *           installs, plus the client apps that bookend them (Obsidian first,
   *           the devices section last). These come up wired together and are
   *           what the page promises.
   * 'extra' — everything else: real services in the repo, but a flag you turn on
   *           yourself. Every 'extra' section renders after every 'core' one and
   *           behind the divider, so nobody reads an add-on as part of the system.
   */
  tier: 'core' | 'extra';
  /** Optional sentence under the section title, for framing the group. */
  lede?: string;
  services: TourService[];
};

export const TOUR: TourSection[] = [
  {
    name: 'Notes',
    kicker: 'Where a second brain starts',
    kind: 'recommended',
    tier: 'core',
    lede: 'You install this one yourself. It writes plain files into a folder Nextcloud syncs, which is how everything downstream gets at your notes.',
    services: [
      {
        slug: 'obsidian',
        name: 'Obsidian',
        blurb: 'Notes and tasks, as plain Markdown files',
        what: 'The front door to the whole thing: a fast editor over a folder of Markdown files, with backlinks, graph view, and Kanban boards for tasks. The vault sits in a directory Nextcloud syncs, so the notes reach the rest of the stack as plain files — no API, no export step, nothing to integrate.',
        shot: '/img/services/obsidian.webp',
        chrome: 'Obsidian — desktop app, reads your vault folder',
        docs: '/docs/services/obsidian',
        source: 'https://obsidian.md',
        proprietary: true,
        tag: 'Free — but not open source',
        note: 'Free without limits — no sign-up, personal and commercial use alike. Paid Sync, Publish and a commercial licence are there if you want to support the developers. It isn’t open source — but your notes stay plain .md files in a folder you own, so the editor is replaceable.',
      },
    ],
  },
  {
    name: 'The pillars',
    kicker: 'What everything else hangs off',
    kind: 'hosted',
    tier: 'core',
    lede: 'Nextcloud carries your files — the Obsidian vault among them. Home Assistant carries what the house is doing. Hermes reads both. Everything after this section is either a way of talking to Hermes or a way of giving it more to work with.',
    services: [
      {
        slug: 'nextcloud',
        name: 'Nextcloud',
        blurb: 'File sync + collaboration',
        what: 'Dropbox that you own: desktop and mobile sync clients, sharing links, calendars and contacts. It also feeds the agent, and it is where the Obsidian vault lives — so every file you drop in, notes included, is material Hermes can read without an upload step or a third party in the middle.',
        shot: '/img/services/nextcloud.webp',
        docs: '/docs/storage/nextcloud',
        source: 'https://github.com/nextcloud/server',
      },
      {
        slug: 'homeassistant',
        name: 'Home Assistant',
        blurb: 'Smart home automation',
        what: 'Every smart device you own on one dashboard, talking to each other instead of to five different phone apps. It feeds Hermes what the house is doing and doubles as a way to talk back to it by voice — and because automations run locally, the lights still work when the internet is down.',
        shot: '/img/services/homeassistant.webp',
        docs: '/docs/services/homeassistant',
        source: 'https://github.com/home-assistant/core',
      },
      {
        slug: 'hermes-agent-dashboard',
        name: 'Hermes',
        blurb: 'The agent everything else plugs into',
        what: 'The middle of the whole diagram. Your notes, files and house state go in; the chat window, the editor and the voice assistant all come out of it. One OpenAI-compatible endpoint holding the models, the tools and the skills, with a dashboard for watching what it actually did.',
        shot: '/img/services/hermes-agent-dashboard.webp',
        docs: '/docs/ai/hermes',
        source: 'https://github.com/NousResearch/hermes-agent',
      },
    ],
  },
  {
    name: 'Talking to it',
    kicker: 'One brain, more than one front door',
    kind: 'hosted',
    tier: 'core',
    lede: 'Open WebUI is the chat window; Home Assistant above is the same agent by voice. Same models and same memory behind each one.',
    services: [
      {
        slug: 'open-webui',
        name: 'Open WebUI',
        blurb: 'Chat UI routed through hermes-agent',
        what: 'The chat window you actually talk to — threads, file uploads, model switching, all of it running against your own GPU instead of somebody’s API. It looks like the chat app you already use, except nothing you type leaves the house.',
        shot: '/img/services/open-webui.webp',
        docs: '/docs/ai/open-web-ui',
        source: 'https://github.com/open-webui/open-webui',
      },
    ],
  },
  {
    name: 'Extending it',
    kicker: 'Giving Hermes more to work with',
    kind: 'hosted',
    tier: 'core',
    lede: 'Each of these hands the agent something it could not do on its own — a memory of you, and somewhere to look things up.',
    services: [
      {
        slug: 'openviking',
        name: 'OpenViking',
        blurb: 'Context database — notes, scraped resources, agent memory',
        what: 'The searchable side of the agent’s memory: your notes, pages it has scraped, and what it has been told, all indexed. It is what lets Hermes answer from your own material rather than only from what it was trained on.',
        shot: '/img/services/openviking.webp',
        docs: '/docs/ai/openviking',
        source: 'https://github.com/volcengine/OpenViking',
      },
      {
        slug: 'honcho',
        name: 'Honcho',
        blurb: 'Memory that survives the conversation',
        what: 'Cross-session memory for the agent. Without it every conversation starts cold; with it, what Hermes worked out about you last week is still there this week. It runs behind the gateway with no interface of its own.',
        chrome: 'honcho — background service, no web UI',
        docs: '/docs/ai/honcho',
        source: 'https://github.com/plastic-labs/honcho',
      },
    ],
  },
  {
    name: 'Underneath',
    kicker: 'Storage, networking, and knowing it is all up',
    kind: 'hosted',
    tier: 'core',
    lede: 'The parts you stop noticing once they work.',
    services: [
      {
        slug: 'grafana',
        name: 'Grafana',
        blurb: 'Dashboards',
        what: 'Graphs of everything the stack emits — container health, disk headroom, how long the nightly jobs took, whether the GPU is actually being used. The one screen to check when something feels slow.',
        shot: '/img/services/grafana.webp',
        docs: '/docs/hosting/grafana',
        source: 'https://github.com/grafana/grafana',
      },
      {
        slug: 'minio',
        name: 'MinIO',
        blurb: 'S3-compatible object store',
        what: 'An S3 bucket in your basement. Anything that speaks the S3 API — backup tools, app uploads, the AI services stashing artifacts — points at it and works, with a console for browsing what landed.',
        shot: '/img/services/minio.webp',
        docs: '/docs/storage/minio',
        source: 'https://github.com/minio/minio',
      },
    ],
  },
  {
    name: 'The everyday surface',
    kicker: 'Where you see it and where it reaches you',
    kind: 'hosted',
    tier: 'core',
    lede: 'One page linking everything above, and one channel every automation reports back on.',
    services: [
      {
        slug: 'ntfy',
        name: 'Ntfy',
        blurb: 'Push notifications',
        what: 'Push notifications to your phone from a one-line HTTP request, no app account and no vendor in between. Every automation in the stack uses it to tell you a backup finished, a transcript is ready, or something broke.',
        shot: '/img/services/ntfy.webp',
        docs: '/docs/services/ntfy',
        source: 'https://github.com/binwiederhier/ntfy',
      },
      {
        slug: 'dashy',
        name: 'Dashy',
        blurb: 'The front door to everything else',
        what: 'One page with a tile for every service you enabled, grouped and status-checked — a red dot appears the moment something stops answering. It is the bookmark you actually keep, and it is generated from the same config that decides what runs.',
        shot: '/img/services/dashy.webp',
        docs: '/docs/services/dashy',
        source: 'https://github.com/Lissy93/dashy',
      },
    ],
  },
  {
    name: 'Also on your devices',
    kicker: 'The rest of what we would install',
    kind: 'recommended',
    tier: 'core',
    lede: 'The clients that get you at your own data from whatever machine or phone is in front of you.',
    services: [
      {
        slug: 'onlyoffice',
        name: 'ONLYOFFICE Desktop',
        blurb: 'Documents, spreadsheets and slides, on your machine',
        what: 'A desktop office suite with the best .docx / .xlsx / .pptx fidelity of the free options — Microsoft formats open without the layout drift you get elsewhere. It edits files in place in the folder Nextcloud syncs, so Collabora covers the quick edit in a browser tab and this covers the long session.',
        shot: '/img/services/onlyoffice.webp',
        chrome: 'ONLYOFFICE Desktop — edits the files Nextcloud syncs',
        docs: '/docs/services/onlyoffice',
        source: 'https://github.com/ONLYOFFICE/DesktopEditors',
      },
      {
        slug: 'tailscale',
        name: 'Tailscale',
        blurb: 'Reach it all from anywhere, without opening a port',
        what: 'A private network that follows your devices around, built on WireGuard. Your laptop and phone behave as though they were on the home LAN, so every service stays reachable from a hotel or a train without any of it facing the open internet — nothing to port-forward, nothing to expose, no attack surface added.',
        chrome: 'Tailscale — a private network across your devices',
        docs: '/docs/hosting/vpn',
        source: 'https://github.com/tailscale/tailscale',
        tag: 'Free for personal use',
        note: 'The clients are open source (BSD-3), but the coordination service that introduces your devices to each other is Tailscale’s own, and hosted. Headscale is an open-source replacement for that piece if you would rather run it yourself.',
      },
      {
        slug: 'mobile',
        name: 'On your phone',
        blurb: 'The same system, in your pocket',
        what: 'Home Assistant, Obsidian and Nextcloud all ship Android apps, so the house controls, the vault and the files travel with you. Nextcloud backs up your camera roll into Immich’s reach and keeps the vault directory in step; on devices where Obsidian can’t read Nextcloud’s storage directly, FolderSync bridges the two folders.',
        chrome: 'Android — Home Assistant · Obsidian · Nextcloud',
        docs: '/docs/services/mobile',
        summary: true,
      },
    ],
  },
  {
    name: 'More ways in, more for the agent',
    kicker: 'Turn these on and the agent can do more',
    kind: 'hosted',
    tier: 'extra',
    lede: 'None of these is required and nothing in Core depends on them. Each one gives the agent a capability it does not otherwise have, or you another door into it.',
    services: [
      {
        slug: 'code-server',
        name: 'code-server',
        blurb: 'Coding against your own agent',
        what: 'The full editor in a browser tab, reachable from a tablet or a phone. Run opencode inside it and point it at Hermes as its OpenAI endpoint, and the coding assistant shares the same models, skills and memory as everything else here.',
        shot: '/img/services/code-server.webp',
        docs: '/docs/services/code-server',
        source: 'https://github.com/coder/code-server',
      },
      {
        slug: 'comfyui',
        name: 'ComfyUI',
        blurb: 'Node-based image generation workflows',
        what: 'Image generation as a wiring diagram: nodes for the model, the prompt, the sampler and the output. Fiddly once, then endlessly reusable — and a graph you have built becomes something the agent can trigger, which is how Hermes gets the ability to make pictures.',
        shot: '/img/services/comfyui.webp',
        docs: '/docs/ai/comfyui',
        source: 'https://github.com/comfyanonymous/ComfyUI',
      },
      {
        slug: 'chatterbox',
        name: 'Chatterbox',
        blurb: 'Text-to-speech, running locally',
        what: 'Turns text into speech on your own GPU, with voice cloning from a short sample, over an OpenAI-compatible HTTP API. Home Assistant does not use it — HA speaks the Wyoming protocol and Core ships wyoming-piper for that — so this is here for audio you generate yourself, from a routine or your own code.',
        docs: '/docs/ai/chatterbox',
        source: 'https://github.com/resemble-ai/chatterbox',
      },
    ],
  },
  {
    name: 'More of the platform',
    kicker: 'Extra visibility and extra plumbing',
    kind: 'hosted',
    tier: 'extra',
    lede: 'Core already gives every service a hostname, a certificate, logs and metrics. These add to that rather than provide it.',
    services: [
      {
        slug: 'portainer',
        name: 'Portainer',
        blurb: 'Container management',
        what: 'A web UI over Docker: which containers are up, what they are logging, and a shell into any of them. The fastest way to answer “why is that one red” without SSH-ing in and remembering the flags.',
        docs: '/docs/hosting/portainer',
        source: 'https://github.com/portainer/portainer',
      },
      {
        slug: 'uptime-kuma',
        name: 'Uptime Kuma',
        blurb: 'Service availability monitor',
        what: 'Pings every service on a schedule and keeps a wall of green squares. When one turns red it pushes a notification, so you hear about an outage from your own hardware rather than from someone trying to use it.',
        shot: '/img/services/uptime-kuma.webp',
        docs: '/docs/hosting/uptime-kuma',
        source: 'https://github.com/louislam/uptime-kuma',
      },
      {
        slug: 'pihole',
        name: 'Pi-hole',
        blurb: 'DNS + ad-blocking',
        what: 'Network-wide ad and tracker blocking at the DNS layer, which covers the devices you cannot install an extension on. It also resolves the wildcard record that gives every service in this stack its own hostname.',
        shot: '/img/services/pihole.webp',
        docs: '/docs/hosting/pihole',
        source: 'https://github.com/pi-hole/pi-hole',
      },
    ],
  },
  {
    name: 'Apps',
    kicker: 'Pick the ones that match something you actually do',
    kind: 'hosted',
    tier: 'extra',
    lede: 'Ordinary self-hosted apps, sharing the network, the storage and the login you already have. Nothing else depends on any of them — turn one off and the rest carries on.',
    services: [
      {
        slug: 'immich',
        name: 'Immich',
        blurb: 'Photo library',
        what: 'Your phone’s camera roll, backed up to your own disks, with the parts you actually miss from the cloud: face grouping, map view, search by what’s in the picture. The mobile app uploads in the background exactly the way the paid ones do.',
        shot: '/img/services/immich.webp',
        docs: '/docs/services/immich',
        source: 'https://github.com/immich-app/immich',
      },
      {
        slug: 'mealie',
        name: 'Mealie',
        blurb: 'Recipe management',
        what: 'Paste a recipe URL and it strips out the life story, keeping the ingredients and steps. From there it does meal plans and a shopping list that adds up quantities across everything you picked for the week.',
        shot: '/img/services/mealie.webp',
        docs: '/docs/services/mealie',
        source: 'https://github.com/mealie-recipes/mealie',
      },
      {
        slug: 'actual-budget',
        name: 'Actual Budget',
        blurb: 'Personal finance',
        what: 'Envelope budgeting that is fast and genuinely pleasant to use — every dollar gets a job, and the month either balances or it doesn’t. Transactions can arrive automatically, so the only thing left to do is categorize.',
        shot: '/img/services/actual-budget.webp',
        docs: '/docs/services/actual-budget',
        source: 'https://github.com/actualbudget/actual',
      },
      {
        slug: 'nocodb',
        name: 'NocoDB',
        blurb: 'Airtable-style database UI',
        what: 'A spreadsheet front-end over a real database — grid, kanban, gallery, and form views over the same rows. This is where the odd personal tracker lives when a note is too loose and an app would be too much.',
        shot: '/img/services/nocodb.webp',
        docs: '/docs/services/nocodb',
        source: 'https://github.com/nocodb/nocodb',
      },
      {
        slug: 'collabora',
        name: 'Collabora',
        blurb: 'Documents edited in the browser',
        what: 'LibreOffice running as a server, wired into Nextcloud so a document opens and edits in the browser tab you already had open. Nothing is uploaded anywhere to make that work — the file never leaves your disks.',
        shot: '/img/services/collabora.webp',
        docs: '/docs/storage/collabora',
        source: 'https://github.com/CollaboraOnline/online',
      },
      {
        slug: 'it-tools',
        name: 'IT Tools',
        blurb: 'Developer utility toolkit',
        what: 'The whole drawer of random web utilities in one place — base64, JWT decode, hashes, cron parsing, UUIDs, colour conversion. Specifically the ones you would otherwise paste company data into a sketchy ad-covered site to get.',
        shot: '/img/services/it-tools.webp',
        docs: '/docs/services/it-tools',
        source: 'https://github.com/CorentinTh/it-tools',
      },
      {
        slug: 'appsmith',
        name: 'Appsmith',
        blurb: 'Internal-tools platform',
        what: 'Drag a table, a form and a chart onto a page, wire them to a query, and you have the little admin app you were going to avoid writing. Good for the one-off interface that only three people will ever use.',
        docs: '/docs/services/appsmith',
        source: 'https://github.com/appsmithorg/appsmith',
      },
      {
        slug: 'lowcoder',
        name: 'Lowcoder',
        blurb: 'Low-code app builder',
        what: 'A second take on the same idea as Appsmith, with a different editor and a more generous free tier of features. Worth having when you want a real app UI over your data without starting a frontend project.',
        shot: '/img/services/lowcoder.webp',
        docs: '/docs/services/lowcoder',
        source: 'https://github.com/lowcoder-org/lowcoder',
      },
    ],
  },
];
