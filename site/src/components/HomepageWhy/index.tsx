import type { ReactNode } from 'react';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

export default function HomepageWhy(): ReactNode {
  return (
    <section className={styles.why}>
      <div className="container">
        <Heading as="h2" className={styles.title}>
          Stop carrying it in your head.
        </Heading>
        <p className={styles.lede}>
          Write it down once. Forget it on purpose. It comes back to you, right when
          it matters.
        </p>
        <p className={styles.lede}>
          Less an assistant. More a digital you — one that never forgets, so you can be present
          instead of on guard.
        </p>
      </div>
    </section>
  );
}
