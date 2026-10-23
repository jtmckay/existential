import type { ReactNode } from 'react';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type Capability = {
  label: string;
  text: string;
};

const Capabilities: Capability[] = [
  { label: 'Remembers', text: "What you were in the middle of is in this morning's notification, word for word." },
  { label: 'Keeps promises', text: "The thing you swore you'd check every Friday gets checked every Friday." },
  { label: 'Captures', text: 'Every prompt you give an agent lands in one stream, searchable a year from now.' },
  { label: 'Looks back', text: '"What did I even do this year?" has an answer.' },
  { label: 'Holds the line', text: "A bad week doesn't undo a good one." },
  { label: 'Grows', text: 'Tell an AI in your work dir what you want automated; it writes the machine.' },
];

function CapabilityCard({ label, text }: Capability) {
  return (
    <div className={styles.card}>
      <span className={styles.cardLabel}>{label}</span>
      <p className={styles.cardText}>{text}</p>
    </div>
  );
}

export default function HomepageCapabilities(): ReactNode {
  return (
    <section className={styles.capabilities}>
      <div className="container">
        <div className={styles.intro}>
          <Heading as="h2" className={styles.title}>
            What the Diagram does on a bad day
          </Heading>
          <p className={styles.lede}>The days you'd have dropped it.</p>
        </div>
        <div className={styles.grid}>
          {Capabilities.map((item) => (
            <CapabilityCard key={item.label} {...item} />
          ))}
        </div>
      </div>
    </section>
  );
}
