import type { ReactNode } from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import HomepageCapabilities from '@site/src/components/HomepageCapabilities';
import HomepageHow from '@site/src/components/HomepageHow';
import HomepageWho from '@site/src/components/HomepageWho';
import HomepageWhy from '@site/src/components/HomepageWhy';
import HomepageFeatures from '@site/src/components/HomepageFeatures';

import styles from './index.module.css';

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <img
          src="/img/favicon.svg"
          alt="Existential Logo"
          className={styles.heroLogo}
        />
        <Heading as="h1" className="hero__title">
          {siteConfig.title}
        </Heading>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <p className={styles.heroLede}>
          Some mornings you wake up able to see the whole board. Most mornings you don't.
          Existential is where the sharp you leaves orders for every other you, and makes sure
          they're carried out.
        </p>
        <div className={styles.buttons}>
          <Link
            className="button button--outline button--secondary button--lg"
            to="/docs/intro">
            Overview
          </Link>
          <Link
            className="button button--outline button--secondary button--lg"
            to="/tour">
            Take a tour
          </Link>
          <Link
            className="button button--secondary button--lg"
            to="/docs/getting-started">
            Get Started
          </Link>
        </div>
      </div>
    </header>
  );
}

export function HomepageClosing() {
  return (
    <section className={styles.closing}>
      <div className="container">
        <Heading as="h2" className={styles.closingTitle}>
          Start your Diagram tonight.
        </Heading>
        <p className={styles.closingLede}>
          One evening, mostly spent waiting on Docker.
        </p>
        <div className={styles.closingCode}>
          <pre>
            <code>
              {'git clone https://github.com/jtmckay/existential.git\n'}
              {'cd existential\n'}
              {'\n'}
              {'./existential.sh     # say yes to Core, or pick your own\n'}
              {'docker compose up -d\n'}
            </code>
          </pre>
        </div>
        <div className={styles.buttons}>
          <Link
            className="button button--outline button--primary button--lg"
            to="/tour">
            Take a tour
          </Link>
          <Link className="button button--primary button--lg" to="/docs/getting-started">
            Getting Started
          </Link>
        </div>
        <p className={styles.closingFaq}>
          Skeptical? <Link to="/docs/faq">Read the FAQ</Link>.
        </p>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.title}
      description="Taking your best brain day, and preserving it for your worst. Your sharpest decisions, written down as automations that run on every other day, on hardware you own. Nothing gets your attention unless you put it there.">
      <HomepageHeader />
      <main>
        <HomepageWhy />
        <HomepageWho />
        <HomepageHow />
        <HomepageCapabilities />
        <HomepageFeatures />
        <HomepageClosing />
      </main>
    </Layout>
  );
}
