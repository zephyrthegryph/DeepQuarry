import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Stack } from 'tgui-core/components';
import type {
  RobotSleeperActions,
  RobotSleeperData,
} from '../generated/RobotSleeper';
import { CargoCompartment } from './SubElements/CargoCompartment';
import { InjectorPanel } from './SubElements/InjectorPanel';
import { SleeperStatus } from './SubElements/SleeperStatus';

export const RobotSleeper = (props) => {
  const { data } = useBackend<RobotSleeperData, RobotSleeperActions>();

  const { theme, chems, delivery, name } = data;
  return (
    <Window width={450} height={500} theme={theme}>
      <Window.Content>
        <Stack vertical fill>
          {!!chems && (
            <Stack.Item>
              <InjectorPanel robotChems={chems} />
            </Stack.Item>
          )}
          {!!delivery && (
            <Stack.Item>
              <CargoCompartment />
            </Stack.Item>
          )}
          <Stack.Item grow>
            <SleeperStatus name={name ?? 'Unknown'} />
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
