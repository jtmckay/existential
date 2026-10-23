import type { ReactNode } from 'react';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

export default function HomepageWhy(): ReactNode {
  return (
    <section className={styles.why}>
      <div className="container">
        <Heading as="h2" className={styles.title}>
          A ratchet, not a churn loop.
        </Heading>
        <p className={styles.lede}>
          Without one: a good day, a bad day, a good day spent catching up. Repeat. With one, your
          best day sets the floor, and the next good day climbs from there.
        </p>
        <p className={styles.lede}>
          What you decide is recorded as a <Link to="/docs/decree">decree machine</Link> and keeps
          running whether you remember it or not.
        </p>

        <Heading as="h2" className={styles.title}>
          Your attention is yours.
        </Heading>
        <p className={styles.lede}>
          What reaches you is what you decided should, on your schedule. No algorithm picks it for
          someone else's profit.
        </p>
        <p className={styles.lede}>
          You put things in through one <Link to="/docs/getting-started#capture">capture</Link>{' '}
          stream; they come back as the{' '}
          <Link to="/docs/getting-started#you-were-here">"you were here"</Link> digest and{' '}
          <Link to="/docs/services/ntfy">ntfy</Link> notifications you asked for.
        </p>
      </div>
    </section>
  );
}
