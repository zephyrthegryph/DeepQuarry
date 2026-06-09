// Moneybag — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, LabeledList, Section } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Counts = {
  gold: number;
  silver: number;
  iron: number;
  diamond: number;
  phoron: number;
  uranium: number;
};

type Data = {
  counts: Counts;
};

const COIN_LABELS: Array<{ key: keyof Counts; label: string }> = [
  { key: 'gold', label: 'Gold' },
  { key: 'silver', label: 'Silver' },
  { key: 'iron', label: 'Metal' },
  { key: 'diamond', label: 'Diamond' },
  { key: 'phoron', label: 'Phoron' },
  { key: 'uranium', label: 'Uranium' },
];

export const Moneybag = () => {
  const { data, act } = useBackend<Data>();
  const counts = data.counts;
  const hasAny = COIN_LABELS.some((c) => counts[c.key] > 0);
  return (
    <Window width={360} height={300} title="Moneybag">
      <Window.Content>
        <Section title="Contents">
          {!hasAny ? (
            <EmptyState>The moneybag is empty.</EmptyState>
          ) : (
            <LabeledList>
              {COIN_LABELS.filter((c) => counts[c.key] > 0).map((c) => (
                <LabeledList.Item key={c.key} label={`${c.label} coins`}>
                  {counts[c.key]}{' '}
                  <Button
                    compact
                    onClick={() => act('remove', { coin: c.key })}
                  >
                    Remove one
                  </Button>
                </LabeledList.Item>
              ))}
            </LabeledList>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
