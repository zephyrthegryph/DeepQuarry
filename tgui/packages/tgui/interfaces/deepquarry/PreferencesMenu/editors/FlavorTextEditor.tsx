// DQAdd — Flavor text editor. Body and robot flavor each show a single tall
// textarea with a button-row above to swap between zones (general/head/face/
// eyes/torso/arms/hands/legs/feet for body; Default + each robot module for
// robot). The previous grid-of-tiny-textareas layout fragmented the editing
// experience and the boxes were too short to write a sentence in.

import { useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Button, TextArea } from 'tgui-core/components';
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

  return (
    <Box>
      {mode === 'robot' ? (
        <>
          <Box bold mb={0.5} color="label">Robot Flavor</Box>
          <ZoneSwitcher
            zones={robotZones}
            getValue={(z) => d.flavour_texts_robot?.[z] ?? ''}
            actionKey="set_robot_flavor"
            paramKey="module"
          />
        </>
      ) : (
        <>
          <Box bold mb={0.5} color="label">Body Flavor</Box>
          <ZoneSwitcher
            zones={zones}
            getValue={(z) => d.flavor_texts?.[z] ?? ''}
            actionKey="set_flavor"
            paramKey="zone"
          />
        </>
      )}
    </Box>
  );
};

/// Renders a wrap-able row of zone-select buttons and a single large textarea
/// for the currently-selected zone. Each zone's text persists on the server
/// even when not displayed; the user just sees one zone at a time.
const ZoneSwitcher = ({
  zones,
  getValue,
  actionKey,
  paramKey,
}: {
  zones: string[];
  getValue: (zone: string) => string;
  actionKey: string;
  paramKey: string;
}) => {
  const { act } = useBackend();
  const [selected, setSelected] = useState<string>(zones[0] ?? '');
  const value = getValue(selected);
  const [draft, setDraft] = useState(value);

  // When the user switches zones (or the server pushes a new value for the
  // current zone), resync the draft buffer. Without this, an out-of-band
  // server update would silently drop onto the editor's draft.
  useEffect(() => {
    setDraft(getValue(selected));
  }, [selected, value]);

  return (
    <Box>
      <Box
        mb={0.5}
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '4px',
        }}
      >
        {zones.map((z) => (
          <Button
            key={z}
            compact
            selected={z === selected}
            onClick={() => setSelected(z)}
          >
            {z.charAt(0).toUpperCase() + z.slice(1)}
          </Button>
        ))}
      </Box>
      <TextArea
        fluid
        height="8em"
        value={draft}
        onChange={(v) => setDraft(v)}
        onBlur={() => {
          if (draft !== value) {
            send(act, actionKey, { [paramKey]: selected, text: draft });
          }
        }}
      />
    </Box>
  );
};
