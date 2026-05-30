import { HtmlRenderer } from './HtmlRenderer';
import type { ActFn } from './PanelTypes';

type Props = {
  html: string;
  act: ActFn;
  enabled?: boolean;
};

// Common case for admin/log panels that embed legacy HTML bodies: the
// host datum forwards byond:// link clicks back into its own Topic().
// Wraps HtmlRenderer with forwardTopic enabled by default.
export const ForwardedHtml = (props: Props) => {
  const { html, act, enabled = true } = props;
  return <HtmlRenderer html={html} act={act} forwardTopic={enabled} />;
};
