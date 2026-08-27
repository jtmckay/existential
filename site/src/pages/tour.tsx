import type { ReactNode } from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import ServiceTour from '@site/src/components/ServiceTour';
import { TOUR } from '@site/src/data/tourServices';

import styles from './tour.module.css';

/** Counts apps, so summary cards like `mobile` don't inflate the tally. */
const count = (kind: 'hosted' | 'recommended') =>
  TOUR.filter((s) => s.kind === kind).reduce(
    (n, s) => n + s.services.filter((service) => !service.summary).length,
    0,
  );

const HOSTED = count('hosted');
const RECOMMENDED = count('recommended');

function TourHeader(): ReactNode {
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          What you actually get
        </Heading>
        <p className={styles.heroLede}>
          {HOSTED} apps Existential hosts on hardware you own, every one of them free and
          open source — plus {RECOMMENDED} more we would recommend installing yourself.
          Scroll through and see what they look like.
        </p>
      </div>
    </header>
  );
}

function TourClosing(): ReactNode {
  return (
    <section className={styles.closing}>
      <div className="container">
        <Heading as="h2" className={styles.closingTitle}>
          Pick the ones you want.
        </Heading>
        <p className={styles.closingLede}>
          Nothing here is all-or-nothing — each app is a flag you flip. The ones you enable come
          up wired together; the ones you don't never touch your disk.
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
        <p className={styles.closingNotice}>
          Every screenshot above is of the upstream project's own interface.{' '}
          <Link to="/docs/open-source-notices">Open source notices</Link>.
        </p>
      </div>
    </section>
  );
}

export default function Tour(): ReactNode {
  return (
    <Layout
      title="Tour"
      description="A scrolling look at every app in the Existential stack — what it looks like and what it's for.">
      <TourHeader />
      <main>
        <ServiceTour />
        <TourClosing />
      </main>
    </Layout>
  );
}
