import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Stack } from 'tgui-core/components';
import type {
  RobotChooseActions,
  RobotChooseData,
} from '../generated/RobotChoose';
import { IconSection } from './IconSection';
import { ModuleSection } from './ModuleSection';
import { SpriteSection } from './SpriteSection';

export const RobotChoose = (props) => {
  const { data } = useBackend<RobotChooseData, RobotChooseActions>();

  const {
    possible_modules,
    whitelisted_modules,
    possible_sprites,
    selected_module,
    sprite_datum,
    theme,
    currentName,
    mind_name,
    isDefaultName,
    sprite_datum_class,
    sprite_datum_size,
  } = data;

  return (
    <Window width={800} height={605} theme={theme ?? undefined}>
      <Window.Content>
        <Stack fill>
          <Stack.Item basis="30%">
            <ModuleSection
              title="Modules"
              sortable={possible_modules}
              highlighted={whitelisted_modules}
              selected={selected_module ?? undefined}
            />
          </Stack.Item>
          <Stack.Item basis="30%">
            <SpriteSection
              title="Sprites"
              sortable={possible_sprites}
              selected={sprite_datum}
            />
          </Stack.Item>
          <Stack.Item grow>
            <IconSection
              currentName={currentName}
              mindName={mind_name}
              isDefaultName={isDefaultName}
              sprite={sprite_datum_class}
              size={sprite_datum_size}
            />
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
