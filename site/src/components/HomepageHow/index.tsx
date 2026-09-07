import type { ReactNode } from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  icon: ReactNode;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'Input',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className={styles.featureIcon}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 10.5v6.75a1.5 1.5 0 001.5 1.5h12a1.5 1.5 0 001.5-1.5V10.5m-16.5 0h1.245c.531 0 1.038.212 1.412.586l1.086 1.086c.374.374.88.586 1.412.586h3.14c.531 0 1.038-.212 1.412-.586l1.086-1.086c.374-.374.88-.586 1.412-.586H19.5m-16.5 0V6a1.5 1.5 0 011.5-1.5h13.5A1.5 1.5 0 0119.5 6v4.5m-6.75-6v6.75m0 0-3-3m3 3 3-3" />
      </svg>
    ),
    description: (
      <>
        Notes, photos, receipts, voice memos — captured the moment they happen, from whatever
        app is already open.
      </>
    ),
  },
  {
    title: 'Workspace',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className={styles.featureIcon}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M9 17.25v1.007a3 3 0 01-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0115 18.257v-1.007m6-12V15a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 15V5.25m18 0A2.25 2.25 0 0018.75 3H5.25A2.25 2.25 0 003 5.25m18 0V12a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 12V5.25" />
      </svg>
    ),
    description: (
      <>
        One shared space where your notes, files, and tools live side by side, synced to
        everywhere you work.
      </>
    ),
  },
  {
    title: 'Automation',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className={styles.featureIcon}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 13.5l10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75z" />
      </svg>
    ),
    description: (
      <>
        Rules that watch the workspace and act on it — filing, tagging, reminding — so nothing
        needs revisiting by hand.
      </>
    ),
  },
];

function Feature({ title, icon, description }: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <div className={styles.featureIconWrapper}>{icon}</div>
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageHow(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className={styles.intro}>
          <Heading as="h2" className={styles.title}>
            How it works
          </Heading>
          <p className={styles.lede}>
            Less screen time, more headspace.
          </p>
        </div>
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
