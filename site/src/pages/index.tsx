import type { ReactNode } from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import HomepageBrain from '@site/src/components/HomepageBrain';
import HomepageLevels from '@site/src/components/HomepageLevels';

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
          There's an app for that, and it's free open source.
          Existential runs it all as <em>one</em> connected system on your own
          hardware — your files in Nextcloud, your house in Home Assistant, and
          a local agent in the middle that reads both.
        </p>
        <div className={styles.buttons}>
          <Link
            className="button button--secondary button--lg"
            to="/docs/intro">
            Get Started
          </Link>
          <Link
            className="button button--outline button--secondary button--lg"
            to="/tour">
            Take a tour
          </Link>
        </div>
      </div>
    </header>
  );
}

function HomepageClosing() {
  return (
    <section className={styles.closing}>
      <div className="container">
        <Heading as="h2" className={styles.closingTitle}>
          It's a homelab. You already have the hardware.
        </Heading>
        <p className={styles.closingLede}>
          One machine, Docker, and an evening. Pick what you want, and it comes
          up wired together.
        </p>
        <div className={styles.closingCode}>
          <pre>
            <code>
              {'git clone https://github.com/jtmckay/existential.git\n'}
              {'cd existential\n'}
              {'\n'}
              {'./existential.sh quest      # pick your services\n'}
              {'docker compose up -d\n'}
            </code>
          </pre>
        </div>
        <div className={styles.buttons}>
          <Link className="button button--primary button--lg" to="/docs/getting-started">
            Getting Started
          </Link>
          <Link
            className="button button--outline button--primary button--lg"
            to="/tour">
            Take a tour
          </Link>
        </div>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.title}
      description="A personal cloud you run yourself. Curated open source, set up once, with one local AI behind conversation, coding and automation.">
      <HomepageHeader />
      <main>
        <HomepageFeatures />
        <HomepageBrain />
        <HomepageLevels />
        <HomepageClosing />
      </main>
    </Layout>
  );
}
