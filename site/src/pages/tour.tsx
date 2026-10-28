import type { ReactNode } from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import { FLOWS, type TourFlow } from '@site/src/data/tourFlows';

import styles from './tour.module.css';

function FlowCard({ flow }: { flow: TourFlow }): ReactNode {
  return (
    <article className={styles.card}>
      <Heading as="h3" className={styles.cardTitle}>
        {flow.title}
      </Heading>
      <p className={styles.cardStory}>{flow.story}</p>
      <p className={styles.cardRuns}>
        Runs on {flow.runsOn.join(', ')}
        {flow.needsModel && <>, plus a chat model, local or on another machine</>}.{' '}
        <Link to={flow.docs}>How it works</Link>
      </p>
    </article>
  );
}

function FlowSection({ tier, title, lede }: { tier: TourFlow['tier']; title: string; lede: string }): ReactNode {
  return (
    <section className={styles.section}>
      <div className="container">
        <Heading as="h2" className={styles.sectionTitle}>
          {title}
        </Heading>
        <p className={styles.sectionLede}>{lede}</p>
        <div className={styles.grid}>
          {FLOWS.filter((f) => f.tier === tier).map((f) => (
            <FlowCard key={f.title} flow={f} />
          ))}
        </div>
      </div>
    </section>
  );
}

export default function Tour(): ReactNode {
  return (
    <Layout
      title="Tour"
      description="What you can set up once and stop thinking about: a morning digest, your own newsletter, a look back at the year, and more.">
      <header className={clsx('hero hero--primary', styles.heroBanner)}>
        <div className="container">
          <Heading as="h1" className="hero__title">
            What you can do with it
          </Heading>
          <p className={styles.heroLede}>
            Set each one up once. It runs on its own after that.
          </p>
        </div>
      </header>
      <main>
        <FlowSection
          tier="core"
          title="With Core"
          lede="An editor with Claude in it, the automation engine, and notifications on your phone."
        />
        <FlowSection
          tier="addon"
          title="With one add-on each"
          lede="Each needs one more service turned on."
        />
        <section className={styles.closing}>
          <div className="container">
            <Heading as="h2" className={styles.closingTitle}>
              Each one is a routine you can read.
            </Heading>
            <p className={styles.closingLede}>
              A few lines of YAML and a script in your workspace. Edit one, or tell Claude what
              you want and it writes a new one.
            </p>
            <div className={styles.buttons}>
              <Link className="button button--primary button--lg" to="/docs/getting-started">
                Getting Started
              </Link>
              <Link
                className="button button--outline button--primary button--lg"
                href="https://discord.gg/McH3kPh9gM">
                Discord
              </Link>
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}
