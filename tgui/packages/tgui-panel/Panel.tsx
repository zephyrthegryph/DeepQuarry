/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { useAtom, useAtomValue } from 'jotai';
import { Pane } from 'tgui/layouts';
import { Button, Section, Stack } from 'tgui-core/components';
import { visibleAtom } from './audio/atoms';
import { NowPlayingWidget } from './audio/NowPlayingWidget';
import { ChatPanel, ScrollToBottom } from './chat/ChatPanel';
import { ChatTabs } from './chat/ChatTabs';
import { useChatPersistence } from './chat/use-chat-persistence';
import { useChatScanlines } from './consoleScanlines';
import { gameAtom } from './game/atoms';
import { useKeepAlive } from './game/use-keep-alive';
import { ChatInput } from './input/ChatInput';
import { layoutModeAtom } from './layout/atoms';
import {
  ChatPinHint,
  ChatResizeHandles,
  ChatSplitHandles,
  useChatDrag,
  useShareReport,
} from './layout/ChatLayout';
import { PingIndicator } from './ping/PingIndicator';
import { useAutoReconnect } from './reconnect';
import { settingsVisibleAtom } from './settings/atoms';
import { SettingsPanel } from './settings/SettingsPanel';
import { useSettings } from './settings/use-settings';

export function Panel(props) {
  const [audioVisible, setAudioVisible] = useAtom(visibleAtom);
  const game = useAtomValue(gameAtom);
  const { settings } = useSettings();
  const [settingsVisible, setSettingsVisible] = useAtom(settingsVisibleAtom);
  useChatPersistence();
  useAutoReconnect(!!game.connectionLostAt || !!game.roundRestartedAt);
  useChatScanlines();
  useKeepAlive();
  useShareReport();
  const floating = useAtomValue(layoutModeAtom) === 'float';
  const drag = useChatDrag();

  return (
    <Pane
      canSuspend={false}
      className={floating ? 'ChatConsole ChatConsole--float' : 'ChatConsole'}
    >
      <Stack fill vertical>
        <Stack.Item>
          <Section fitted>
            <div className="ChatDragRow" onPointerDown={drag.onPointerDown}>
              <ChatTabs>
                <PingIndicator />
                <Button
                  selected={audioVisible}
                  icon="music"
                  tooltip="Music player"
                  tooltipPosition="bottom-start"
                  onClick={() => {
                    setAudioVisible((v) => !v);
                  }}
                />
                <Button
                  icon={settingsVisible ? 'times' : 'cog'}
                  selected={settingsVisible}
                  tooltip={settingsVisible ? 'Close settings' : 'Open settings'}
                  tooltipPosition="bottom-start"
                  onClick={() => setSettingsVisible((v) => !v)}
                />
              </ChatTabs>
            </div>
          </Section>
        </Stack.Item>
        {audioVisible && (
          <Stack.Item>
            <Section>
              <NowPlayingWidget />
            </Section>
          </Stack.Item>
        )}
        {settingsVisible && (
          <Stack.Item>
            <SettingsPanel />
          </Stack.Item>
        )}
        <Stack.Item grow>
          <Section fill fitted position="relative">
            <Pane.Content scrollable id="chat-pane">
              <ChatPanel lineHeight={settings.lineHeight} />
            </Pane.Content>
            <ScrollToBottom />
          </Section>
        </Stack.Item>
        <Stack.Item>
          <ChatInput />
        </Stack.Item>
      </Stack>
      {floating && <ChatPinHint hint={drag.hint} />}
      {floating && <ChatResizeHandles />}
      <ChatSplitHandles />
    </Pane>
  );
}
