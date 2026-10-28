/**
 * The tour: things you can set up once and stop thinking about. What /tour lists.
 *
 * FLOWS, NOT SERVICES. Each entry is something a person does with the stack, told as a
 * scene, with the services it runs on named after it, small. A service with no flow
 * behind it has no place here.
 *
 * CORE FIRST. `tier: 'core'` runs on what `.env.exist.shared` ships on (code-server,
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
  /** What it does, to one person, as "you". One to three plain sentences. */
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
      "At seven your phone shows what's waiting on you, the next thing to do, and where each " +
      'conversation with Claude left off. Plus one encyclopedia article on a subject you keep ' +
      'coming back to, never one it already sent.',
    runsOn: ['Decree', 'ntfy', 'code-server'],
    needsModel: true,
    docs: '/docs/getting-started#you-were-here',
  },
  {
    tier: 'core',
    title: 'Write "next time…", and it offers to do it',
    story:
      'You write "next time I write up a meeting, pull out who owes what and draft the ' +
      'follow-up." A minute later your phone offers to automate it, with the steps listed. ' +
      'Move the file to accept, and every meeting note after that gets its follow-up drafted.',
    runsOn: ['Decree', 'ntfy', 'code-server'],
    needsModel: true,
    docs: '/docs/flows/note-to-automation',
  },
  {
    tier: 'core',
    title: 'A newsletter from only the feeds you picked',
    story:
      'Every Monday: at most seven items from the blogs, channels and forums you listed, each ' +
      'with one line on why it matters to you. It picks using a paragraph you wrote about what ' +
      'you care about.',
    runsOn: ['Decree', 'ntfy'],
    needsModel: true,
    docs: '/docs/flows/newsletter',
  },
  {
    tier: 'core',
    title: 'What did I even do this year?',
    story:
      'A summary of the week every Sunday and of the month at month-end, saved next to your ' +
      'notes. Ask for the year and get what shipped, what you kept coming back to and what you ' +
      'decided, each linked to the day it happened.',
    runsOn: ['Decree', 'ntfy'],
    needsModel: true,
    docs: '/docs/getting-started#look-back',
  },
  {
    tier: 'core',
    title: 'The note you meant to come back to',
    story:
      'Each new note is checked for something worth doing. If there is, you get a draft of the ' +
      'parts that can be done without you, and the questions only you can answer.',
    runsOn: ['Decree', 'ntfy'],
    needsModel: true,
    docs: '/docs/flows/note-to-action',
  },
  {
    tier: 'core',
    title: 'Drop a file in a folder, and the next step happens',
    story:
      'Save a file where a routine is watching and it runs. Tell Claude in code-server ' +
      '"when an invoice lands in invoices/, file it and tell me", and it writes the routine.',
    runsOn: ['Decree', 'code-server'],
    docs: '/docs/decree/file-handlers',
  },
  {
    tier: 'core',
    title: 'When something breaks, your phone says so',
    story:
      'A routine that fails or needs an answer sends one notification: what happened, and the ' +
      'command that continues it.',
    runsOn: ['Decree', 'ntfy'],
    docs: '/docs/decree#when-a-run-needs-you',
  },
  {
    tier: 'addon',
    title: 'Every business idea, researched before you fall for it',
    story:
      'Write once: "next time I have a business idea, look up competitors and do a market ' +
      'analysis." After that, each idea you write down is researched on the web, and your phone ' +
      'gets the verdict: favorable, unfavorable, or already done and by whom. Every figure links ' +
      'to its source.',
    runsOn: ['Firecrawl', 'Decree', 'ntfy'],
    needsModel: true,
    docs: '/docs/flows/note-to-automation#research-on-the-web-with-firecrawl',
  },
  {
    tier: 'addon',
    title: 'Ask Claude what you decided',
    story:
      '"What did I decide about syncing my notes?" Claude searches your notes, PDFs and Word ' +
      'files, by meaning and by exact words, and answers with the file and line.',
    runsOn: ['Search (qmd)', 'code-server'],
    docs: '/docs/ai/qmd',
  },
  {
    tier: 'addon',
    title: 'Bank alerts become budget entries',
    story:
      'Each charge alert your bank emails becomes a budget transaction, payee and amount ' +
      'filled in, a few minutes after you pay.',
    runsOn: ['Gmail', 'Actual Budget', 'Decree'],
    docs: '/docs/flows/transaction-gmail-actual-budget',
  },
  {
    tier: 'addon',
    title: 'Photograph it, and the text is yours',
    story:
      'Photograph a receipt, a whiteboard or a page. It syncs from your phone, and its text is ' +
      'saved next to the image a few seconds later, where search can find it.',
    runsOn: ['Nextcloud', 'a vision model', 'Decree'],
    needsModel: true,
    docs: '/docs/flows/image-ocr',
  },
  {
    tier: 'addon',
    title: 'Voice memos you actually read',
    story:
      'Record a voice memo. A transcript, with each speaker labelled, is saved beside it.',
    runsOn: ['Nextcloud', 'WhisperX', 'Decree'],
    docs: '/docs/flows/recording-transcription',
  },
  {
    tier: 'addon',
    title: 'Notes that find their own connections',
    story:
      'Each new note is checked against everything you already wrote, and you are told when ' +
      'it connects to an earlier one.',
    runsOn: ['Hermes', 'OpenViking', 'Decree'],
    needsModel: true,
    docs: '/docs/flows/note-connect',
  },
  {
    tier: 'addon',
    title: 'Say it out loud at home',
    story:
      'A wake word on your phone starts a recording or runs a home automation through your ' +
      'own Home Assistant. No cloud assistant.',
    runsOn: ['Home Assistant', 'HAwake'],
    docs: '/docs/flows/hawake-homeassistant',
  },
];
