import { useBackend } from 'tgui/backend';
import { Button, Divider, Section, Stack } from 'tgui-core/components';
import type { PaiChooseActions, PaiChooseData } from '../generated/PaiChoose';
import { PreferenceEditColor } from '../PreferencesMenu/elements/ColorInput';
import { PaiPreview } from './PaiPreview';

export const IconSection = (props) => {
  const { act, data } = useBackend<PaiChooseData, PaiChooseActions>();
  const { sprite_datum_class, sprite_datum_size, selected_chassis, pai_color } =
    data;

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
          icon={sprite_datum_class ?? undefined}
          size={sprite_datum_size ?? undefined}
          color={pai_color}
        />
      </Stack>
    </Section>
  );
};
