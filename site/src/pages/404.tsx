import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';

import styles from './index.module.css';

export default function NotFound(): ReactNode {
  return (
    <Layout title="Page Not Found">
      <header className={clsx('hero hero--primary', styles.heroBanner)}>
        <div className="container">
          <img
            src="/img/favicon.svg"
            alt="Existential Logo"
            className={styles.heroLogo}
          />
          <Heading as="h1" className="hero__title">
            404
          </Heading>
          <p className="hero__subtitle">
            This page doesn't exist — but your homelab does.
          </p>
          <div className={styles.buttons}>
            <Link className="button button--secondary button--lg" to="/">
              Go Home
            </Link>
          </div>
        </div>
      </header>
    </Layout>
  );
}
