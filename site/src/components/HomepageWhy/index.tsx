import type { ReactNode } from 'react';
import styles from './styles.module.css';

export default function HomepageWhy(): ReactNode {
  return (
    <>
      <section className={styles.why}>
        <div className="container">
          <p className={styles.lede}>
            Every system you've tried needed you to remember to use it. That's the one thing a bad
            day takes.
          </p>
          <p className={styles.lede}>
            Your good days stop going to catching up. Each one starts where the last one left off.
          </p>
          <p className={styles.lede}>
            Everything else on your phone surfaces what someone else decided needs your attention.
            This surfaces what you decided.
          </p>
          <p className={styles.lede}>
            What you're building is your Diagram: the plan your best day wrote, followed on every
            other one.
          </p>
        </div>
      </section>
      <section className={styles.why}>
        <div className="container">
          <p className={styles.lede}>
            When you outgrow how you set it up, and you will, rebuild it your way. Nothing you
            built is lost: it's all plain files, and it's where the next version starts.
          </p>
          <p className={styles.lede}>
            Existential makes no money from you: no ads, no attention to sell, nothing collected.
            Which AI you talk to is your choice, as private or as easy as you want. Your data
            improves you.
          </p>
        </div>
      </section>
    </>
  );
}
