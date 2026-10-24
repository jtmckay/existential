import type { ReactNode } from 'react';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

export default function HomepageWhy(): ReactNode {
  return (
    <>
      <section className={styles.why}>
        <div className="container">
          <Heading as="h2" className={styles.title}>
            Intentional attention
          </Heading>
          <p className={styles.lede}>
            Every system you've tried needed you to remember to use it. That's the first thing a bad
            day takes.
          </p>
          <p className={styles.lede}>
            Everything else on your phone surfaces what someone else decided needs your attention.
            This surfaces what you decided.
          </p>
          <p className={styles.lede}>
            What you're building is your Diagram: the plan from your best day, followed on the rest.
          </p>
        </div>
      </section>
    </>
  );
}
