import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Icon, LabeledList, Section, Stack } from 'tgui-core/components';
import type {
  DockingConsoleMultiActions,
  DockingConsoleMultiData,
} from './generated/DockingConsoleMulti';
import { DockStatus } from './EmbeddedController/EmbeddedControllerHelpers';

/**
 * Shockingly, the multi docking console is the simplest docking console.
 * It has no functionality except to display the status of multiple airlocks,
 * for bigger shuttles.
 * Replaces multi_docking_console.tmpl
 */
const DockingConsoleMultiContent = () => {
  const { data } = useBackend<
    DockingConsoleMultiData,
    DockingConsoleMultiActions
  >();

  const { docking_status } = data;

  return (
    <>
      <Section title="Docking Status">
        <DockStatus docking_status={docking_status} override_enabled={false} />
      </Section>
      <Section title="Airlocks">
        {data.airlocks.length ? (
          <LabeledList>
            {data.airlocks.map((airlock) => (
              <LabeledList.Item
                color={airlock.override_enabled ? 'bad' : 'good'}
                key={airlock.name}
                label={airlock.name}
              >
                {airlock.override_enabled ? 'OVERRIDE ENABLED' : 'STATUS OK'}
              </LabeledList.Item>
            ))}
          </LabeledList>
        ) : (
          <Stack height="100%" mt="0.5em">
            <Stack.Item grow align="center" textAlign="center" color="bad">
              <Icon name="door-closed" mb="0.5rem" size={5} />
              <br />
              No airlocks found.
            </Stack.Item>
          </Stack>
        )}
      </Section>
    </>
  );
};

export const DockingConsoleMulti = () => (
  <Window width={500} height={400}>
    <Window.Content>
      <DockingConsoleMultiContent />
    </Window.Content>
  </Window>
);
