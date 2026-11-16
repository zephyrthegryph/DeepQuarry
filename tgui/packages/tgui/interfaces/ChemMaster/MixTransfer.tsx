import { useBackend } from 'tgui/backend';
import { modalOpen } from 'tgui/interfaces/common/ComplexModal';
import { Button, Stack } from 'tgui-core/components';
import { transferAmounts } from './constants';
import type { reagent } from './types';

/**
 * Whole-mix transfer buttons: `action` moves that many units of the mixture
 * as it is (every reagent in its share). No button picks one chemical out.
 */
export const MixTransfer = (props: {
  action: 'add' | 'remove';
  custom: 'addcustom' | 'removecustom';
  reagents: reagent[];
}) => {
  const { act } = useBackend();
  const { action, custom, reagents } = props;
  const total = reagents.reduce((sum, r) => sum + r.volume, 0);

  return (
    <Stack mb="4px">
      {transferAmounts.map((amount) => (
        <Stack.Item key={amount}>
          <Button mb="0" onClick={() => act(action, { amount })}>
            {amount}
          </Button>
        </Stack.Item>
      ))}
      <Stack.Item>
        <Button mb="0" onClick={() => act(action, { amount: total })}>
          All
        </Button>
      </Stack.Item>
      <Stack.Item>
        <Button mb="0" onClick={() => modalOpen(custom)}>
          Custom...
        </Button>
      </Stack.Item>
    </Stack>
  );
};
