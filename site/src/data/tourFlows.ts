/**
 * The tour: things you can set up once and stop thinking about. What /tour lists.
 *
 * FLOWS, NOT SERVICES. Each entry is something a person does with the stack, told as a
 * scene, with the services it runs on named after it, small. A service with no flow
 * behind it has no place here.
 *
 * CORE FIRST. `tier: 'core'` runs on what `src/quests/00-core.md` installs (code-server,
 * decree, ntfy), plus a chat model wherever `needsModel` says so: a model is not part of
 * Core, so a flow that uses one says it. Everything else is `tier: 'addon'` and names
 * the add-on it needs.
 *
 * Every story must be true of the repo as it is: a flow described here has a machine
 * that does it, and `docs` is the page that shows how. The site sets
 * `onBrokenLinks: 'throw'`, so a wrong `docs` path fails the build.
 */

export type TourFlow = {
  title: string;
  /** The scene, to one person, as "you". Two to four sentences. */
  story: string;
  /** What it runs on, as names the reader will see in the docs. */
  runsOn: string[];
  /** Uses a chat model for part of it (Core does not install one). */
  needsModel?: boolean;
  /** The docs page that shows how; must resolve. */
  docs: string;
  tier: 'core' | 'addon';
};

export const FLOWS: TourFlow[] = [
  {
    tier: 'core',
    title: 'Where you were, every morning',
    story:
      "At seven your phone shows yesterday, not a feed: what's waiting on you, the one next " +
      'thing, and where each conversation with Claude left off, in your own words. Then one ' +
      "encyclopedia article on the subject you've been circling, so you can learn it properly " +
      "instead of in fragments, never one it suggested before or one you saved to a note. Then it ends.",
    runsOn: ['Decree', 'ntfy', 'code-server'],
    needsModel: true,
    docs: '/docs/getting-started#you-were-here',
  },
  {
    tier: 'core',
    title: 'Write "next time…", and it offers to do it',
    story:
      'You jot down "next time I have a business idea, research who already does it and draft ' +
      'a one-page plan." A minute later your phone offers to automate exactly that, with the ' +
      'steps spelled out. Move the file to accept it, and the next idea you write down gets ' +
      'researched and planned on its own, the results waiting in a note you can dig into with Claude.',
    runsOn: ['Decree', 'ntfy', 'code-server'],
    needsModel: true,
    docs: '/docs/flows/note-to-automation',
  },
  {
    tier: 'core',
    title: 'A newsletter from only the feeds you picked',
    story:
      'Every Monday you get one issue: at most seven items from the blogs, channels and forums ' +
      'you listed, each in one line saying why it matters to you. It picks by a paragraph you ' +
      'wrote in plain words, not by what keeps you scrolling. A week with nothing worth your ' +
      'time says so in one line.',
    runsOn: ['Decree', 'ntfy'],
    needsModel: true,
    docs: '/docs/flows/newsletter',
  },
  {
    tier: 'core',
    title: 'What did I even do this year?',
    story:
      'Every Sunday a look back at the week lands next to your notes, and every month-end one ' +
      'for the month. When a review comes round, ask for the year: what shipped, what you kept ' +
      'coming back to, what you decided, each linked to the day it happened. Filter it to work ' +
      'with one word.',
    runsOn: ['Decree', 'ntfy'],
    needsModel: true,
    docs: '/docs/getting-started#look-back',
  },
  {
    tier: 'core',
    title: 'The note you meant to come back to',
    story:
      'You write a note and move on. Something reads each new one and asks a single question: ' +
      'is there something here worth doing? If there is, you get a draft of what can be done ' +
      'without you, ending with the questions only you can answer.',
    runsOn: ['Decree', 'ntfy'],
    needsModel: true,
    docs: '/docs/flows/note-to-action',
  },
  {
    tier: 'core',
    title: 'Drop a file in a folder, and the next step happens',
    story:
      'Save a note into to-process/, or drop a PDF anywhere, and the routine you set for it ' +
      'runs once you stop saving. You don\'t write the routine: tell Claude in code-server ' +
      '"when an invoice lands in invoices/, file it and tell me", and it writes one.',
    runsOn: ['Decree', 'code-server'],
    docs: '/docs/decree/file-handlers',
  },
  {
    tier: 'core',
    title: 'When something breaks, your phone says so',
    story:
      'A routine that fails, or stops to ask you something, sends one notification with what ' +
      "happened and the exact command that continues it. Nothing fails quietly, and nothing " +
      'nags twice.',
    runsOn: ['Decree', 'ntfy'],
    docs: '/docs/decree#when-a-run-needs-you',
  },
  {
    tier: 'addon',
    title: 'Ask Claude what you decided',
    story:
      '"What did I decide about syncing my notes?" Claude searches everything you\'ve written, ' +
      'and the PDFs and Word files you keep, by meaning and by exact words, and answers with ' +
      'the file and line. A note you saved a minute ago is already in it.',
    runsOn: ['Search (qmd)', 'code-server'],
    docs: '/docs/ai/qmd',
  },
  {
    tier: 'addon',
    title: 'Bank alerts become budget entries',
    story:
      'The alert email your bank sends for every charge becomes a transaction in your budget, ' +
      'with the payee and amount filled in, a few minutes after you tap your card.',
    runsOn: ['Gmail', 'Actual Budget', 'Decree'],
    docs: '/docs/flows/transaction-gmail-actual-budget',
  },
  {
    tier: 'addon',
    title: 'Photograph it, and the text is yours',
    story:
      'A receipt, a whiteboard, a page of a book: the photo syncs from your phone, and the text ' +
      'in it lands next to the image a few seconds later, where search and your notes can find it.',
    runsOn: ['Nextcloud', 'a vision model', 'Decree'],
    needsModel: true,
    docs: '/docs/flows/image-ocr',
  },
  {
    tier: 'addon',
    title: 'Voice memos you actually read',
    story:
      'Record a thought on a walk. By the time you are home there is a transcript beside it, ' +
      'each speaker labelled, instead of another recording you will never play back.',
    runsOn: ['Nextcloud', 'WhisperX', 'Decree'],
    docs: '/docs/flows/recording-transcription',
  },
  {
    tier: 'addon',
    title: 'Notes that find their own connections',
    story:
      'Each new note is checked against everything you already wrote. When there is a real ' +
      'connection, not just a shared topic, it comes back to you before you would have found ' +
      'it yourself.',
    runsOn: ['Hermes', 'OpenViking', 'Decree'],
    needsModel: true,
    docs: '/docs/flows/note-connect',
  },
  {
    tier: 'addon',
    title: 'Say it out loud at home',
    story:
      'A wake word on your phone starts a recording or runs a home automation, through your ' +
      'own Home Assistant, with no cloud assistant listening.',
    runsOn: ['Home Assistant', 'HAwake'],
    docs: '/docs/flows/hawake-homeassistant',
  },
];
