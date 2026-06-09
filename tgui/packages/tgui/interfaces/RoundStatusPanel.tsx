// Round Status admin panel — TGUI.
//
// Architectural template for the rest of the admin tools. Receives
// structured tgui_data (typed shuttle state machine, game mode, typed
// antag-block tree with member rows) and dispatches every action via
// act() — no embedded byond:// hrefs anywhere. Antag blocks are now
// fully structured via /datum/antagonist/proc/get_check_antag_data
// (see modular_dq/code/modules/admin/antag_panel_data.dm).

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type ShuttleState = 'idle' | 'counting_down' | 'arriving' | 'warmup';

type ShuttleData = {
  state: ShuttleState;
  time_left_seconds?: number;
  time_left_display?: string;
  can_recall?: BooleanLike;
};

type AntagMember = {
  name?: string;
  key: string;
  ref?: string;
  logged_out?: BooleanLike;
  dead?: BooleanLike;
  mob_missing?: BooleanLike;
};

type AntagDisk = {
  name: string;
  location: string;
};

type AntagBlock = {
  role_text: string;
  role_text_plural: string;
  members: AntagMember[];
  disks?: AntagDisk[];
};

type Data = {
  mode_name: string;
  round_duration: string;
  delay_end: BooleanLike;
  shuttle: ShuttleData;
  antag_blocks: AntagBlock[];
};

const ShuttleControls = (props: {
  shuttle: ShuttleData;
  act: (action: string) => void;
}) => {
  const { shuttle, act } = props;
  switch (shuttle.state) {
    case 'idle':
      return (
        <Button icon="rocket" color="bad" onClick={() => act('call_shuttle')}>
          Call Shuttle
        </Button>
      );
    case 'counting_down':
      return (
        <Box mb={1}>
          ETL:{' '}
          <Button onClick={() => act('edit_shuttle_time')}>
            {shuttle.time_left_display}
          </Button>
        </Box>
      );
    case 'arriving':
      return (
        <>
          <Box mb={1}>
            ETA:{' '}
            <Button onClick={() => act('edit_shuttle_time')}>
              {shuttle.time_left_display}
            </Button>
          </Box>
          {shuttle.can_recall ? (
            <Button color="bad" onClick={() => act('recall_shuttle')}>
              Send Back
            </Button>
          ) : null}
        </>
      );
    case 'warmup':
      return (
        <Box italic color="bad">
          Launching now…
        </Box>
      );
    default:
      return null;
  }
};

const AntagMemberRow = (props: {
  member: AntagMember;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { member, act } = props;
  if (member.mob_missing) {
    return <EmptyState>{member.key} — mob not found!</EmptyState>;
  }
  return (
    <Stack>
      <Stack.Item grow>
        <Box>
          {member.name}/{member.key}
          {member.logged_out ? (
            <Box inline italic color="label" ml={1}>
              (logged out)
            </Box>
          ) : null}
          {member.dead ? (
            <Box inline bold color="bad" ml={1}>
              (DEAD)
            </Box>
          ) : null}
        </Box>
      </Stack.Item>
      <Stack.Item>
        <Button
          compact
          onClick={() => act('antag_pp', { ref: member.ref })}
          tooltip="Player options"
        >
          PP
        </Button>{' '}
        <Button
          compact
          onClick={() => act('antag_pm', { ref: member.ref })}
          tooltip="Private message"
        >
          PM
        </Button>{' '}
        <Button
          compact
          onClick={() => act('antag_tp', { ref: member.ref })}
          tooltip="Traitor panel"
        >
          TP
        </Button>
      </Stack.Item>
    </Stack>
  );
};

export const RoundStatusPanel = () => {
  const { data, act } = useBackend<Data>();
  const { mode_name, round_duration, delay_end, shuttle, antag_blocks } = data;

  return (
    <Window width={620} height={700} title="Round Status">
      <Window.Content scrollable>
        <Section title="Round">
          <LabeledList>
            <LabeledList.Item label="Game Mode">{mode_name}</LabeledList.Item>
            <LabeledList.Item label="Round Duration">
              {round_duration}
            </LabeledList.Item>
            <LabeledList.Item label="Round End">
              <Button
                selected={!!delay_end}
                icon={delay_end ? 'pause' : 'play'}
                onClick={() => act('toggle_delay_end')}
              >
                {delay_end ? 'End Round Normally' : 'Delay Round End'}
              </Button>
            </LabeledList.Item>
          </LabeledList>
        </Section>

        <Section title="Emergency Shuttle">
          <ShuttleControls shuttle={shuttle} act={act} />
        </Section>

        {antag_blocks.length > 0
          ? antag_blocks.map((block, i) => (
              <Section key={block.role_text + i} title={block.role_text_plural}>
                <Stack vertical>
                  {block.members.map((m, j) => (
                    <Stack.Item key={(m.ref ?? m.key) + j}>
                      <AntagMemberRow member={m} act={act} />
                    </Stack.Item>
                  ))}
                </Stack>
                {block.disks && block.disks.length > 0 ? (
                  <Box mt={1}>
                    <Box bold mb="2px">
                      Nuclear disk(s)
                    </Box>
                    {block.disks.map((d, k) => (
                      <Box key={d.name + k} color="label">
                        <b>{d.name}</b>, {d.location}
                      </Box>
                    ))}
                  </Box>
                ) : null}
              </Section>
            ))
          : null}
      </Window.Content>
    </Window>
  );
};
