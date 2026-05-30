// AI liquid dispenser (slipper) — TGUI.
//
// Silicons or anyone with an unlocked panel can toggle activation and
// fire a foam puck. Locked panels prompt non-silicons to swipe ID.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Data = {
  area_name: string;
  locked: BooleanLike;
  is_silicon: BooleanLike;
  disabled: BooleanLike;
  uses: number;
  cooldown_on: BooleanLike;
  cooldown_timeleft: number;
};

export const AiSlipper = () => {
  const { data, act } = useBackend<Data>();
  const {
    area_name,
    locked,
    is_silicon,
    disabled,
    uses,
    cooldown_on,
    cooldown_timeleft,
  } = data;

  const lockedToUser = locked && !is_silicon;

  return (
    <Window width={420} height={220}>
      <Window.Content>
        <Section title={`AI Liquid Dispenser (${area_name})`}>
          {lockedToUser ? (
            <EmptyState>Swipe ID card to unlock control panel.</EmptyState>
          ) : (
            <LabeledList>
              <LabeledList.Item label="Dispenser">
                <Button
                  selected={!disabled}
                  icon={disabled ? 'power-off' : 'check'}
                  onClick={() => act('toggle_on')}
                >
                  {disabled ? 'Disabled' : 'Enabled'}
                </Button>
              </LabeledList.Item>
              <LabeledList.Item label="Uses Left">
                <Box inline bold>
                  {uses}
                </Box>
              </LabeledList.Item>
              <LabeledList.Item label="Fire">
                <Button
                  icon="bolt"
                  color="bad"
                  disabled={!!disabled || !!cooldown_on || uses <= 0}
                  onClick={() => act('toggle_use')}
                >
                  {cooldown_on
                    ? `Cooldown (${cooldown_timeleft}s)`
                    : 'Dispense'}
                </Button>
              </LabeledList.Item>
            </LabeledList>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
