import type { ReactNode } from 'react';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

const Traits: string[] = [
  "You've had the same good idea three times and lost it twice.",
  "Your best plans don't survive your first bad week.",
  "You want your phone to interrupt you for your reasons, not someone else's.",
  "You'd rather write a rule once than remember it forever.",
  "You'd rather own a box in the closet than rent your own life back monthly.",
  'You want to answer "what did I even do this year?" with something better than a guess.',
];

export default function HomepageWho(): ReactNode {
  return (
    <section className={styles.who}>
      <div className="container">
        <div className={styles.intro}>
          <Heading as="h2" className={styles.title}>
            Who this is for
          </Heading>
          <p className={styles.lede}>If three of these sting, it's for you.</p>
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
