// DQAdd — Trait picker UI. Three columns (positive/neutral/negative), point + max-trait
// budget header, blood color swatch, click-to-add from the pool, click-to-remove from the
// selected list.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  ColorBox,
  Input,
  Section,
  Stack,
} from 'tgui-core/components';
import type { EditorProps } from './index';

type TraitData = {
  blood_color: string;
  traits_cheating: number;
  starting_trait_points: number;
  max_traits: number;
  points_used: number;
  total_traits: number;
  pos_traits: string[];
  neu_traits: string[];
  neg_traits: string[];
};

type TraitStatic = {
  all_traits: Record<
    string,
    { name: string; desc: string; cost: number; category: number }
  >;
  positive_traits: string[];
  neutral_traits: string[];
  negative_traits: string[];
};

const send = (
  act: ReturnType<typeof useBackend>['act'],
  action: string,
  params: Record<string, unknown>,
) => act('dq_editor_action', { editor: 'trait_picker', action, params });

const COLUMN_COLOR: Record<'pos' | 'neu' | 'neg', string> = {
  pos: 'good',
  neu: 'label',
  neg: 'bad',
};

export const TraitPicker = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as TraitData;
  const s = (staticData ?? {}) as TraitStatic;
  const [search, setSearch] = useState('');

  if (!s.all_traits) return null;

  const pointsRemaining = d.starting_trait_points - d.points_used;
  const traitsRemaining = d.max_traits - d.total_traits;

  return (
    <Box>
      <Box
        mb={1}
        px={1}
        py={0.5}
        style={{
          backgroundColor: 'rgba(255,255,255,0.05)',
          borderRadius: '2px',
        }}
      >
        <Stack align="center">
          <Stack.Item grow>
            <Box fontSize="1.1em">
              <Box inline color={pointsRemaining < 0 ? 'bad' : 'good'} bold>
                {pointsRemaining}
              </Box>{' '}
              points left ({d.points_used}/{d.starting_trait_points} spent) ·{' '}
              <Box inline color={traitsRemaining < 0 ? 'bad' : 'good'} bold>
                {traitsRemaining}
              </Box>{' '}
              trait slots left ({d.total_traits}/{d.max_traits})
            </Box>
          </Stack.Item>
          <Stack.Item>
            <Stack inline align="center">
              <Stack.Item>Blood:</Stack.Item>
              <Stack.Item>
                <ColorBox color={d.blood_color} />
              </Stack.Item>
              <Stack.Item>
                <Button
                  icon="palette"
                  onClick={() => send(act, 'set_blood_color', {})}
                >
                  {d.blood_color}
                </Button>
              </Stack.Item>
            </Stack>
          </Stack.Item>
        </Stack>
        <Box mt={1}>
          <Input
            fluid
            placeholder="Search traits…"
            value={search}
            onChange={(v) => setSearch(v)}
          />
        </Box>
      </Box>
      <Stack>
        <Stack.Item grow basis={0}>
          <TraitColumn
            label="Positive"
            categoryKey="pos"
            available={s.positive_traits}
            selected={d.pos_traits}
            allTraits={s.all_traits}
            search={search}
          />
        </Stack.Item>
        <Stack.Item grow basis={0}>
          <TraitColumn
            label="Neutral"
            categoryKey="neu"
            available={s.neutral_traits}
            selected={d.neu_traits}
            allTraits={s.all_traits}
            search={search}
          />
        </Stack.Item>
        <Stack.Item grow basis={0}>
          <TraitColumn
            label="Negative"
            categoryKey="neg"
            available={s.negative_traits}
            selected={d.neg_traits}
            allTraits={s.all_traits}
            search={search}
          />
        </Stack.Item>
      </Stack>
    </Box>
  );
};

const TraitColumn = ({
  label,
  categoryKey,
  available,
  selected,
  allTraits,
  search,
}: {
  label: string;
  categoryKey: 'pos' | 'neu' | 'neg';
  available: string[];
  selected: string[];
  allTraits: TraitStatic['all_traits'];
  search: string;
}) => {
  const { act } = useBackend();
  const selectedSet = new Set(selected);
  const lcSearch = search.trim().toLowerCase();
  const matches = (path: string) => {
    if (!lcSearch) return true;
    const meta = allTraits[path];
    if (!meta) return false;
    return (
      meta.name.toLowerCase().includes(lcSearch) ||
      meta.desc.toLowerCase().includes(lcSearch)
    );
  };
  const color = COLUMN_COLOR[categoryKey];

  return (
    <Section
      title={label}
      style={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      <Box style={{ maxHeight: '70vh', overflowY: 'auto' }}>
        <Box mb={0.25} bold color={color} fontSize="0.85em">
          Selected
        </Box>
        {selected.length === 0 && (
          <Box italic mb={0.5} fontSize="0.85em" color="label">
            None
          </Box>
        )}
        {selected.map((path) => {
          const meta = allTraits[path];
          if (!meta) return null;
          return (
            <TraitRow
              key={path}
              meta={meta}
              action="remove_trait"
              categoryKey={categoryKey}
              path={path}
              icon="times"
              iconColor="bad"
            />
          );
        })}
        <Box mt={0.5} mb={0.25} bold color={color} fontSize="0.85em">
          Available
        </Box>
        {available
          .filter((path) => !selectedSet.has(path) && matches(path))
          .map((path) => {
            const meta = allTraits[path];
            if (!meta) return null;
            return (
              <TraitRow
                key={path}
                meta={meta}
                action="add_trait"
                categoryKey={categoryKey}
                path={path}
                icon="plus"
                iconColor={color}
              />
            );
          })}
      </Box>
    </Section>
  );
};

const TraitRow = ({
  meta,
  action,
  categoryKey,
  path,
  icon,
  iconColor,
}: {
  meta: { name: string; desc: string; cost: number; category: number };
  action: 'add_trait' | 'remove_trait';
  categoryKey: 'pos' | 'neu' | 'neg';
  path: string;
  icon: string;
  iconColor: string;
}) => {
  const { act } = useBackend();
  const [open, setOpen] = useState(false);
  const costStr = meta.cost === 0 ? '0' : meta.cost > 0 ? `+${meta.cost}` : `${meta.cost}`;
  return (
    <Box mb={0.1} fontSize="0.85em">
      <Box style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
        <Button
          compact
          icon={icon}
          color={iconColor}
          onClick={() =>
            send(act, action, {
              category: categoryKey,
              trait_path: path,
            })
          }
        />
        <Box
          style={{
            cursor: 'pointer',
            flex: 1,
            minWidth: 0,
            display: 'flex',
            alignItems: 'baseline',
            gap: '4px',
          }}
          onClick={() => setOpen((v) => !v)}
        >
          <Box
            bold
            style={{
              flex: 1,
              minWidth: 0,
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {meta.name}
          </Box>
          <Box color="label" style={{ flex: '0 0 auto' }}>
            ({costStr})
          </Box>
        </Box>
      </Box>
      {open && (
        <Box color="label" fontSize="0.85em" pl={3} pr={1}>
          {meta.desc}
        </Box>
      )}
    </Box>
  );
};
