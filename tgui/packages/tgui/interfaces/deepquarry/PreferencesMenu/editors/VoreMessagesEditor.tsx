// DQAdd — Vore custom_heat/custom_cold message list editor. Each message is shown to the
// player when their character hits the temperature extreme; max 10 per list, 400 chars each.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Input,
  Section,
  Stack,
} from 'tgui-core/components';
import type { EditorProps } from './index';

type Data = { heat: string[]; cold: string[] };

const MessageList = ({
  which,
  messages,
}: {
  which: 'heat' | 'cold';
  messages: string[];
}) => {
  const { act } = useBackend();
  const [draft, setDraft] = useState('');
  const [editingIdx, setEditingIdx] = useState<number | null>(null);
  const [editingText, setEditingText] = useState('');

  const send = (action: string, params: Record<string, unknown>) =>
    act('dq_editor_action', {
      editor: 'vore_messages',
      action,
      params: { which, ...params },
    });

  return (
    <Section
      title={which === 'heat' ? 'Hot weather messages' : 'Cold weather messages'}
    >
      <Stack vertical>
        {messages.map((msg, idx) => (
          <Stack.Item key={`${idx}-${msg}`}>
            {editingIdx === idx ? (
              <Stack align="center">
                <Stack.Item grow>
                  <Input
                    fluid
                    value={editingText}
                    onChange={(v) => setEditingText(v)}
                  />
                </Stack.Item>
                <Stack.Item>
                  <Button
                    icon="check"
                    color="good"
                    onClick={() => {
                      send('edit_message', { index: idx + 1, text: editingText });
                      setEditingIdx(null);
                    }}
                  />
                </Stack.Item>
                <Stack.Item>
                  <Button icon="xmark" onClick={() => setEditingIdx(null)} />
                </Stack.Item>
              </Stack>
            ) : (
              <Stack align="center">
                <Stack.Item grow>
                  <Box>{msg}</Box>
                </Stack.Item>
                <Stack.Item>
                  <Button
                    icon="pen"
                    onClick={() => {
                      setEditingIdx(idx);
                      setEditingText(msg);
                    }}
                  />
                </Stack.Item>
                <Stack.Item>
                  <Button
                    icon="trash"
                    color="bad"
                    onClick={() => send('remove_message', { index: idx + 1 })}
                  />
                </Stack.Item>
              </Stack>
            )}
          </Stack.Item>
        ))}
        {messages.length < 10 && (
          <Stack.Item>
            <Stack>
              <Stack.Item grow>
                <Input
                  fluid
                  placeholder="Add a new message..."
                  value={draft}
                  onChange={(v) => setDraft(v)}
                />
              </Stack.Item>
              <Stack.Item>
                <Button
                  icon="plus"
                  color="good"
                  disabled={!draft.trim()}
                  onClick={() => {
                    send('add_message', { text: draft });
                    setDraft('');
                  }}
                />
              </Stack.Item>
            </Stack>
          </Stack.Item>
        )}
      </Stack>
    </Section>
  );
};

export const VoreMessagesEditor = ({ data }: EditorProps) => {
  const d = data as Data;
  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(360px, 1fr))',
        gap: '12px',
        alignItems: 'start',
      }}
    >
      <MessageList which="heat" messages={d.heat ?? []} />
      <MessageList which="cold" messages={d.cold ?? []} />
    </Box>
  );
};
