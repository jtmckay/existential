import type { ReactNode } from 'react';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

const Traits: string[] = [
  "You have a lot of stuff to keep straight.",
  "You want a connected system.",
  "You love automating things.",
  "You hate subscriptions, and lock-in.",
  "You care about privacy.",
  "You want or already have a homelab.",
];

export default function HomepageWho(): ReactNode {
  return (
    <section className={styles.who}>
      <div className="container">
        <div className={styles.intro}>
          <Heading as="h2" className={styles.title}>
            Who this is for
          </Heading>
          <p className={styles.lede}>A type of person, not a technical requirement.</p>
        </div>

        <ul className={styles.list}>
          {Traits.map((trait) => (
            <li key={trait} className={styles.item}>
              {trait}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
