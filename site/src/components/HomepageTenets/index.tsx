import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type Tenet = {
  name: string;
  description: string;
};

type TenetGroup = {
  title: string;
  tenets: Tenet[];
};

const TenetGroups: TenetGroup[] = [
  {
    title: "It's yours",
    tenets: [
      {
        name: 'Privacy first',
        description:
          'We never see or sell your data — baked in, not an afterthought policy.',
      },
      {
        name: "It's yours",
        description:
          'Your stuff lives on your own space, locked with a key only you hold. We can’t open it, even if we wanted to.',
      },
      {
        name: 'Leave anytime',
        description:
          'One button hands you a full copy and you’re gone. Nothing keeps you here but wanting to stay.',
      },
      {
        name: 'Open for all to see',
        description:
          'The code is out in the open. Anyone can check it, run it themselves, or keep it.',
      },
    ],
  },
  {
    title: 'It actually helps',
    tenets: [
      {
        name: 'All in one place',
        description:
          'Everything finally together instead of scattered across a dozen apps that don’t talk.',
      },
      {
        name: 'Your own helper',
        description:
          'A smart assistant that knows your whole life and works only for you. It tells no one anything.',
      },
      {
        name: 'Works the way you want',
        description:
          'Tell it what you want and it does it, instead of waiting for someone to build an app for it.',
      },
    ],
  },
  {
    title: "It's on your side",
    tenets: [
      {
        name: 'No ads, ever',
        description:
          'Nobody pays us to grab your attention. You’re the customer, not the product.',
      },
      {
        name: 'Less screen, more life',
        description:
          'Built to quietly handle things so you spend less time on your devices, not more.',
      },
    ],
  },
];

function Group({title, tenets}: TenetGroup) {
  return (
    <div className={clsx('col col--4')}>
      <Heading as="h3" className={styles.groupTitle}>
        {title}
      </Heading>
      <ul className={styles.tenetList}>
        {tenets.map((tenet, idx) => (
          <li key={idx} className={styles.tenet}>
            <span className={styles.tenetName}>{tenet.name}</span>
            <span className={styles.tenetDescription}>{tenet.description}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

export default function HomepageTenets(): ReactNode {
  return (
    <section className={styles.tenets}>
      <div className="container">
        <div className={styles.intro}>
          <Heading as="h2">What we stand for</Heading>
          <p className={styles.lede}>
            Existential gives you back ownership of your digital life — one private
            intelligence over everything you have, that answers only to you.
          </p>
        </div>
        <div className="row">
          {TenetGroups.map((group, idx) => (
            <Group key={idx} {...group} />
          ))}
        </div>
        <div className={styles.cta}>
          <Link className="button button--primary button--lg" to="/manifesto">
            Read the manifesto
          </Link>
          <Link
            className="button button--outline button--primary button--lg"
            to="/declaration">
            The declaration
          </Link>
        </div>
      </div>
    </section>
  );
}
