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
          On a clear day you can see exactly what to do. Then the fog rolls in, and the idea sits
          in a note you won't open for three weeks. Existential keeps the clear day running. What
          you decide when you're sharp becomes an automation that comes to you on its own, on the
          days you'd never think to look.
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
          One evening of setup. Then it runs, and the tinkering is optional.
        </p>
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
      description="Your best brain day now carries your worst. What you decide when you're sharp becomes an automation that comes to you on its own, on the days you'd never think to look.">
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
