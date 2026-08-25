import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type Level = {
  number: string;
  name: string;
  question: string;
  blurb: string;
  to: string;
};

const Levels: Level[] = [
  {
    number: '1',
    name: 'Context',
    question: 'What is this, and what does it do for me?',
    blurb:
      'The system as one box: you, your data, your house, and the few things outside it that Existential talks to.',
    to: '/docs/intro',
  },
  {
    number: '2',
    name: 'Pieces',
    question: "What's actually running?",
    blurb:
      'The moving parts and how they fit — a flag per service, one compose file, one network, and the AI spine behind every surface.',
    to: '/docs/how-it-works',
  },
  {
    number: '3',
    name: 'Flows',
    question: 'How does one job get done, start to finish?',
    blurb:
      'A recording becomes a transcript. A receipt becomes a budget entry. Each flow traced through the services it touches.',
    to: '/docs/flows/',
  },
  {
    number: '4',
    name: 'Build on it',
    question: 'How do I extend it?',
    blurb:
      'The small, frozen contract: how work gets in, what a message looks like, where the data sits, how to read the result.',
    to: '/docs/build-on-it',
  },
];

export default function HomepageLevels(): ReactNode {
  return (
    <section className={styles.levels}>
      <div className="container">
        <div className={styles.intro}>
          <Heading as="h2" className={styles.title}>
            Understand it at whatever level you need
          </Heading>
          <p className={styles.lede}>
            The docs are layered the way a{' '}
            <a href="https://c4model.com/" target="_blank" rel="noreferrer">
              C4 diagram
            </a>{' '}
            is: each level zooms in one step, and you can stop at any of them.
            Most people never go past the second.
          </p>
        </div>

        <div className={styles.grid}>
          {Levels.map((level) => (
            <Link key={level.number} to={level.to} className={styles.card}>
              <div className={styles.cardHead}>
                <span className={styles.badge}>Level {level.number}</span>
                <Heading as="h3" className={styles.cardTitle}>
                  {level.name}
                </Heading>
              </div>
              <p className={styles.question}>{level.question}</p>
              <p className={styles.blurb}>{level.blurb}</p>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}
