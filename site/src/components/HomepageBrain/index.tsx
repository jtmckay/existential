import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type Surface = {
  title: string;
  blurb: string;
  icon: ReactNode;
};

const Surfaces: Surface[] = [
  {
    title: 'Talk to it',
    blurb:
      'Ask for something out loud, anywhere in the house. It hears you, answers in its own voice, and can actually go do the thing.',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className={styles.surfaceIcon}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M12 18.75a6 6 0 006-6v-1.5m-6 7.5a6 6 0 01-6-6v-1.5m6 7.5v3.75m-3.75 0h7.5M12 15.75a3 3 0 01-3-3V4.5a3 3 0 116 0v8.25a3 3 0 01-3 3z" />
      </svg>
    ),
  },
  {
    title: 'Code with it',
    blurb:
      'The same assistant in your editor and your terminal — with your repos, your notes and your machine already in reach.',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className={styles.surfaceIcon}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M17.25 6.75L22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3l-4.5 16.5" />
      </svg>
    ),
  },
  {
    title: 'It works while you sleep',
    blurb:
      'Routines fire on a schedule, a webhook, or a file landing somewhere — filing, transcribing, reconciling, and only telling you when it matters.',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className={styles.surfaceIcon}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M21.752 15.002A9.718 9.718 0 0118 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 003 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 009.002-5.998z" />
      </svg>
    ),
  },
];

export default function HomepageBrain(): ReactNode {
  return (
    <section className={styles.brain}>
      <div className="container">
        <div className={styles.intro}>
          <Heading as="h2" className={styles.title}>
            One brain, every surface
          </Heading>
          <p className={styles.lede}>
            Conversation, coding and automation are usually three separate
            products, three subscriptions, and three places your data goes.
            Here they are three doors into the same thing.
          </p>
        </div>

        <div className={styles.surfaces}>
          {Surfaces.map((surface) => (
            <div key={surface.title} className={styles.surface}>
              <div className={styles.surfaceIconWrap}>{surface.icon}</div>
              <Heading as="h3" className={styles.surfaceTitle}>
                {surface.title}
              </Heading>
              <p className={styles.surfaceBlurb}>{surface.blurb}</p>
            </div>
          ))}
        </div>

        <div className={styles.converge} aria-hidden="true">
          <span className={styles.convergeLine} />
          <span className={styles.convergeLine} />
          <span className={styles.convergeLine} />
        </div>

        <div className={styles.core}>
          <span className={styles.coreLabel}>One local endpoint</span>
          <p className={styles.coreBlurb}>
            Every surface speaks to the same API, and the same models answer.
            Change what's behind it — a bigger model, a different voice, a new
            skill — and all three change at once. It never left the building to
            find out.
          </p>
        </div>

        <div className={styles.metal} aria-hidden="true">
          <span className={styles.metalLine} />
        </div>
        <div className={styles.hardware}>Your hardware</div>

        <p className={styles.more}>
          <Link to="/docs/how-it-works">
            See which pieces actually do this →
          </Link>
        </p>
      </div>
    </section>
  );
}
