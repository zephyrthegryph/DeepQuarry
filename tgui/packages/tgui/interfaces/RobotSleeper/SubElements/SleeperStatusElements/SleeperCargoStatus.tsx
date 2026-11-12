import { Fragment } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Stack } from 'tgui-core/components';
import type {
  RobotSleeperActions,
  RobotSleeperData,
} from '../../../generated/RobotSleeper';
import { filterFuel, summarizeItems } from '../../functions';

export const SleeperCargoStatus = (props) => {
  const { data } = useBackend<RobotSleeperData, RobotSleeperActions>();
  const { deliveryslot_1, deliveryslot_2, deliveryslot_3, contents } = data;

  const cargoSlots = [deliveryslot_1, deliveryslot_2, deliveryslot_3];

  return (
    <>
      {cargoSlots.map((slot, index) => (
        <Fragment key={index}>
          <Stack.Item>
            <Box color="label">Cargo compartment slot: Cargo {index}.</Box>
          </Stack.Item>
          <Stack.Item>
            <Box color="label">{summarizeItems(slot)}</Box>
          </Stack.Item>
        </Fragment>
      ))}
      <Stack.Item>
        <Box color="red">Cargo compartment slot: Fuel.</Box>
      </Stack.Item>
      <Stack.Item>
        <Box color="red">
          {summarizeItems(filterFuel(contents, cargoSlots.flat()))}
        </Box>
      </Stack.Item>
      <Stack.Divider />
    </>
  );
};
