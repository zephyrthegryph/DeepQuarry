import { useBackend } from 'tgui/backend';
import { Button, Dropdown, Section, Stack } from 'tgui-core/components';
import type {
  RobotSleeperActions,
  RobotSleeperData,
} from '../../generated/RobotSleeper';

export const CargoCompartment = (props) => {
  const { act, data } = useBackend<RobotSleeperData, RobotSleeperActions>();
  const { delivery_lists, delivery_tag } = data;

  return (
    <Section fill title="Cargo Compartment">
      <Stack>
        <Stack.Item>
          <Dropdown
            onSelected={(value: string) =>
              act('deliveryslot', { value: value })
            }
            options={Object.keys(delivery_lists)}
            selected={delivery_tag}
          />
        </Stack.Item>
        <Stack.Item>
          <Button
            disabled={!delivery_lists[delivery_tag]?.length}
            onClick={() => act('slot_eject')}
          >
            Eject Slot
          </Button>
        </Stack.Item>
      </Stack>
    </Section>
  );
};
