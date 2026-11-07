/**
 * The one tab row of the console UI: the stat panel's tabs and the chat's.
 * A flat tgui-core Tabs list sitting on the row's 2px bottom rule, so the
 * selected tab's underline lands on that rule whatever else the row holds;
 * `children` go at the row's end (buttons, a search box). With `onReorder`
 * the tabs can be dragged onto each other to change their order.
 * Styles: tgui/styles/components/ConsoleTabs.scss.
 */

import { type ReactNode, useState } from 'react';
import { Tabs } from 'tgui-core/components';
import { classes } from 'tgui-core/react';
import { moveBefore } from './reorder';

export type ConsoleTab = {
  id: string;
  label: ReactNode;
  selected?: boolean;
  /** A tab that may not be dragged or dropped on (a pinned first tab). */
  fixed?: boolean;
};

/** How the row lays out its tabs: wrap onto more rows, one scrolling row, or the denser classic look. */
export type ConsoleTabsLayout = 'wrap' | 'scrollable' | 'classic';

type Props = {
  tabs: ConsoleTab[];
  onSelect: (id: string) => void;
  /** Called with the new order after a tab is dropped on another; omit to disable dragging. */
  onReorder?: (order: string[]) => void;
  layout?: ConsoleTabsLayout;
  className?: string;
  /** Right after the last tab (an add-tab button). */
  afterTabs?: ReactNode;
  /** At the row's end (buttons, a search box). */
  children?: ReactNode;
};

const DRAG_TYPE = 'text/x-console-tab';

export function ConsoleTabs(props: Props) {
  const {
    tabs,
    onSelect,
    onReorder,
    layout = 'wrap',
    className,
    afterTabs,
    children,
  } = props;
  const [dragging, setDragging] = useState<string | null>(null);
  const [over, setOver] = useState<string | null>(null);
  const ids = tabs.map((tab) => tab.id);
  const end = () => {
    setDragging(null);
    setOver(null);
  };

  return (
    <div
      className={classes(['ConsoleTabs', `ConsoleTabs--${layout}`, className])}
    >
      <Tabs className="ConsoleTabs__list">
        {tabs.map((tab) => {
          const movable = !!onReorder && !tab.fixed;
          return (
            <Tabs.Tab
              key={tab.id}
              selected={tab.selected}
              className={classes([
                dragging === tab.id && 'ConsoleTabs__tab--dragged',
                over === tab.id &&
                  dragging !== tab.id &&
                  'ConsoleTabs__tab--over',
              ])}
              onClick={() => onSelect(tab.id)}
              draggable={movable}
              onDragStart={(event: React.DragEvent) => {
                event.dataTransfer.effectAllowed = 'move';
                event.dataTransfer.setData(DRAG_TYPE, tab.id);
                setDragging(tab.id);
              }}
              onDragOver={(event: React.DragEvent) => {
                if (!dragging || !movable) return;
                event.preventDefault();
                event.dataTransfer.dropEffect = 'move';
                if (over !== tab.id) setOver(tab.id);
              }}
              onDragLeave={() => {
                if (over === tab.id) setOver(null);
              }}
              onDrop={(event: React.DragEvent) => {
                event.preventDefault();
                if (dragging && movable && onReorder) {
                  const next = moveBefore(ids, dragging, tab.id);
                  if (next !== ids) onReorder(next);
                }
                end();
              }}
              onDragEnd={end}
            >
              {tab.label}
            </Tabs.Tab>
          );
        })}
      </Tabs>
      {afterTabs !== undefined && (
        <div className="ConsoleTabs__after">{afterTabs}</div>
      )}
      {children !== undefined && (
        <div className="ConsoleTabs__end">{children}</div>
      )}
    </div>
  );
}
