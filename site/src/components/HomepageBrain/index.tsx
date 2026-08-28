import type { ReactNode } from 'react';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type Node = {
  title: string;
  blurb: string;
  icon: ReactNode;
};

const icon = (path: string) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className={styles.surfaceIcon}>
    <path strokeLinecap="round" strokeLinejoin="round" d={path} />
  </svg>
);

/** What goes in. This half is what makes it a second brain rather than a chat window. */
const Feeds: Node[] = [
  {
    title: 'Your notes and files',
    blurb:
      'Obsidian writes plain Markdown into the vault; Nextcloud syncs the lot. Everything you keep is already material the agent can read — no upload step, no integration to wire up.',
    icon: icon('M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z'),
  },
  {
    title: 'Your house',
    blurb:
      'Home Assistant knows what the sensors, lights, doors and energy meters are doing. That state is something the agent can read — and act on.',
    icon: icon('M2.25 12l8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75'),
  },
];

/** What comes out. */
const Surfaces: Node[] = [
  {
    title: 'Talk to it',
    blurb:
      'Ask for something on your phone, or anywhere in the house. It hears you, answers in its own voice, and can actually go do the thing.',
    icon: icon('M12 18.75a6 6 0 006-6v-1.5m-6 7.5a6 6 0 01-6-6v-1.5m6 7.5v3.75m-3.75 0h7.5M12 15.75a3 3 0 01-3-3V4.5a3 3 0 116 0v8.25a3 3 0 01-3 3z'),
  },
  {
    title: 'Code with it',
    blurb:
      'The same assistant in your editor and your terminal — with your repos, your notes and your machine already in reach.',
    icon: icon('M17.25 6.75L22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3l-4.5 16.5'),
  },
  {
    title: 'Automate it',
    blurb:
      'Routines fire on a schedule, a webhook, or a file landing while you sleep — filing, transcribing, reconciling, and only telling you when it matters.',
    icon: icon('M21.752 15.002A9.718 9.718 0 0118 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 003 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 009.002-5.998z'),
  },
];

function Card({ node }: { node: Node }) {
  return (
    <div className={styles.surface}>
      <div className={styles.surfaceIconWrap}>{node.icon}</div>
      <Heading as="h3" className={styles.surfaceTitle}>
        {node.title}
      </Heading>
      <p className={styles.surfaceBlurb}>{node.blurb}</p>
    </div>
  );
}

export default function HomepageBrain(): ReactNode {
  return (
    <section className={styles.brain}>
      <div className="container">
        <div className={styles.intro}>
          <Heading as="h2" className={styles.title}>
            Everything feeds one brain
          </Heading>
          <p className={styles.lede}>
            Your files and your house go in one side. Conversation, coding and
            automation come out the other. Usually those are three separate
            products, three subscriptions and three places your data goes — here
            they are three doors into the same thing, and it already has your
            material.
          </p>
        </div>

        <div className={styles.feeds}>
          {Feeds.map((n) => (
            <Card key={n.title} node={n} />
          ))}
        </div>

        <div className={styles.convergeFeeds} aria-hidden="true">
          <span className={styles.convergeLine} />
          <span className={styles.convergeLine} />
        </div>

        <div className={styles.core}>
          <span className={styles.coreLabel}>Hermes · one local endpoint</span>
          <p className={styles.coreBlurb}>
            One API that every surface speaks to, with your files and your house
            already in reach. Change what sits behind it — a bigger model, a
            different voice, a new skill — and all three surfaces change at once.
          </p>
        </div>

        <div className={styles.diverge} aria-hidden="true">
          <span className={styles.divergeLine} />
          <span className={styles.divergeLine} />
          <span className={styles.divergeLine} />
        </div>

        <div className={styles.surfaces}>
          {Surfaces.map((n) => (
            <Card key={n.title} node={n} />
          ))}
        </div>

        <div className={styles.metal} aria-hidden="true">
          <span className={styles.metalLine} />
        </div>
        <div className={styles.hardware}>Your hardware</div>

        <p className={styles.more}>
          <Link to="/tour">See what all of it looks like →</Link>
        </p>
      </div>
    </section>
  );
}
