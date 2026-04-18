import type {ReactNode} from 'react';
import {Redirect} from '@docusaurus/router';
import type {Props} from '@theme/Blog/Pages/BlogAuthorsListPage';

export default function BlogAuthorsListPage(_props: Props): ReactNode {
  return <Redirect to="/about" />;
}
