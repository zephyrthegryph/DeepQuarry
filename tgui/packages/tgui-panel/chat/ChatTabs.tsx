/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { useAtom } from 'jotai';
import type { ReactNode } from 'react';
import { ConsoleTabs } from 'tgui/components';
import { Box, Button } from 'tgui-core/components';
import { settingsVisibleAtom } from '../settings/atoms';
import { useChatPages } from './use-chat-pages';

type UnreadCountWidgetProps = {
  value: number;
};

function UnreadCountWidget(props: UnreadCountWidgetProps) {
  const { value } = props;
  return <Box className="UnreadCount">{value > 99 ? '99+' : value}</Box>;
}

/**
 * The chat's tab row: the shared console tab row (the stat panel's), with the
 * add-tab button and `children` (ping, music, settings) at its end. Tabs can
 * be dragged onto each other to reorder them; the main tab stays first.
 */
export function ChatTabs(props: { children?: ReactNode }) {
  const {
    addChatPage,
    changeChatPage,
    reorderChatPages,
    pages,
    pagesRecord,
    currentPageId,
  } = useChatPages();

  const [, setSettingsVisible] = useAtom(settingsVisibleAtom);

  return (
    <ConsoleTabs
      className="ChatTabs"
      layout="scrollable"
      tabs={pages.map((page, index) => {
        const actual = pagesRecord[page];
        return {
          id: page,
          selected: page === currentPageId,
          fixed: index === 0,
          label: (
            <>
              {actual.name}
              {!actual.hideUnreadCount && actual.unreadCount > 0 && (
                <UnreadCountWidget value={actual.unreadCount} />
              )}
            </>
          ),
        };
      })}
      onSelect={(id) => changeChatPage(pagesRecord[id])}
      onReorder={reorderChatPages}
      afterTabs={
        <Button
          icon="plus"
          tooltip="Add a chat tab"
          tooltipPosition="bottom"
          onClick={() => {
            addChatPage();
            setSettingsVisible(true);
          }}
        />
      }
    >
      {props.children}
    </ConsoleTabs>
  );
}
