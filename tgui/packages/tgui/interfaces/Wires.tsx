import 'tgui/styles/interfaces/Wires.scss';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Color } from 'tgui-core/color';
import { Box, Section, Stack } from 'tgui-core/components';
import { classes } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';
import type { WiresActions, WiresData } from './generated/Wires';

export type WireData = WiresData;
export type Wire = WireData['wires'][number];

export const Wires = (props) => {
  const { data } = useBackend<WireData, WiresActions>();
  const { wires = [] } = data;

  return (
    <Window width={500} height={150 + wires.length * 40}>
      <Window.Content>
        <Stack vertical fill>
          <Stack.Item grow>
            <WiresWires />
          </Stack.Item>
          <Stack.Item>
            <WiresStatus />
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};

const WIRE_COLOR_HEX: Record<string, string> = {
  red: '#ff0000',
  blue: '#0000ff',
  green: '#008000',
  yellow: '#ffff00',
  orange: '#ffa500',
  pink: '#ffc0cb',
  purple: '#800080',
  cyan: '#00ffff',
  aqua: '#00ffff',
  black: '#000000',
  white: '#ffffff',
  grey: '#808080',
  gray: '#808080',
  brown: '#a52a2a',
  gold: '#ffd700',
  silver: '#c0c0c0',
  violet: '#ee82ee',
  magenta: '#ff00ff',
  lime: '#00ff00',
  teal: '#008080',
  navy: '#000080',
  maroon: '#800000',
  olive: '#808000',
  indigo: '#4b0082',
  salmon: '#fa8072',
  crimson: '#dc143c',
  beige: '#f5f5dc',
  khaki: '#f0e68c',
  tan: '#d2b48c',
};

export const standardizeColor = (color: string): string => {
  // A page without OffscreenCanvas (an older embedded browser, the test DOM): the wire colour names DM uses, else grey.
  if (typeof OffscreenCanvas === 'undefined') {
    if (/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(color)) return color;
    return WIRE_COLOR_HEX[color.toLowerCase()] ?? '#808080';
  }
  const canvas = new OffscreenCanvas(1, 1);
  const ctx = canvas.getContext('2d');
  if (ctx) {
    ctx.fillStyle = color;
    return ctx.fillStyle;
  } else {
    return '#000000';
  }
};

export const WiresWires = (props) => {
  const { data } = useBackend<WireData, WiresActions>();

  const { wires = [] } = data;
  return (
    <Section scrollable fill>
      <Stack vertical>
        {wires.length === 0 && <EmptyState>No wires are exposed.</EmptyState>}
        {wires.map((wire) => {
          return (
            <Stack.Item key={wire.seen_color}>
              <WireComponent wire={wire} />
            </Stack.Item>
          );
        })}
      </Stack>
    </Section>
  );
};

export const WiresStatus = (props) => {
  const { data } = useBackend<WireData, WiresActions>();
  const statuses = data.status || [];

  return statuses.length ? (
    <Section>
      {statuses.map((status) => (
        <Box key={status} color="lightgray" mt={0.1}>
          {status}
        </Box>
      ))}
    </Section>
  ) : null;
};

export const WireComponent = ({ wire }: { wire: Wire }) => {
  const { act } = useBackend<WireData, WiresActions>();
  const color = standardizeColor(wire.seen_color);
  const darkened = Color.fromHex(color).darken(30).toString();

  return (
    <Stack align="center">
      <Stack.Item grow>
        <Stack
          align="center"
          className="Wires__Cursor__Wirecutters"
          onClick={() => act('cut', { wire: wire.color })}
        >
          <Stack.Item grow>
            <Box
              style={{
                background: `linear-gradient(${color} 75%,  ${darkened} 75% 100%)`,
                textTransform: 'capitalize',
              }}
              className="Wires__Outlined"
              height={2}
              color="white"
              pl={1}
            >
              {wire.color_name}
            </Box>
          </Stack.Item>
          {wire.cut ? <Stack.Item>&nbsp;&nbsp;&nbsp;&nbsp;</Stack.Item> : null}
          <Stack.Item grow ml={-1}>
            <Box
              style={{
                background: `linear-gradient(${color} 75%,  ${darkened} 75% 100%)`,
              }}
              className="Wires__Outlined"
              height={2}
              color="white"
              textAlign="right"
              italic
              pr={1}
            >
              {wire.wire ? `(${wire.wire})` : null}
            </Box>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item ml={-1}>
        <Box
          className="Wires__Terminal Wires__Cursor__Multitool"
          height={2.4}
          width={5}
          onClick={() => act('pulse', { wire: wire.color })}
        />
      </Stack.Item>
      <Stack.Item ml={-3}>
        <Box
          className={classes([
            'Wires__Cursor__Signaller Wires__Signaller',
            wire.attached ? 'active' : null,
          ])}
          height={2.4}
          width={3}
          onClick={() => act('attach', { wire: wire.color })}
        />
      </Stack.Item>
    </Stack>
  );
};
