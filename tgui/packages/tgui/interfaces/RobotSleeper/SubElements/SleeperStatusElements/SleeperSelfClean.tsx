import { useBackend } from 'tgui/backend';
import { Box, Stack } from 'tgui-core/components';
import type {
  RobotSleeperActions,
  RobotSleeperData,
} from '../../../generated/RobotSleeper';
import { filterFuel } from '../../functions';

export const SleeperSelfClean = (props) => {
  const { data } = useBackend<RobotSleeperData, RobotSleeperActions>();
  const { cleaning, items_preserved, contents } = data;

  const perservedCount = items_preserved.length;
  const cleanableCount = filterFuel(contents, items_preserved).length;

  return (
    <>
      {!!cleaning && (
        <Stack.Item>
          {cleanableCount ? (
            <>
              <Box color="red" inline>
                Self-cleaning mode.
              </Box>
              <Box inline preserveWhitespace>
                {`${cleanableCount} object${cleanableCount > 1 ? 's' : ''} remaining.`}
              </Box>
            </>
          ) : (
            <Box color="red">
              Self-cleaning done. Eject remaining objects now.
            </Box>
          )}
        </Stack.Item>
      )}
      {!!perservedCount && (
        <Stack.Item>
          <Box color="red">
            {`${perservedCount} uncleanable object${perservedCount > 1 ? 's' : ''}.`}
          </Box>
        </Stack.Item>
      )}
      {!!cleaning || (!!perservedCount && <Stack.Divider />)}
    </>
  );
};
