// The shapeshift panel: the appearance commands of a shapeshifter (body shape,
// hair, colours, ears, tail, wings, gender and the forms) in one console
// window, with a preview of how the mob looks now. The server lists the groups
// and the present values, so a new command is a row in the DM list and no
// change here.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  ColorBox,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import type { ShapeshiftPanelActions } from './generated/ShapeshiftPanel';

type Row = {
  id: string;
  label: string;
  desc: string;
  action: string;
  value: string | null;
  swatch: string | null;
  enabled: BooleanLike;
  why: string | null;
};

type Group = {
  title: string;
  rows: Row[];
};

type Data = {
  name: string;
  preview: string | null;
  groups: Group[];
};

const CommandRow = (props: { row: Row }) => {
  const { act } = useBackend<Data, ShapeshiftPanelActions>();
  const { row } = props;
  return (
    <LabeledList.Item
      label={row.label}
      buttons={
        <Button
          disabled={!row.enabled}
          tooltip={row.enabled ? row.desc : row.why || row.desc}
          onClick={() => act('shift_do', { action: row.id })}
        >
          {row.action}
        </Button>
      }
    >
      {!!row.swatch && <ColorBox color={row.swatch} mr={1} />}
      <Box inline>{row.value ?? ''}</Box>
    </LabeledList.Item>
  );
};

export const ShapeshiftPanel = () => {
  const { data } = useBackend<Data, ShapeshiftPanelActions>();
  const { name, preview, groups } = data;
  return (
    <Window width={640} height={560} title="Shapeshift" theme="console">
      <Window.Content scrollable>
        {!groups.length && <NoticeBox>There is nothing to change.</NoticeBox>}
        {!!groups.length && (
          <Stack>
            <Stack.Item basis="30%">
              <Section title={name} textAlign="center">
                {!!preview && (
                  <img
                    alt="Preview"
                    src={`data:image/png;base64,${preview}`}
                    style={{
                      imageRendering: 'pixelated',
                      width: '128px',
                      height: '128px',
                    }}
                  />
                )}
              </Section>
            </Stack.Item>
            <Stack.Item grow>
              <Stack vertical>
                {groups.map((group) => (
                  <Stack.Item key={group.title}>
                    <Section title={group.title}>
                      <LabeledList>
                        {group.rows.map((row) => (
                          <CommandRow key={row.id} row={row} />
                        ))}
                      </LabeledList>
                    </Section>
                  </Stack.Item>
                ))}
              </Stack>
            </Stack.Item>
          </Stack>
        )}
      </Window.Content>
    </Window>
  );
};
