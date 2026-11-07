/**
 * The DQ tab row: every tab strip of the DQ UI (the stat panel's tabs, the
 * chat's, the Inspect and MC sub-tabs). A flat tgui-core Tabs list sitting on
 * the row's 2px bottom rule, so the selected tab's underline lands on that
 * rule whatever else the row holds; `children` go at the row's end (buttons,
 * a search box). With `onReorder` the tabs can be dragged onto each other to
 * change their order. Styles: tgui/styles/dq/tabs.scss.
 */

import { type ReactNode, useState } from 'react';
import { Tabs as CoreTabs } from 'tgui-core/components';
import { classes } from 'tgui-core/react';
import { moveBefore } from './reorder';

export type Tab = {
  id: string;
  label: ReactNode;
  selected?: boolean;
  /** A tab that may not be dragged or dropped on (a pinned first tab). */
  fixed?: boolean;
  /** Hover text (a label cut short by the row). */
  title?: string;
};

/** How the row lays out its tabs: wrap onto more rows, one scrolling row, or the denser classic look. */
export type TabsLayout = 'wrap' | 'scrollable' | 'classic';

type Props = {
  tabs: Tab[];
  onSelect: (id: string) => void;
  /** Called with the new order after a tab is dropped on another; omit to disable dragging. */
  onReorder?: (order: string[]) => void;
  layout?: TabsLayout;
  /** `small` for a sub-tab row inside a page (Inspect, MC). */
  size?: 'normal' | 'small';
  className?: string;
  /** Right after the last tab (an add-tab button). */
  afterTabs?: ReactNode;
  /** At the row's end (buttons, a search box). */
  children?: ReactNode;
};

const DRAG_TYPE = 'text/x-dq-tab';

export function Tabs(props: Props) {
  const {
    tabs,
    onSelect,
    onReorder,
    layout = 'wrap',
    size = 'normal',
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
      className={classes([
        'DqTabs',
        `DqTabs--${layout}`,
        size === 'small' && 'DqTabs--small',
        className,
      ])}
    >
      <CoreTabs className="DqTabs__list">
        {tabs.map((tab) => {
          const movable = !!onReorder && !tab.fixed;
          return (
            <CoreTabs.Tab
              key={tab.id}
              selected={tab.selected}
              className={classes([
                dragging === tab.id && 'DqTabs__tab--dragged',
                over === tab.id && dragging !== tab.id && 'DqTabs__tab--over',
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
              {tab.title ? (
                <span title={tab.title}>{tab.label}</span>
              ) : (
                tab.label
              )}
            </CoreTabs.Tab>
          );
        })}
      </CoreTabs>
      {afterTabs !== undefined && (
        <div className="DqTabs__after">{afterTabs}</div>
      )}
      {children !== undefined && <div className="DqTabs__end">{children}</div>}
    </div>
  );
}
