import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, Section } from 'tgui-core/components';
import type {
  AtmosAlertConsoleActions,
  AtmosAlertConsoleData,
} from './generated/AtmosAlertConsole';

type Data = AtmosAlertConsoleData;

export const AtmosAlertConsole = (props) => {
  const { act, data } = useBackend<Data, AtmosAlertConsoleActions>();

  const { priority_alarms = [], minor_alarms = [] } = data;

  return (
    <Window width={350} height={300}>
      <Window.Content>
        <Section fill scrollable title="Alarms">
          <ul>
            {priority_alarms.length === 0 && (
              <li className="color-good">No Priority Alerts</li>
            )}
            {priority_alarms.map((alert) => (
              <li key={alert.name}>
                <Button
                  icon="times"
                  color="bad"
                  onClick={() => act('clear', { ref: alert.ref })}
                >
                  {alert.name}
                </Button>
              </li>
            ))}
            {minor_alarms.length === 0 && (
              <li className="color-good">No Minor Alerts</li>
            )}
            {minor_alarms.map((alert) => (
              <li key={alert.name}>
                <Button
                  icon="times"
                  color="average"
                  onClick={() => act('clear', { ref: alert.ref })}
                >
                  {alert.name}
                </Button>
              </li>
            ))}
          </ul>
        </Section>
      </Window.Content>
    </Window>
  );
};
