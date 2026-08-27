import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import clsx from 'clsx';
import { TOUR, type TourSection, type TourService } from '@site/src/data/tourServices';
import styles from './styles.module.css';

/** Peak parallax offset of the pinned screenshot, in px. Deliberately small. */
const DRIFT_PX = 12;

/**
 * The screenshot, or a labeled placeholder when we don't have one yet.
 * The tour has to look intentional at any level of image coverage.
 */
function Shot({
  service,
  active,
  eager,
}: {
  service: TourService;
  active: boolean;
  eager: boolean;
}): ReactNode {
  return (
    <div className={clsx(styles.shot, active && styles.shotActive)} aria-hidden={!active}>
      <div className={styles.chrome}>
        <span className={styles.dot} />
        <span className={styles.dot} />
        <span className={styles.dot} />
        <span className={styles.chromeUrl}>
          {service.chrome ?? (
            <>
              {service.slug}.<span className={styles.chromeDomain}>yourdomain.com</span>
            </>
          )}
        </span>
      </div>
      <div className={styles.shotBody}>
        {service.shot ? (
          <img
            className={styles.shotImg}
            src={service.shot}
            alt={`The ${service.name} interface`}
            width={1600}
            height={1000}
            loading={eager ? 'eager' : 'lazy'}
            decoding="async"
          />
        ) : (
          <div className={styles.placeholder}>
            <span className={styles.placeholderName}>{service.name}</span>
            <span className={styles.placeholderNote}>screenshot coming</span>
          </div>
        )}
      </div>
    </div>
  );
}

function Stage({
  section,
  sectionIndex,
  active,
  registerSection,
  registerPanel,
}: {
  section: TourSection;
  sectionIndex: number;
  active: number;
  registerSection: (index: number, el: HTMLElement | null) => void;
  registerPanel: (section: number, index: number, el: HTMLElement | null) => void;
}): ReactNode {
  const headingId = `tour-${section.name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')}`;

  return (
    <section
      className={styles.stage}
      ref={(el) => {
        registerSection(sectionIndex, el);
      }}
      aria-labelledby={headingId}
    >
      <div className="container">
        <div className={styles.stageHead}>
          <span className={styles.kicker}>{section.kicker}</span>
          <Heading as="h2" id={headingId} className={styles.stageTitle}>
            {section.name}
          </Heading>
          {section.kind === 'recommended' && (
            <span className={styles.stageBadge}>Recommended · not hosted</span>
          )}
          {section.lede && <p className={styles.stageLede}>{section.lede}</p>}
        </div>

        <div className={styles.grid}>
          <div className={styles.frameCol}>
            <div className={styles.frameSticky}>
              <div className={styles.frame}>
                {section.services.map((service, i) => (
                  <Shot
                    key={service.slug}
                    service={service}
                    active={i === active}
                    eager={sectionIndex === 0 && i === 0}
                  />
                ))}
              </div>
            </div>
          </div>

          <div className={styles.panels}>
            {section.services.map((service, i) => (
              <article
                key={service.slug}
                ref={(el) => {
                  registerPanel(sectionIndex, i, el);
                }}
                className={clsx(styles.panel, i === active && styles.panelActive)}
              >
                {/* Shown only below the sticky breakpoint, where the frame column is hidden. */}
                <div className={styles.inlineShot}>
                  <Shot service={service} active eager={sectionIndex === 0 && i === 0} />
                </div>

                <Heading as="h3" className={styles.panelTitle}>
                  {service.name}
                </Heading>
                <p className={styles.panelBlurb}>{service.blurb}</p>
                {service.tag && <p className={styles.panelTag}>{service.tag}</p>}
                <p className={styles.panelWhat}>{service.what}</p>
                {service.note && <p className={styles.panelNote}>{service.note}</p>}
                <div className={styles.panelLinks}>
                  <Link className={styles.panelDocs} to={service.docs}>
                    Docs
                  </Link>
                  {service.source && (
                    <a
                      className={styles.panelSource}
                      href={service.source}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {service.proprietary ? 'Website' : 'Source'}
                    </a>
                  )}
                </div>
              </article>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

export default function ServiceTour(): ReactNode {
  const [active, setActive] = useState<number[]>(() => TOUR.map(() => 0));
  const sections = useRef<(HTMLElement | null)[]>([]);
  const panels = useRef<(HTMLElement | null)[][]>(TOUR.map(() => []));
  // The scroll handler reads the active panels but must not be rebuilt when they
  // change, so it goes through this mirror rather than closing over the state.
  const activeRef = useRef(active);
  // Cached at registration: re-querying the heading every frame, for every panel,
  // is the one avoidable cost in the rAF loop.
  const headings = useRef<(Element | null)[][]>(TOUR.map(() => []));

  const registerSection = useCallback((index: number, el: HTMLElement | null) => {
    sections.current[index] = el;
  }, []);

  const registerPanel = useCallback(
    (section: number, index: number, el: HTMLElement | null) => {
      (panels.current[section] ??= [])[index] = el;
      // Child refs attach before the parent's, so the h3 is already in the DOM.
      (headings.current[section] ??= [])[index] = el?.querySelector('h3') ?? el;
    },
    [],
  );

  // One rAF-throttled scroll handler drives the whole tour. It does two things
  // per visible section: pick the panel nearest the viewport's centre line (that
  // one owns the pinned frame), and write a --drift custom property that CSS
  // applies to the screenshot.
  //
  // Deriving the active panel here rather than from an IntersectionObserver
  // keeps it total: there is no dead zone between sections where nothing is
  // intersecting and the frame would be left showing a stale screenshot after a
  // jump — a refresh that restores scroll position lands in exactly that gap.
  //
  // The drift is the only literal parallax; the real effect is the frame holding
  // still while the text column moves past it.
  useEffect(() => {
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');

    let frame = 0;
    const update = () => {
      frame = 0;
      const vh = window.innerHeight;
      const centre = vh / 2;
      const next: number[] = [];
      const current = activeRef.current;
      let changed = false;

      // Style writes are collected and flushed after the read pass: setting
      // --drift here, between two getBoundingClientRect calls, forces a layout.
      const drifts: [HTMLElement, string][] = [];

      for (let s = 0; s < TOUR.length; s += 1) {
        const el = sections.current[s];
        next[s] = current[s];
        if (!el) continue;

        const rect = el.getBoundingClientRect();
        if (rect.bottom < 0 || rect.top > vh) continue;

        if (!reduced.matches) {
          const travel = Math.max(rect.height - vh, 1);
          const progress = Math.min(Math.max(-rect.top / travel, 0), 1);
          drifts.push([el, `${(progress - 0.5) * 2 * DRIFT_PX}px`]);
        }

        // Whichever entry's heading is nearest the middle of the screen owns
        // the frame. Because the entries are evenly spaced, "nearest" hands over
        // exactly halfway between one and the next — so the card never sits
        // beside the wrong entry's text for long.
        //
        // Measure the heading, not the panel box: the box centre sits ~115px
        // below the text centred inside it, and keying off the box would shift
        // every handover by that much. The heading also stays right when a blurb
        // runs to a different number of lines.
        let best = 0;
        let bestDistance = Infinity;
        (panels.current[s] ?? []).forEach((panel, i) => {
          if (!panel) return;
          const heading = headings.current[s]?.[i] ?? panel;
          const h = heading.getBoundingClientRect();
          const distance = Math.abs(h.top + h.height / 2 - centre);
          if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
          }
        });
        next[s] = best;
        if (best !== current[s]) changed = true;
      }

      for (const [el, drift] of drifts) el.style.setProperty('--drift', drift);

      if (changed) {
        activeRef.current = next;
        setActive(next);
      }
    };

    const onScroll = () => {
      if (frame) return;
      frame = requestAnimationFrame(update);
    };

    update();
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
    return () => {
      if (frame) cancelAnimationFrame(frame);
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
    };
  }, []);

  return (
    <div className={styles.tour}>
      {TOUR.map((section, i) => (
        <Stage
          key={section.name}
          section={section}
          sectionIndex={i}
          active={active[i]}
          registerSection={registerSection}
          registerPanel={registerPanel}
        />
      ))}
    </div>
  );
}
