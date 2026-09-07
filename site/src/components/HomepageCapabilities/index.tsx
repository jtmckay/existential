import type { ReactNode } from 'react';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type Capability = {
  label: string;
  text: string;
};

const Capabilities: Capability[] = [
  { label: 'Working memory', text: 'Capture ideas effortlessly, so you can live in the moment.' },
  { label: 'Remembering', text: 'The right note finds you, unasked, when it matters.' },
  { label: 'Prioritization', text: 'Know what you are doing is the right thing to do.' },
  { label: 'Plan', text: 'Breakdown tasks in the background, and see the next real step surfaced.' },
  { label: 'Organization', text: 'Notes, photos, files — filed the moment they land.' },
  { label: 'Systematize', text: 'Build systems that work for you.' },
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
            What gets easier
          </Heading>
          <p className={styles.lede}>Concretely, immediately.</p>
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
