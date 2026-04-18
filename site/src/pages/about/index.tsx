import {Redirect} from '@docusaurus/router';
import type {ReactNode} from 'react';

export default function About(): ReactNode {
  return <Redirect to="/about/taylor" />;
}
