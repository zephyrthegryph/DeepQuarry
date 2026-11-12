import { useBackend } from 'tgui/backend';
import { NtosWindow } from 'tgui/layouts';
import { Button, LabeledList, Section } from 'tgui-core/components';
import type {
  NtosRevelationActions,
  NtosRevelationData,
} from './generated/NtosRevelation';

export const NtosRevelation = (props) => {
  const { act, data } = useBackend<NtosRevelationData, NtosRevelationActions>();
  const { armed } = data;
  return (
    <NtosWindow width={400} height={250} theme="syndicate">
      <NtosWindow.Content>
        <Section>
          <Button.Input
            fluid
            buttonText="Obfuscate Name..."
            onCommit={(value) =>
              act('PRG_obfuscate', {
                new_name: value,
              })
            }
            mb={1}
          />
          <LabeledList>
            <LabeledList.Item
              label="Payload Status"
              buttons={
                <Button
                  color={armed ? 'bad' : 'average'}
                  onClick={() => act('PRG_arm')}
                >
                  {armed ? 'ARMED' : 'DISARMED'}
                </Button>
              }
            />
          </LabeledList>
          <Button
            fluid
            bold
            textAlign="center"
            color="bad"
            disabled={!armed}
            onClick={() => act('PRG_activate')}
          >
            ACTIVATE
          </Button>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
