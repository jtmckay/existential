import React, { type ReactNode } from "react";
import clsx from "clsx";
import {
  PageMetadata,
  HtmlClassNameProvider,
  ThemeClassNames,
} from "@docusaurus/theme-common";
import {
  useBlogAuthorPageTitle,
  BlogAuthorNoPostsLabel,
} from "@docusaurus/theme-common/internal";
import Link from "@docusaurus/Link";
import BlogLayout from "@theme/BlogLayout";
import BlogListPaginator from "@theme/BlogListPaginator";
import SearchMetadata from "@theme/SearchMetadata";
import type { Props } from "@theme/Blog/Pages/BlogAuthorsPostsPage";
import BlogPostItems from "@theme/BlogPostItems";
import Author from "@theme/Blog/Components/Author";

function Metadata({ author }: Props): ReactNode {
  const title = useBlogAuthorPageTitle(author);
  return (
    <>
      <PageMetadata title={title} />
      <SearchMetadata tag="blog_authors_posts" />
    </>
  );
}

function AboutLink({ author }: Pick<Props, "author">) {
  const authorKey = author.page?.permalink?.split("/").filter(Boolean).pop();
  const href = authorKey ? `/about/${authorKey}` : "/about";
  return <Link href={href}>More about the author</Link>;
}

function Content({ author, items, sidebar, listMetadata }: Props): ReactNode {
  return (
    <BlogLayout sidebar={sidebar}>
      <header className="margin-bottom--xl">
        <Author as="h1" author={author} />
        {author.description && <p>{author.description}</p>}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "0.5rem",
            flexWrap: "wrap",
          }}
        >
          <AboutLink author={author} />
        </div>
      </header>
      {items.length === 0 ? (
        <p>
          <BlogAuthorNoPostsLabel />
        </p>
      ) : (
        <>
          <hr />
          <BlogPostItems items={items} />
          <BlogListPaginator metadata={listMetadata} />
        </>
      )}
    </BlogLayout>
  );
}

export default function BlogAuthorsPostsPage(props: Props): ReactNode {
  return (
    <HtmlClassNameProvider
      className={clsx(
        ThemeClassNames.wrapper.blogPages,
        ThemeClassNames.page.blogAuthorsPostsPage,
      )}
    >
      <Metadata {...props} />
      <Content {...props} />
    </HtmlClassNameProvider>
  );
}
