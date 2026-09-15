import type { ReactNode } from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import ServiceTour from '@site/src/components/ServiceTour';
import { TOUR, type TourSection } from '@site/src/data/tourServices';

import styles from './tour.module.css';

/**
 * How many services Core installs — one per service folder it enables, which is
 * one per `EXIST_IS_*` flag in `src/quests/00-core.md`'s `services:` block. That
 * is the stack's own unit of a service (a folder), and the closest thing it has
 * to a pod: several of them run more than one container (honcho is three,
 * firecrawl is six), and `./existential.sh quest` turns each on or off as one
 * thing.
 *
 * NOT the number of cards below, which is what this number used to be — the page
 * said "N apps make up the core" while N counted screenshots. Most of Core has no
 * screen to show (a cache, a log store, a metrics store, the model server, the
 * voice pipeline, the agent's memory), so the card count undersold it by half.
 *
 * Hardcoded on purpose: this module is bundled for the browser, so it cannot read
 * the quest file at runtime, and a codegen step for one integer is worse than a
 * test. `./existential.sh validate conventions` fails if the two disagree.
 */
const CORE_SERVICES = 19;

/**
 * Counts cards, so summary cards like `mobile` don't inflate the tally.
 *
 * Core and beyond-Core are counted separately and said separately in the lede:
 * one number covering both would be the same overclaim the divider exists to
 * stop — Core installs the first figure, not the sum.
 */
const count = (match: (s: TourSection) => boolean) =>
  TOUR.filter(match).reduce(
    (n, s) => n + s.services.filter((service) => !service.summary).length,
    0,
  );

const CORE_CARDS = count((s) => s.tier === 'core' && s.kind === 'hosted');
const CORE_CLIENTS = count((s) => s.tier === 'core' && s.kind === 'recommended');
const EXTRA = count((s) => s.tier === 'extra');

function TourHeader(): ReactNode {
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          What you actually get
        </Heading>
        <p className={styles.heroLede}>
          <strong>{CORE_SERVICES} services make up the core</strong> — on
          hardware you own, every one of them free and open source — plus {CORE_CLIENTS}{' '}
          clients you install on your own machines to reach them, and {EXTRA} optional
          services you can turn on. The {CORE_CARDS} below are the ones worth a screenshot;
          the rest are plumbing — a cache, a log store, a metrics store, the model server,
          the voice pipeline, the agent's memory. Scroll through and see what they look
          like.
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
