// The ghost panel: every ghost command in one console window (what the Ghost
// tab's verbs used to be). The server lists the actions and the toggles, so a
// new ghost command is a row in the DM list and no change here.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Action = {
  id: string;
  label: string;
  desc: string;
  enabled: BooleanLike;
  why: string | null;
};

type Group = {
  title: string;
  actions: Action[];
};

type Toggle = {
  id: string;
  label: string;
  desc: string;
  value: BooleanLike;
  text: string | null;
  can: BooleanLike;
  why: string | null;
};

type Data = {
  groups: Group[];
  toggles: Toggle[];
  notice: string | null;
};

const ActionButton = (props: { action: Action }) => {
  const { act } = useBackend<Data>();
  const { action } = props;
  return (
    <Button
      fluid
      disabled={!action.enabled}
      tooltip={action.enabled ? action.desc : action.why || action.desc}
      onClick={() => act('ghost_do', { action: action.id })}
    >
      {action.label}
    </Button>
  );
};

const ToggleRow = (props: { toggle: Toggle }) => {
  const { act } = useBackend<Data>();
  const { toggle } = props;
  return (
    <LabeledList.Item label={toggle.label}>
      <Button
        compact
        disabled={!toggle.can}
        selected={!!toggle.value}
        tooltip={toggle.can ? toggle.desc : toggle.why || toggle.desc}
        onClick={() => act('ghost_do', { action: toggle.id })}
      >
        {toggle.text ?? (toggle.value ? 'On' : 'Off')}
      </Button>
    </LabeledList.Item>
  );
};

export const GhostPanel = () => {
  const { data } = useBackend<Data>();
  const { groups, toggles, notice } = data;
  return (
    <Window width={520} height={620} title="Ghost Panel" theme="console">
      <Window.Content scrollable>
        <Stack vertical>
          {!!notice && (
            <Stack.Item>
              <NoticeBox>{notice}</NoticeBox>
            </Stack.Item>
          )}
          {groups.map((group) => (
            <Stack.Item key={group.title}>
              <Section title={group.title}>
                <Box className="GhostPanel__actions">
                  <Stack wrap>
                    {group.actions.map((action) => (
                      <Stack.Item key={action.id} basis="48%" grow>
                        <ActionButton action={action} />
                      </Stack.Item>
                    ))}
                  </Stack>
                </Box>
              </Section>
            </Stack.Item>
          ))}
          <Stack.Item>
            <Section title="Settings">
              <LabeledList>
                {toggles.map((toggle) => (
                  <ToggleRow key={toggle.id} toggle={toggle} />
                ))}
              </LabeledList>
            </Section>
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
