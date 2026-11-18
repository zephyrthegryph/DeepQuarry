import { useBackend } from 'tgui/backend';
import { Button, Section, Table } from 'tgui-core/components';
import { EmptyState } from '../common/EmptyState';
import type { PowerMonitorActions } from '../generated/PowerMonitor';
import { PowerMonitorFocus } from './PowerMonitorFocus';
import type { Data } from './types';

export const PowerMonitorContent = (props) => {
  const { act, data } = useBackend<Data, PowerMonitorActions>();

  const { all_sensors, focus } = data;

  if (focus) {
    return <PowerMonitorFocus focus={focus} />;
  }

  let body: React.JSX.Element = (
    <EmptyState>
      No power sensors found. Scan again once one is built.
    </EmptyState>
  );

  if (all_sensors?.length) {
    body = (
      <Table>
        {all_sensors.map((sensor) => (
          <Table.Row key={sensor.name}>
            <Table.Cell>
              <Button
                icon={sensor.alarm ? 'bell' : 'sign-in-alt'}
                onClick={() => act('setsensor', { id: sensor.name })}
              >
                {sensor.name}
              </Button>
            </Table.Cell>
          </Table.Row>
        ))}
      </Table>
    );
  }

  return (
    <Section
      title="Power Sensors"
      buttons={
        <Button icon="undo" onClick={() => act('refresh')}>
          Scan For Sensors
        </Button>
      }
    >
      {body}
    </Section>
  );
};
