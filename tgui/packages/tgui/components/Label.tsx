import type { ComponentProps } from 'react';
import { Box } from 'tgui-core/components';

/** Secondary text in the theme's label colour (captions, hints, field names); takes every Box prop. */
export function Label(props: ComponentProps<typeof Box>) {
  return <Box color="label" {...props} />;
}
