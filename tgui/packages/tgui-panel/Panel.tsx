/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { useAtom, useAtomValue } from 'jotai';
import { useState } from 'react';
import { Pane } from 'tgui/layouts';
import { Button, Section, Stack } from 'tgui-core/components';
import { visibleAtom } from './audio/atoms';
import { NowPlayingWidget } from './audio/NowPlayingWidget';
import { ChatPanel } from './chat/ChatPanel';
import { ChatTabs } from './chat/ChatTabs';
import { useChatPersistence } from './chat/use-chat-persistence';
import { useChatScanlines } from './consoleScanlines';
import { gameAtom } from './game/atoms';
import { useKeepAlive } from './game/use-keep-alive';
import { ChatInput } from './input/ChatInput';
import { layoutModeAtom } from './layout/atoms';
import {
  ChatPinHint,
  ChatResizeGrip,
  useChatDrag,
  useShareReport,
} from './layout/ChatLayout';
import { Notifications } from './Notifications';
import { PingIndicator } from './ping/PingIndicator';
import { ReconnectButton } from './reconnect';
import { settingsVisibleAtom } from './settings/atoms';
import { SettingsPanel } from './settings/SettingsPanel';
import { useSettings } from './settings/use-settings';

export function Panel(props) {
  const [audioVisible, setAudioVisible] = useAtom(visibleAtom);
  const game = useAtomValue(gameAtom);
  const { settings } = useSettings();
  const [settingsVisible, setSettingsVisible] = useAtom(settingsVisibleAtom);
  const [dismissedWarning, setDismissedWarning] = useState(false);
  useChatPersistence();
  useChatScanlines();
  useKeepAlive(setDismissedWarning);
  useShareReport();
  const floating = useAtomValue(layoutModeAtom) === 'float';
  const drag = useChatDrag();

  return (
    <Pane
      theme={settings.theme}
      canSuspend={false}
      className={floating ? 'ChatConsole ChatConsole--float' : 'ChatConsole'}
    >
      <Stack fill vertical>
        <Stack.Item>
          <Section fitted>
            <div className="ChatDragRow" onPointerDown={drag.onPointerDown}>
              <Stack mx={0.5} my={0.25} align="center">
                <Stack.Item grow>
                  <ChatTabs />
                </Stack.Item>
                <Stack.Item>
                  <PingIndicator />
                </Stack.Item>
                <Stack.Item>
                  <Button
                    selected={audioVisible}
                    icon="music"
                    tooltip="Music player"
                    tooltipPosition="bottom-start"
                    onClick={() => {
                      setAudioVisible((v) => !v);
                    }}
                  />
                </Stack.Item>
                <Stack.Item>
                  <Button
                    icon={settingsVisible ? 'times' : 'cog'}
                    selected={settingsVisible}
                    tooltip={
                      settingsVisible ? 'Close settings' : 'Open settings'
                    }
                    tooltipPosition="bottom-start"
                    onClick={() => setSettingsVisible((v) => !v)}
                  />
                </Stack.Item>
              </Stack>
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
            <Notifications>
              {settings.showReconnectWarning &&
                game.connectionLostAt &&
                !dismissedWarning && (
                  <Notifications.Item
                    rightSlot={
                      <ReconnectButton
                        onDismissedWarning={setDismissedWarning}
                      />
                    }
                  >
                    You are either AFK, experiencing lag or the connection has
                    closed.
                  </Notifications.Item>
                )}
              {settings.showReconnectWarning && game.roundRestartedAt && (
                <Notifications.Item>
                  The connection has been closed because the server is
                  restarting. Please wait while you automatically reconnect.
                </Notifications.Item>
              )}
            </Notifications>
          </Section>
        </Stack.Item>
        <Stack.Item>
          <ChatInput />
        </Stack.Item>
      </Stack>
      {floating && <ChatPinHint hint={drag.hint} />}
      {floating && <ChatResizeGrip />}
    </Pane>
  );
}
