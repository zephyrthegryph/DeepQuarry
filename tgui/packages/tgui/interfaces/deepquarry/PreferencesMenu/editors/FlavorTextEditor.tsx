// DQAdd — Flavor text editor: a button list of the entries (General/Face/Body, or Default + each robot module), one text
// area beside it, and the text as examine prints it below.

import { useBackend } from 'tgui/backend';
import { Box, Button } from 'tgui-core/components';
import { type SwitcherEntry, TextSwitcher } from '../TextSwitcher';
import type { EditorProps } from './index';

type FlavorData = {
  flavor_texts: Record<string, string>;
  flavour_texts_robot: Record<string, string>;
  play_mode: 'human' | 'robot' | 'pai';
};

type FlavorStatic = {
  flavor_zones: string[];
  robot_modules: string[];
};

const send = (
  act: ReturnType<typeof useBackend>['act'],
  action: string,
  params: Record<string, unknown>,
) => act('dq_editor_action', { editor: 'flavor', action, params });

export const FlavorTextEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as FlavorData;
  const s = (staticData ?? {}) as FlavorStatic;
  const zones = s.flavor_zones ?? [];
  const robotZones = ['Default', ...(s.robot_modules ?? [])];
  const mode = d.play_mode ?? 'human';

  if (mode === 'pai') {
    return (
      <Box color="label" italic>
        pAIs use the card details under the Game tab — no body flavor needed.
      </Box>
    );
  }

  const robot = mode === 'robot';
  const shownZones = robot ? robotZones : zones;
  const texts = (robot ? d.flavour_texts_robot : d.flavor_texts) ?? {};
  const entries: SwitcherEntry[] = shownZones.map((z) => ({
    key: z,
    label: z.charAt(0).toUpperCase() + z.slice(1),
    value: texts[z] ?? '',
  }));
  return (
    <TextSwitcher
      entries={entries}
      onCommit={(zone, text) =>
        robot
          ? send(act, 'set_robot_flavor', { module: zone, text })
          : send(act, 'set_flavor', { zone, text })
      }
      actions={
        robot ? undefined : (
          <Button
            compact
            icon="eye"
            tooltip="Print it in your chat the way an examining player sees it"
            onClick={() => act('dq_inspect_flavor')}
          >
            Show in chat as examined
          </Button>
        )
      }
      formatted
      buttonsBelow
    />
  );
};
