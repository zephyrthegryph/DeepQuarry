// The pet customize window: the name, description, gender, colour and size
// settings of a simple mob (what its Settings verbs were) in one console
// window. The server lists the settings with their present values and says
// which are used up, so a new setting is a row in the DM list and no change
// here.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  ColorBox,
  LabeledList,
  NoticeBox,
  Section,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import type { PetCustomizeActions } from './generated/PetCustomize';

type Setting = {
  id: string;
  label: string;
  desc: string;
  value: string | null;
  swatch: string | null;
  action: string;
  enabled: BooleanLike;
  why: string | null;
};

type Data = {
  pet_name: string;
  settings: Setting[];
};

const SettingRow = (props: { setting: Setting }) => {
  const { act } = useBackend<Data, PetCustomizeActions>();
  const { setting } = props;
  return (
    <LabeledList.Item
      label={setting.label}
      buttons={
        <Button
          disabled={!setting.enabled}
          tooltip={setting.enabled ? setting.desc : setting.why || setting.desc}
          onClick={() => act('pet_do', { action: setting.id })}
        >
          {setting.action}
        </Button>
      }
    >
      {!!setting.swatch && <ColorBox color={setting.swatch} mr={1} />}
      <Box inline preserveWhitespace>
        {setting.value ?? ''}
      </Box>
    </LabeledList.Item>
  );
};

export const PetCustomize = () => {
  const { data } = useBackend<Data, PetCustomizeActions>();
  const { pet_name, settings } = data;
  return (
    <Window width={480} height={420} title="Customize" theme="console">
      <Window.Content scrollable>
        {!settings.length && (
          <NoticeBox>There is nothing to customize.</NoticeBox>
        )}
        {!!settings.length && (
          <Section title={pet_name}>
            <LabeledList>
              {settings.map((setting) => (
                <SettingRow key={setting.id} setting={setting} />
              ))}
            </LabeledList>
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};
