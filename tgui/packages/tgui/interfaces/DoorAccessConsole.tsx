import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type {
  DoorAccessConsoleActions,
  DoorAccessConsoleData,
} from './generated/DoorAccessConsole';
import { PanelOpen } from './EmbeddedController/PanelOpen';

/**
 * Airlock but without anything other than doors. Separates clean rooms.
 * Replaces door_access_console.tmpl
 */
const DoorAccessConsoleContent = () => {
  const { act, data } = useBackend<
    DoorAccessConsoleData,
    DoorAccessConsoleActions
  >();

  const { interior_status, exterior_status, panel_open } = data;

  const interiorOpen =
    interior_status.state === 'open' || exterior_status.state === 'closed';
  const exteriorOpen =
    exterior_status.state === 'open' || interior_status.state === 'closed';

  return (
    <>
      <Section
        title="Status"
        buttons={
          <Stack>
            {/* Interior Button */}
            <Stack.Item>
              <Button
                icon={interiorOpen ? 'arrow-left' : 'exclamation-triangle'}
                onClick={() => {
                  act(interiorOpen ? 'cycle_ext_door' : 'force_ext');
                }}
              >
                {interiorOpen ? 'Cycle To Exterior' : 'Lock Exterior Door'}
              </Button>
            </Stack.Item>
            {/* Exterior Button */}
            <Stack.Item>
              <Button
                icon={exteriorOpen ? 'arrow-right' : 'exclamation-triangle'}
                onClick={() => {
                  act(exteriorOpen ? 'cycle_int_door' : 'force_int');
                }}
              >
                {exteriorOpen ? 'Cycle To Interior' : 'Lock Interior Door'}
              </Button>
            </Stack.Item>
          </Stack>
        }
      >
        <LabeledList>
          <LabeledList.Item label="Exterior Door Status">
            {exterior_status.state === 'closed' ? 'Locked' : 'Open'}
          </LabeledList.Item>
          <LabeledList.Item label="Interior Door Status">
            {interior_status.state === 'closed' ? 'Locked' : 'Open'}
          </LabeledList.Item>
        </LabeledList>
      </Section>
      {!!panel_open && <PanelOpen />}
    </>
  );
};

export const DoorAccessConsole = () => (
  <Window width={500} height={400}>
    <Window.Content>
      <DoorAccessConsoleContent />
    </Window.Content>
  </Window>
);
