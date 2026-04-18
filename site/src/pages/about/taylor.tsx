import type { ReactNode } from "react";
import Link from "@docusaurus/Link";
import Layout from "@theme/Layout";
import Heading from "@theme/Heading";
import clsx from "clsx";
import styles from "./about.module.css";
const SECTION_CONTAINER_CLASS = styles.timelineSection;
const SECTION_CONTENT_CLASS = styles.timelineContent;
const MAX_WIDTH = styles.timelineText;
const TIMELINE_HEADER_CLASS = styles.timelineImageCol;
const SECTION_HEADER = styles.timelineEntryTitle;
const SECTION_IMAGE_CLASS = styles.timelineImg;

// Timeline SVG with inline styles
const Timeline = () => {
  const svgStyle = {
    position: "absolute",
    bottom: "-90px",
    height: "350px",
    width: "50px",
    zIndex: -1,
  };
  const lineStyle = { stroke: "gray", strokeWidth: 4 };
  const circleStyle = { fill: "gray" };

  return (
    <svg style={svgStyle as never}>
      <line x1="25" y1="0" x2="25" y2="350" style={lineStyle} />
      <circle cx="25" cy="175" r="10" style={circleStyle} />
    </svg>
  );
};

const AUTHORS = [
  {
    key: "taylor",
    name: "Taylor McKay",
    imageUrl: "https://github.com/jtmckay.png",
    href: "/about/taylor",
  },
];

const PROJECTS = [
  {
    name: "Existential",
    href: "https://github.com/jtmckay/existential",
    description:
      "A curated self-hosted stack combining AI, automation, note-taking, and productivity services. One command bootstraps the entire environment from .example files to a unified Docker Compose.",
    tags: ["Docker", "Shell", "Python", "Docusaurus", "Self-hosting"],
  },
  {
    name: "Decree",
    href: "https://github.com/jtmckay/existential/tree/main/services/decree",
    description:
      "Automation engine at the heart of the Existential stack. Runs routines, syncs Gmail, manages rclone remotes, and exposes webhooks — all from a single container with no external dependencies.",
    tags: ["Docker", "Shell", "rclone", "OAuth", "Webhooks"],
  },
];

function AuthorSidebar({ activeKey }: { activeKey: string }) {
  return (
    <aside className={styles.sidebar}>
      <p className={styles.sidebarLabel}>Authors</p>
      <ul className="menu__list">
        {AUTHORS.map((a) => (
          <li key={a.key} className="menu__list-item">
            <Link
              href={a.href}
              className={clsx("menu__link", styles.authorLink, {
                "menu__link--active": a.key === activeKey,
              })}
            >
              <img
                src={a.imageUrl}
                alt={a.name}
                className={styles.authorAvatar}
              />
              {a.name}
            </Link>
          </li>
        ))}
      </ul>
    </aside>
  );
}

export default function TaylorAbout(): ReactNode {
  return (
    <Layout
      title="Taylor McKay — About"
      description="Self-hosted infrastructure, AI tooling, and automation."
    >
      <div className={styles.pageWrapper}>
        <AuthorSidebar activeKey="taylor" />

        <main className={styles.content}>
          {/* Header */}
          <Heading as="h1" className={styles.name}>
            Taylor McKay
          </Heading>
          <p className={styles.tagline}>
            Self-hosted infrastructure · AI tooling · Automation
          </p>
          <div className={styles.links}>
            <Link
              className="button button--primary button--sm"
              href="https://github.com/jtmckay"
            >
              GitHub
            </Link>
            <Link
              className="button button--outline button--primary button--sm"
              href="/blog/authors/taylor"
            >
              Blog Posts
            </Link>
            <Link
              className="button button--outline button--primary button--sm"
              href="https://discord.gg/McH3kPh9gM"
            >
              Discord
            </Link>
          </div>

          {/* About */}
          <Heading as="h2" className={styles.sectionTitle}>
            About
          </Heading>
          <p className={styles.about}>
            I build systems that run quietly in the background — self-hosted
            stacks that unify data, automate routine tasks, and leverage local
            AI without depending on third-party services. My focus is on
            open-source software, full data ownership, and infrastructure that
            stays out of the way so you can focus on what matters.
          </p>

          {/* Projects */}
          <Heading as="h2" className={styles.sectionTitle}>
            Projects
          </Heading>
          <div className={styles.projectGrid}>
            {PROJECTS.map((p) => (
              <Link key={p.name} href={p.href} className={styles.projectCard}>
                <div className={styles.projectName}>{p.name}</div>
                <p className={styles.projectDesc}>{p.description}</p>
                <div className={styles.projectTags}>
                  {p.tags.map((t) => (
                    <span key={t} className={styles.tag}>
                      {t}
                    </span>
                  ))}
                </div>
              </Link>
            ))}
          </div>
          <br />
          <br />

          <div className={styles.timelineList}>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2024 - Serve to be Free</div>
                  <div>Serving made simple.</div>
                  <br />
                  <div>
                    <a
                      className="underline"
                      href="https://github.com/techtobefree/serve"
                    >
                      https://github.com/techtobefree/serve
                    </a>
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img src="/images/stbf.jpg" className={SECTION_IMAGE_CLASS} />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2024 - Mo'bus</div>
                  <div>State management; extending MobX with RxJS</div>
                  <br />
                  <div>
                    Mobus can and should coexist with simple react-type hook
                    state management, and even MobX state management.
                  </div>
                  <br />
                  <div>
                    This library makes it simple to add event driven responses
                    to MobX. As well as optimistic UI updates, and provides an
                    interface to exploit the full power of RxJS in your system.
                  </div>
                  <br />
                  <div>
                    <a
                      className="underline"
                      href="https://www.npmjs.com/package/mobus"
                      rel="noreferrer"
                    >
                      https://www.npmjs.com/package/mobus
                    </a>
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/2024-10-12_15-43-12_2706.jpeg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2024 - Swingset arm</div>
                  <div>
                    You need two pivot points for each set of chains in order
                    for your kid to push themselves.
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/swingset.png"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>
                    2024 - Pinewood Derby sensor
                  </div>
                  <div>
                    A simple array of sensors to track the fastest cars.
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/PXL_20240224_181114676.jpg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2023 - Todoalot</div>
                  <div>A todo app, built for individuals with ADHD.</div>
                  <br />
                  <div>Retired August 31, 2024</div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/tater-task.jpg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2023 - Tater Flow</div>
                  <div>A visual way to work with data.</div>
                  <br />
                  <div>Extending Mathite.</div>
                  <br />
                  <div>
                    <a
                      className="underline"
                      href="https://flow.existential.company/"
                    >
                      https://flow.existential.company/
                    </a>
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <div
                    className={SECTION_IMAGE_CLASS}
                    style={{ display: "flex", alignItems: "center" }}
                  >
                    <img src="/images/exampleFlow.jpg" />
                  </div>
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2022 - Rx-JSX</div>
                  <div>A replacement for React to build UIs using RxJS.</div>
                  <br />
                  <div>
                    Github:{" "}
                    <a
                      className="underline"
                      href="https://github.com/taterer/rx-jsx"
                    >
                      https://github.com/taterer/rx-jsx
                    </a>
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/2024-10-12_15-43-12_2706.jpeg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>
                    2022 - Taekwonduino contained
                  </div>
                  <div>
                    An arcade game, where you have to punch or kick the
                    indicated targets, using actual taekwondo paddles, so you
                    can kick or punch as hard as you want.
                  </div>
                  <br />
                  <div>
                    This time with light indicators instead of hooking up to an
                    Unreal Engine game.
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/2022-11-27 10.56.37.jpg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>
                    2022 - Taekwonduino Unreal Engine
                  </div>
                  <div>
                    An arcade game, where you have to punch or kick the
                    indicated targets, using actual taekwondo paddles, so you
                    can kick or punch as hard as you want.
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/PXL_20220712_161702437.MP.jpg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2022 - Tater Share</div>
                  <div>Obsidian plugin to allow sharing notes via IPFS.</div>
                  <br />
                  <div>UI never published</div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/2024-10-12_15-43-12_2706.jpeg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>
                    2022 - Typescript Abstract Syntax Tree Explorer
                  </div>
                  <div>Tater TASTE</div>
                  <br />
                  <div>
                    Visualize your way through a Typescript codebase, and
                    hopefully don't get lost.
                  </div>
                  <br />
                  <div>
                    <a
                      className="underline"
                      href="https://www.npmjs.com/package/tater-taste"
                    >
                      https://www.npmjs.com/package/tater-taste
                    </a>
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/taste.jpg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2020 - Tater Tot</div>
                  <div>A React Native recipe shopping assistant.</div>
                  <br />
                  <div>Removed from Google play store April 21, 2024</div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/Screenshot_1605720485.png"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>
                    2019 - Serverless convention
                  </div>
                  <div>
                    A serverless plugin to allow folder conventions to form the
                    infrastructure as code.
                  </div>
                  <br />
                  <div>
                    <a
                      className="underline"
                      href="https://github.com/LeoPlatform/serverless-convention"
                    >
                      https://github.com/LeoPlatform/serverless-convention
                    </a>
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/2024-10-12_15-43-12_2706.jpeg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2019 - Mathite</div>
                  <div>An online graphing calculator.</div>
                  <br />
                  <div>
                    Meant to replace a spreadsheet that I made in college, that
                    I made to help with all of my math homework.
                  </div>
                  <br />
                  <div>
                    Now I regularly use this site when I need to calculate an
                    ammortization schedule, like buying a house or car.
                  </div>
                  <br />
                  <div>
                    <a className="underline" href="https://mathite.com">
                      https://mathite.com/
                    </a>
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/mathite.png"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>
                    2018 - Clipboard to keystrokes
                  </div>
                  <div>A what</div>
                  <div>See more at:</div>
                  <div>
                    <a
                      className="underline"
                      href="https://github.com/jtmckay/ClipboardToKeystrokes"
                    >
                      https://github.com/jtmckay/ClipboardToKeystrokes
                    </a>
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/clipboardtokey.jpg"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>2017 - Penguin Wars</div>
                  <div>A 3D snowball fight game.</div>
                  <br />
                  <div>Try it out!</div>
                  <div>
                    <a
                      className="underline"
                      href="https://jtmckay.github.io/PenguinWars/"
                    >
                      https://jtmckay.github.io/PenguinWars/
                    </a>
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/penguin_wars.png"
                    className={SECTION_IMAGE_CLASS}
                  />
                  <Timeline />
                </div>
              </div>
            </div>
            <div className={SECTION_CONTAINER_CLASS}>
              <div className={SECTION_CONTENT_CLASS}>
                <div className={MAX_WIDTH}>
                  <div className={SECTION_HEADER}>
                    2015 - Breast Cancer Research Lab
                  </div>
                  <div>
                    Fast fourier transform on tissue, to detect malignancy.
                  </div>
                </div>
                <div className={TIMELINE_HEADER_CLASS}>
                  <img
                    src="/images/2024-10-12_15-43-12_2706.jpeg"
                    className={SECTION_IMAGE_CLASS}
                  />
                </div>
              </div>
            </div>
          </div>
        </main>
      </div>
    </Layout>
  );
}
