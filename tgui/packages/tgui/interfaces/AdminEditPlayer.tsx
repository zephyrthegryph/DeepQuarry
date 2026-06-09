// Admin "Edit Player" panel — structured TGUI replacement for the legacy
// right-click "Show Player Panel" admin context menu.
//
// All clicks dispatch through the existing /datum/admins.Topic handlers so
// the legacy action flows (mute toggles, DNA gene mutation prompts, simple
// transformation, etc.) keep their behavior.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';

type Language = { key: string; known: BooleanLike };
type DnaCell = {
  block: number;
  name: string | null;
  tname: string | null;
  state: 'active' | 'blocked' | 'inactive' | 'empty';
};

type Data = {
  ref: string;
  name: string;
  key: string;
  mob_type: string;
  has_client: BooleanLike;
  is_newplayer: BooleanLike;
  is_human: BooleanLike;
  is_ai: BooleanLike;
  is_carbon: BooleanLike;
  is_small: BooleanLike;
  is_corgi: BooleanLike;
  is_animal: BooleanLike;
  client_name: string | null;
  client_ref: string | null;
  player_age?: number;
  account_join_date?: string;
  account_age?: number;
  inactivity_minutes: number;
  rank_names?: string;
  editrights_mode?: string;
  muted: number;
  can_event: BooleanLike;
  special_character: number; // 0,1,2

  mute_mask_ic: number;
  mute_mask_ooc: number;
  mute_mask_looc: number;
  mute_mask_pray: number;
  mute_mask_adminhelp: number;
  mute_mask_deadchat: number;
  mute_mask_all: number;

  dna_cells: DnaCell[] | null;
  dna_se_length?: number;

  languages: Language[];
};

import type { ActFn } from './common/PanelTypes';

const MuteButton = (props: {
  data: Data;
  act: ActFn;
  mask: number;
  label: string;
}) => {
  const { data, act, mask, label } = props;
  const on = !!(data.muted & mask);
  return (
    <Button
      compact
      color={on ? 'bad' : 'default'}
      onClick={() => act('mute', { mute_type: mask })}
    >
      {label}
    </Button>
  );
};

const SimpleMakeButton = (props: {
  act: ActFn;
  kind: string;
  label: string;
  species?: string;
}) => {
  const { act, kind, label, species } = props;
  return (
    <Button
      compact
      onClick={() => act('simplemake', { kind, species: species ?? '' })}
    >
      {label}
    </Button>
  );
};

const HeaderSection = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section title={`Edit Player: ${data.key}`}>
      <LabeledList>
        <LabeledList.Item label="Mob">{data.name}</LabeledList.Item>
        {data.has_client && data.client_name ? (
          <LabeledList.Item label="Played by">
            {data.client_name}{' '}
            <Button
              compact
              onClick={() =>
                act('editrights', { mode: data.editrights_mode ?? 'add' })
              }
            >
              {data.rank_names ?? 'Player'}
            </Button>
          </LabeledList.Item>
        ) : null}
        <LabeledList.Item label="Mob type">
          <Box style={{ fontFamily: 'monospace' }}>{data.mob_type}</Box>
        </LabeledList.Item>
        {data.is_newplayer ? (
          <LabeledList.Item label="Status">
            <Box bold>Hasn't Entered Game</Box>
          </LabeledList.Item>
        ) : (
          <LabeledList.Item label="Health">
            <Button onClick={() => act('revive')} color="good" icon="heart">
              Heal
            </Button>
          </LabeledList.Item>
        )}
        {data.has_client ? (
          <>
            <LabeledList.Item label="First connection">
              {data.player_age} days ago
            </LabeledList.Item>
            <LabeledList.Item label="BYOND account created">
              {data.account_join_date}
            </LabeledList.Item>
            <LabeledList.Item label="Account age">
              {data.account_age} days
            </LabeledList.Item>
            <LabeledList.Item label="Inactivity">
              {data.inactivity_minutes} minutes
            </LabeledList.Item>
          </>
        ) : (
          <LabeledList.Item label="Inactivity">Logged out</LabeledList.Item>
        )}
      </LabeledList>
      <Box mt={1}>
        <Button compact onClick={() => act('vv')}>
          VV
        </Button>{' '}
        <Button compact onClick={() => act('traitor')}>
          TP
        </Button>{' '}
        <Button compact onClick={() => act('priv_msg')}>
          PM
        </Button>{' '}
        <Button compact onClick={() => act('subtlemessage')}>
          SM
        </Button>{' '}
        <Button compact onClick={() => act('jumpto')}>
          Jump
        </Button>
      </Box>
    </Section>
  );
};

const ModerationSection = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section title="Moderation">
      <Box mb={1}>
        <Button compact color="bad" onClick={() => act('boot2')}>
          Kick
        </Button>{' '}
        <Button compact onClick={() => act('warn')}>
          Warn
        </Button>{' '}
        <Button compact color="bad" onClick={() => act('newban')}>
          Ban
        </Button>{' '}
        <Button compact onClick={() => act('jobban2')}>
          Jobban
        </Button>{' '}
        <Button compact onClick={() => act('notes')}>
          Notes
        </Button>{' '}
        {data.has_client ? (
          <>
            <Button compact color="bad" onClick={() => act('sendtoprison')}>
              Prison
            </Button>{' '}
            <Button compact onClick={() => act('sendbacktolobby')}>
              Send back to Lobby
            </Button>
          </>
        ) : null}
      </Box>
      {data.has_client ? (
        <>
          <Box bold mb="2px">
            Mute:
          </Box>
          <Box mb={1}>
            <MuteButton
              data={data}
              act={act}
              mask={data.mute_mask_ic}
              label="IC"
            />{' '}
            <MuteButton
              data={data}
              act={act}
              mask={data.mute_mask_ooc}
              label="OOC"
            />{' '}
            <MuteButton
              data={data}
              act={act}
              mask={data.mute_mask_looc}
              label="LOOC"
            />{' '}
            <MuteButton
              data={data}
              act={act}
              mask={data.mute_mask_pray}
              label="PRAY"
            />{' '}
            <MuteButton
              data={data}
              act={act}
              mask={data.mute_mask_adminhelp}
              label="ADMINHELP"
            />{' '}
            <MuteButton
              data={data}
              act={act}
              mask={data.mute_mask_deadchat}
              label="DEADCHAT"
            />{' '}
            <MuteButton
              data={data}
              act={act}
              mask={data.mute_mask_all}
              label="Toggle All"
            />
          </Box>
        </>
      ) : null}
    </Section>
  );
};

const NavigationSection = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section title="Navigation & Messages">
      <Box mb={1}>
        <Button compact onClick={() => act('jumpto')}>
          Jump to
        </Button>{' '}
        <Button compact onClick={() => act('getmob')}>
          Get
        </Button>{' '}
        <Button compact onClick={() => act('sendmob')}>
          Send To
        </Button>
      </Box>
      <Box>
        {data.can_event ? (
          <>
            <Button compact onClick={() => act('traitor')}>
              Traitor panel
            </Button>{' '}
          </>
        ) : null}
        <Button compact onClick={() => act('narrateto')}>
          Narrate to
        </Button>{' '}
        <Button compact onClick={() => act('subtlemessage')}>
          Subtle message
        </Button>{' '}
        <Button compact onClick={() => act('forcespeech')}>
          Forcesay
        </Button>
      </Box>
    </Section>
  );
};

const TransformationSection = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  if (!data.has_client || data.is_newplayer) {
    return null;
  }
  return (
    <Section title="Transformation">
      <Box mb={1}>
        {data.is_small ? (
          <Box inline bold>
            Monkeyized
          </Box>
        ) : (
          <Button compact onClick={() => act('turn_monkey')}>
            Monkeyize
          </Button>
        )}{' '}
        {data.is_corgi ? (
          <Box inline bold>
            Corgized
          </Box>
        ) : (
          <Button compact onClick={() => act('corgione')}>
            Corgize
          </Button>
        )}{' '}
        {data.is_ai ? (
          <Box inline bold>
            Is an AI
          </Box>
        ) : data.is_human ? (
          <>
            <Button compact onClick={() => act('turn_ai')}>
              Make AI
            </Button>{' '}
            <Button compact onClick={() => act('turn_robot')}>
              Make Robot
            </Button>{' '}
            <Button compact onClick={() => act('turn_alien')}>
              Make Alien
            </Button>
          </>
        ) : null}{' '}
        <Button compact onClick={() => act('makeanimal')}>
          {data.is_animal ? 'Re-Animalize' : 'Animalize'}
        </Button>{' '}
        <Button compact onClick={() => act('respawn')}>
          Respawn
        </Button>
      </Box>
    </Section>
  );
};

const DnaSection = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  if (!data.dna_cells || data.dna_cells.length === 0) {
    return null;
  }
  // Render in rows of 5; total = 145 cells.
  const cells = data.dna_cells;
  const rows: DnaCell[][] = [];
  for (let i = 0; i < cells.length; i += 5) {
    rows.push(cells.slice(i, i + 5));
  }
  const color_for = (state: DnaCell['state']) => {
    if (state === 'active') return 'good';
    if (state === 'blocked') return 'average';
    if (state === 'inactive') return 'bad';
    return undefined;
  };
  return (
    <Section title="DNA Blocks">
      <Box style={{ fontFamily: 'monospace' }}>
        {rows.map((row, rowIdx) => (
          <Stack key={rowIdx}>
            <Stack.Item basis="38px">
              <Box color="label" textAlign="right">
                {rowIdx * 5}
              </Box>
            </Stack.Item>
            {row.map((c) => (
              <Stack.Item key={c.block} basis="120px">
                {c.name ? (
                  <Button
                    compact
                    fluid
                    color={color_for(c.state)}
                    tooltip={c.tname ?? undefined}
                    onClick={() => act('togmutate', { block: c.block })}
                  >
                    {c.name}
                    <sub>{c.block}</sub>
                  </Button>
                ) : (
                  <Box color="label" textAlign="center">
                    {c.block}
                  </Box>
                )}
              </Stack.Item>
            ))}
          </Stack>
        ))}
      </Box>
    </Section>
  );
};

const RudimentaryTransformationSection = (props: {
  data: Data;
  act: ActFn;
}) => {
  const { data, act } = props;
  if (!data.has_client || data.is_newplayer) {
    return null;
  }
  return (
    <Section title="Rudimentary Transformation">
      <Box italic color="label" mb={1}>
        These transformations create a new mob type and copy stuff over — they
        don't account for MMIs and similar mob-specific things. Prefer the
        buttons in Transformation when possible.
      </Box>
      <Box mb="2px">
        <SimpleMakeButton act={act} kind="observer" label="Observer" />
      </Box>
      {RUDIMENTARY_GROUPS.map((group) => (
        <Box key={group.title} mt={1}>
          <Box mb="2px" color="label">
            {group.title}:
          </Box>
          {group.rows.map((row, i) => (
            <Box key={i} mb="2px">
              {row.map((entry, j) => (
                <SimpleMakeButton
                  key={`${entry.kind}-${entry.species ?? ''}-${j}`}
                  act={act}
                  kind={entry.kind}
                  species={entry.species}
                  label={entry.label}
                />
              ))}
            </Box>
          ))}
        </Box>
      ))}
    </Section>
  );
};

type MakeEntry = { kind: string; label: string; species?: string };
type MakeGroup = { title: string; rows: MakeEntry[][] };

const RUDIMENTARY_GROUPS: MakeGroup[] = [
  {
    title: 'Xenos',
    rows: [
      [
        { kind: 'larva', label: 'Larva' },
        { kind: 'human', species: 'Xenomorph Drone', label: 'Drone' },
        { kind: 'human', species: 'Xenomorph Hunter', label: 'Hunter' },
        { kind: 'human', species: 'Xenomorph Sentinel', label: 'Sentinel' },
        { kind: 'human', species: 'Xenomorph Queen', label: 'Queen' },
      ],
    ],
  },
  {
    title: 'Crew',
    rows: [
      [
        { kind: 'human', label: 'Human' },
        { kind: 'human', species: 'Unathi', label: 'Unathi' },
        { kind: 'human', species: 'Tajaran', label: 'Tajaran' },
        { kind: 'human', species: 'Skrell', label: 'Skrell' },
      ],
      [
        { kind: 'nymph', label: 'Nymph' },
        { kind: 'human', species: 'Diona', label: 'Diona' },
      ],
    ],
  },
  {
    title: 'Slime',
    rows: [
      [
        { kind: 'slime', label: 'Baby' },
        { kind: 'adultslime', label: 'Adult' },
      ],
      [
        { kind: 'monkey', label: 'Monkey' },
        { kind: 'robot', label: 'Cyborg' },
        { kind: 'cat', label: 'Cat' },
        { kind: 'runtime', label: 'Runtime' },
        { kind: 'corgi', label: 'Corgi' },
        { kind: 'ian', label: 'Ian' },
        { kind: 'crab', label: 'Crab' },
        { kind: 'coffee', label: 'Coffee' },
      ],
    ],
  },
  {
    title: 'Construct',
    rows: [
      [
        { kind: 'constructarmoured', label: 'Armoured' },
        { kind: 'constructbuilder', label: 'Builder' },
        { kind: 'constructwraith', label: 'Wraith' },
        { kind: 'shade', label: 'Shade' },
      ],
    ],
  },
];

const ThunderdomeSection = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  if (!data.has_client) return null;
  return (
    <Section title="Thunderdome">
      <Button compact onClick={() => act('tdome1')}>
        Thunderdome 1
      </Button>{' '}
      <Button compact onClick={() => act('tdome2')}>
        Thunderdome 2
      </Button>{' '}
      <Button compact onClick={() => act('tdomeadmin')}>
        Admin
      </Button>{' '}
      <Button compact onClick={() => act('tdomeobserve')}>
        Observer
      </Button>
    </Section>
  );
};

const LanguageSection = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section title="Languages">
      <Stack wrap>
        {data.languages.map((l) => (
          <Stack.Item key={l.key}>
            <Button
              compact
              color={l.known ? 'good' : 'bad'}
              onClick={() => act('toglang', { lang: l.key })}
            >
              {l.key}
            </Button>
          </Stack.Item>
        ))}
      </Stack>
    </Section>
  );
};

export const AdminEditPlayer = () => {
  const { data, act } = useBackend<Data>();
  return (
    <Window width={820} height={780} title={`Edit Player: ${data.key}`}>
      <Window.Content scrollable>
        <HeaderSection data={data} act={act} />
        <ModerationSection data={data} act={act} />
        <NavigationSection data={data} act={act} />
        <TransformationSection data={data} act={act} />
        <DnaSection data={data} act={act} />
        <RudimentaryTransformationSection data={data} act={act} />
        <ThunderdomeSection data={data} act={act} />
        <LanguageSection data={data} act={act} />
      </Window.Content>
    </Window>
  );
};
