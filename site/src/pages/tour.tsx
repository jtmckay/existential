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
 * to a pod: some of them run more than one container (automation is two,
 * prometheus is three), and `./existential.sh quest` turns each on or off as one
 * thing.
 *
 * NOT the number of cards below, which is what this number used to be — the page
 * said "N apps make up the core" while N counted screenshots. Part of Core has no
 * screen to show (the automation engine), so the card count undersold it.
 *
 * Hardcoded on purpose: this module is bundled for the browser, so it cannot read
 * the quest file at runtime, and a codegen step for one integer is worse than a
 * test. `./existential.sh validate conventions` fails if the two disagree.
 */
const CORE_SERVICES = 3;

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
const EXTRA = count((s) => s.tier === 'extra');

function TourHeader(): ReactNode {
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          What's inside
        </Heading>
        <p className={styles.heroLede}>
          <strong>{CORE_SERVICES} services make up Core</strong>, on hardware you own, every one
          of them free and open source, plus {EXTRA} more you can turn on whenever you want them.
          The {CORE_CARDS} below are the ones you'll open; the other runs underneath: the
          automation engine.
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
          Start small. Add when you need it.
        </Heading>
        <p className={styles.closingLede}>
          Each app is a flag. Turn one on and it comes up wired into the rest; leave it off and it
          never touches your disk. Change your mind next month: nothing you set up is lost.
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
      description="A look at every app in Existential: what it looks like and what it's for.">
      <TourHeader />
      <main>
        <ServiceTour />
        <TourClosing />
      </main>
    </Layout>
  );
}
