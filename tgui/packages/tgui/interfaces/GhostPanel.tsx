// The ghost panel: every ghost command in one console window (what the Ghost
// tab's verbs used to be). The server lists the actions and the toggles, so a
// new ghost command is a row in the DM list and no change here.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { GhostPanelActions, GhostPanelData } from './generated/GhostPanel';

type Group = GhostPanelData['groups'][number];

type Action = Group['actions'][number];

type Toggle = GhostPanelData['toggles'][number];

const ActionButton = (props: { action: Action }) => {
  const { act } = useBackend<GhostPanelData, GhostPanelActions>();
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
  const { act } = useBackend<GhostPanelData, GhostPanelActions>();
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
  const { data } = useBackend<GhostPanelData, GhostPanelActions>();
  const { groups, toggles } = data;
  return (
    <Window width={520} height={620} title="Ghost Panel" theme="console">
      <Window.Content scrollable>
        <Stack vertical>
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
