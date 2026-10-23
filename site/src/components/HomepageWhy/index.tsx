import type { ReactNode } from 'react';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

export default function HomepageWhy(): ReactNode {
  return (
    <section className={styles.why}>
      <div className="container">
        <Heading as="h2" className={styles.title}>
          Write your Diagram.
        </Heading>
        <p className={styles.lede}>
          In Brandon Sanderson's <em>Stormlight Archive</em>, Taravangian wakes every day with a
          different mind. Most days he's ordinary. Some days he can barely follow a conversation.
          One day he was a genius, and in that one day he wrote the Diagram. He has followed it
          ever since, on days he couldn't have written a line of it.
        </p>
        <p className={styles.lede}>
          That's what you're building here. Not a notes app, not a dashboard: a Diagram. What you
          decide on your best days is written down as a{' '}
          <Link to="/docs/decree">decree machine</Link>, and it runs on the days you've forgotten
          why.
        </p>
        <p className={styles.lede}>
          So the good days stop being spent catching up. Each one starts where the last one left
          you, and climbs.
        </p>

        <Heading as="h2" className={styles.title}>
          Nobody else decides what you look at.
        </Heading>
        <p className={styles.lede}>
          Every app on your phone is bidding for your next thirty seconds, and the winner is
          whoever profits most from them. Here, nothing reaches you unless you put it there: the
          reminder you set on a sharp day, the feeds you chose, this morning's{' '}
          <Link to="/docs/getting-started#you-were-here">"you were here"</Link> digest of what you
          were in the middle of. Everything you put in lands in one{' '}
          <Link to="/docs/getting-started#capture">capture</Link> stream; everything that comes
          back arrives through <Link to="/docs/services/ntfy">ntfy</Link>, when you said it should.
        </p>
        <p className={styles.lede}>Every interruption has an author. Here, it's you.</p>
      </div>
    </section>
  );
}
