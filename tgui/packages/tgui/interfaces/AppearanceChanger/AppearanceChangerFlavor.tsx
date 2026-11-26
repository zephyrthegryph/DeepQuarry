import { useBackend } from 'tgui/backend';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import { capitalize } from 'tgui-core/string';
import type { AppearanceChangerActions } from '../generated/AppearanceChanger';
import type { Data } from './types';

export const AppearanceChangerFlavor = (props) => {
  const { act, data } = useBackend<Data, AppearanceChangerActions>();
  const { flavor_text } = data;

  return (
    <Section title="Flavor Text" fill scrollable>
      <LabeledList>
        {Object.keys(flavor_text).map((key) => (
          <LabeledList.Item key={key} label={capitalize(key)}>
            <Button
              icon="pen"
              onClick={() =>
                act('flavor_text', {
                  target: key,
                })
              }
            >
              Edit
            </Button>
            <br />
            <Box preserveWhitespace style={{ wordBreak: 'break-all' }}>
              {flavor_text[key]}
            </Box>
          </LabeledList.Item>
        ))}
      </LabeledList>
    </Section>
  );
};
