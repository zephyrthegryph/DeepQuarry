import { useBackend } from 'tgui/backend';
import { Button, Divider, Section, Stack } from 'tgui-core/components';
import type { PaiChooseActions } from '../generated/PaiChoose';
import { PreferenceEditColor } from '../PreferencesMenu/elements/ColorInput';
import { PaiPreview } from './PaiPreview';
import type { Data } from './types';

export const IconSection = (props) => {
  const { act, data } = useBackend<Data, PaiChooseActions>();
  const {
    sprite_datum_class,
    sprite_datum_size,
    selected_chassis,
    pai_color = '#ffffff',
  } = data;

  return (
    <Section
      title="Sprite"
      fill
      buttons={
        <Button disabled={!selected_chassis} onClick={() => act('confirm')}>
          Apply
        </Button>
      }
    >
      <Stack vertical fill>
        <Stack.Item>
          <Stack>
            <Stack.Item color="label">Color:</Stack.Item>
            <Stack.Item>
              <PreferenceEditColor
                onClose={(value) => act('change_color', { color: value })}
                tooltip="Choose your pAI's default glow colour."
                back_color={pai_color}
              />
            </Stack.Item>
          </Stack>
        </Stack.Item>
        <Divider />
        <PaiPreview
          icon={sprite_datum_class}
          size={sprite_datum_size}
          color={pai_color}
        />
      </Stack>
    </Section>
  );
};
