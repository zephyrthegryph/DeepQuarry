/**
 * The chat as a tgui window (code/content/client/chat_ui.dm,
 * doc/rewrite/proposals/window_system.md section 12): docked in the
 * right-hand column by default, floating like any other window, moved by the
 * same dock model. The chat itself is the tgui-panel chat (Panel): docked, it
 * is part of the column page, whose own bus has every chat message all along;
 * floating, this window's messages feed a fresh copy of that bus. Either way
 * it loads and saves the stored chat log, asks the server for what follows
 * the log (chat/ready, answered from the server's history ring; chat/log.ts)
 * and keeps the input draft on the server (chat/draft), so a move loses
 * nothing. Both pages draw it with the one chat sheet (chat-theme.scss).
 */
import 'tgui-panel/styles/chat-theme.scss';

import { Provider } from 'jotai';
import { useContext, useEffect, useRef } from 'react';
import { useBackend, useWindowMessages, useWindowSend } from 'tgui/backend';
import { EmbeddedContext } from 'tgui/embedded';
import { Window } from 'tgui/layouts';
import { chatLoadedAtom } from 'tgui-panel/chat/atoms';
import { saveChatToStorage } from 'tgui-panel/chat/helpers';
import { chatResumeAfter, setChatSession } from 'tgui-panel/chat/log';
import { chatRenderer } from 'tgui-panel/chat/renderer';
import { bus } from 'tgui-panel/events/listeners';
import { store } from 'tgui-panel/events/store';
import { databaseBackendEnabledAtom } from 'tgui-panel/game/atoms';
import { chatDraftAtom } from 'tgui-panel/input/atoms';
import { Panel } from 'tgui-panel/Panel';

type Data = { draft: string; session: string };

/** The page messages a floating chat passes to the chat's bus: the column page gets the rest itself. */
const CHAT_TYPES = new Set([
  'asset/stylesheet',
  'audio/playMusic',
  'audio/stopMusic',
  'chat/channels',
  'chat/focusInput',
  'chat/languageRules',
  'chat/message',
  'chat/radioChannels',
  'connected',
  'ping/reply',
  'ping/soft',
  'roundrestart',
]);
const DRAFT_DELAY_MS = 400;

/** A floating chat's message for the chat's bus, or null; chat/config is the panel's `update` (a tgui window's own update is its data). */
export function chatBusMessage(
  type: string,
  payload: unknown,
): { type: string; payload: unknown } | null {
  if (type === 'chat/config') return { type: 'update', payload };
  return CHAT_TYPES.has(type) ? { type, payload } : null;
}

export function Chat() {
  const { data } = useBackend<Data>();
  const embedded = !!useContext(EmbeddedContext);
  const send = useWindowSend();
  const started = useRef(false);
  if (!started.current) {
    started.current = true;
    // The connection the stored log's mark must be from (chat/log.ts).
    if (data?.session) setChatSession(data.session);
    if (data?.draft && !store.get(chatDraftAtom)) {
      store.set(chatDraftAtom, data.draft);
    }
  }
  useWindowMessages((type, payload) => {
    if (embedded) return;
    const message = chatBusMessage(type, payload);
    if (message) bus.dispatch(message);
  });
  useEffect(() => {
    let live = true;
    // Once the stored log is in: ask for what follows it (or what this page last showed).
    chatResumeAfter(() => chatRenderer.clearChat()).then((after) => {
      if (live) send('chat/ready', { after });
    });
    return () => {
      live = false;
      // Leaving this page (floated out, docked back): the next window starts from the log as it is now.
      if (store.get(chatLoadedAtom) && !store.get(databaseBackendEnabledAtom)) {
        saveChatToStorage();
      }
    };
  }, []);
  useEffect(() => {
    let last = store.get(chatDraftAtom);
    let timer: ReturnType<typeof setTimeout> | undefined;
    const unsubscribe = store.sub(chatDraftAtom, () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        const draft = store.get(chatDraftAtom);
        if (draft === last) return;
        last = draft;
        send('chat/draft', { draft });
      }, DRAFT_DELAY_MS);
    });
    return () => {
      clearTimeout(timer);
      unsubscribe();
    };
  }, []);
  return (
    <Window title="Chat" width={520} height={640}>
      <Window.Content fitted>
        <Provider store={store}>
          <div className="chat-theme">
            <Panel />
          </div>
        </Provider>
      </Window.Content>
    </Window>
  );
}
