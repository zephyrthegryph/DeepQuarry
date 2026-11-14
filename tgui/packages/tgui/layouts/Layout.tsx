/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { useEffect, useRef } from 'react';
import type { Box } from 'tgui-core/components';
import { addScrollableNode, removeScrollableNode } from 'tgui-core/events';
import { classes } from 'tgui-core/react';
import { computeBoxClassName, computeBoxProps } from 'tgui-core/ui';
import { resolveTheme } from './consoleTheme';
import { useScrollMemory } from './scrollMemory';

type BoxProps = React.ComponentProps<typeof Box>;

type Props = Partial<{
  theme: string;
}> &
  BoxProps;

export function Layout(props: Props) {
  const { className, theme, children, ...rest } = props;

  const themeClass = `theme-${resolveTheme(theme)}`;

  useEffect(() => {
    document.documentElement.className = themeClass;
  }, [themeClass]);

  return (
    <div className={themeClass}>
      <div
        className={classes(['Layout', className, computeBoxClassName(rest)])}
        {...computeBoxProps(rest)}
      >
        {children}
      </div>
    </div>
  );
}

type ContentProps = Partial<{
  scrollable: boolean;
  /** Remember the scroll position under this name (the interface): a reopened window shows what it showed (scrollMemory.ts). */
  scrollKey: string;
}> &
  BoxProps;

function LayoutContent(props: ContentProps) {
  const { className, scrollable, scrollKey, children, ...rest } = props;
  const node = useRef<HTMLDivElement>(null);
  useScrollMemory(node, scrollKey, !!scrollable);

  useEffect(() => {
    const self = node.current;

    if (self && scrollable) {
      addScrollableNode(self);
    }
    return () => {
      if (self && scrollable) {
        removeScrollableNode(self);
      }
    };
  }, []);

  return (
    <div
      className={classes([
        'Layout__content',
        scrollable && 'Layout__content--scrollable',
        className,
        computeBoxClassName(rest),
      ])}
      ref={node}
      {...computeBoxProps(rest)}
    >
      {children}
    </div>
  );
}

Layout.Content = LayoutContent;
