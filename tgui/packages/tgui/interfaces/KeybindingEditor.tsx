import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Dropdown,
  Input,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';
import { isEscape, KEY } from 'tgui-core/keys';

type Binding = {
  id: string;
  name: string;
  category: string;
  command: string;
};

type Option = {
  id: string;
  name: string;
};

type Data = {
  bindings: Binding[];
  profiles: Option[];
  right_click_options: Option[];
  max_keys: number;
  profile: string;
  keys: Record<string, string[]>;
  customised: string[];
  right_click: string;
};

// DOM key names to BYOND macro key names.
const DOM_TO_BYOND: Record<string, string> = {
  ARROWUP: 'NORTH',
  ARROWDOWN: 'SOUTH',
  ARROWLEFT: 'WEST',
  ARROWRIGHT: 'EAST',
  HOME: 'NORTHWEST',
  END: 'SOUTHWEST',
  PAGEUP: 'NORTHEAST',
  PAGEDOWN: 'SOUTHEAST',
  DELETE: 'DELETE',
  INSERT: 'INSERT',
  ' ': 'SPACE',
  TAB: 'TAB',
  BACKSPACE: 'BACK',
  ENTER: 'RETURN',
  '+': 'ADD',
  '-': 'SUBTRACT',
  '*': 'MULTIPLY',
  '/': 'DIVIDE',
};

const DOM_KEY_LOCATION_NUMPAD = 3;

function isModifier(key: string): boolean {
  return key === KEY.Alt || key === KEY.Control || key === KEY.Shift;
}

/** Turns a key press into a BYOND macro name such as "CTRL+SHIFT+X". */
function byondKeyName(event: React.KeyboardEvent<HTMLDivElement>): string {
  const parts: string[] = [];
  if (event.ctrlKey) {
    parts.push('CTRL');
  }
  if (event.altKey) {
    parts.push('ALT');
  }
  if (event.shiftKey) {
    parts.push('SHIFT');
  }
  const key = event.key.toUpperCase();
  let name = DOM_TO_BYOND[key] || key;
  if (event.location === DOM_KEY_LOCATION_NUMPAD && /^[0-9]$/.test(key)) {
    name = `NUMPAD${key}`;
  }
  parts.push(name);
  return parts.join('+');
}

export const KeybindingEditor = (props) => {
  const { act, data } = useBackend<Data>();
  const {
    bindings,
    profiles,
    right_click_options,
    max_keys,
    profile,
    keys,
    customised,
    right_click,
  } = data;
  const [capturing, setCapturing] = useState<string | null>(null);
  const [search, setSearch] = useState('');

  const categories: string[] = [];
  for (const binding of bindings) {
    if (!categories.includes(binding.category)) {
      categories.push(binding.category);
    }
  }
  const [category, setCategory] = useState(categories[0]);

  const lowerSearch = search.toLowerCase();
  const shown = bindings.filter((binding) =>
    lowerSearch
      ? binding.name.toLowerCase().includes(lowerSearch) ||
        (keys[binding.id] || []).some((key) =>
          key.toLowerCase().includes(lowerSearch),
        )
      : binding.category === category,
  );

  function handleKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    if (!capturing) {
      return;
    }
    event.preventDefault();
    if (isEscape(event.key)) {
      setCapturing(null);
      return;
    }
    if (isModifier(event.key)) {
      return;
    }
    act('bind', { id: capturing, key: byondKeyName(event) });
    setCapturing(null);
  }

  const rightClickName =
    right_click_options.find((option) => option.id === right_click)?.name ||
    right_click;

  return (
    <Window title="Keybindings" width={560} height={640}>
      <Window.Content onKeyDown={handleKeyDown} scrollable>
        <Section title="Mouse">
          <LabeledList>
            <LabeledList.Item label="Right-click">
              <Dropdown
                width="100%"
                selected={rightClickName}
                options={right_click_options.map((option) => option.name)}
                onSelected={(name) => {
                  const option = right_click_options.find(
                    (entry) => entry.name === name,
                  );
                  if (option) {
                    act('set_right_click', { binding: option.id });
                  }
                }}
              />
            </LabeledList.Item>
          </LabeledList>
        </Section>
        <Section
          title="Keys"
          buttons={
            <Button.Confirm
              icon="undo"
              color="bad"
              onClick={() => act('reset_all')}
            >
              Reset profile
            </Button.Confirm>
          }
        >
          <Tabs>
            {profiles.map((entry) => (
              <Tabs.Tab
                key={entry.id}
                selected={entry.id === profile}
                onClick={() => act('set_profile', { profile: entry.id })}
              >
                {entry.name}
              </Tabs.Tab>
            ))}
          </Tabs>
          <Input
            fluid
            placeholder="Search bindings or keys"
            value={search}
            onChange={setSearch}
          />
          {!search && (
            <Tabs mt={1} fluid>
              {categories.map((entry) => (
                <Tabs.Tab
                  key={entry}
                  selected={entry === category}
                  onClick={() => setCategory(entry)}
                >
                  {entry}
                </Tabs.Tab>
              ))}
            </Tabs>
          )}
          {capturing && (
            <NoticeBox info>
              Press a key (with Ctrl, Alt or Shift if you like). Escape
              cancels.
            </NoticeBox>
          )}
          <Stack vertical mt={1}>
            {shown.map((binding) => {
              const bound = keys[binding.id] || [];
              return (
                <Stack.Item key={binding.id}>
                  <Stack align="center">
                    <Stack.Item grow>
                      <Box bold={customised.includes(binding.id)}>
                        {binding.name}
                      </Box>
                    </Stack.Item>
                    <Stack.Item>
                      {bound.map((key) => (
                        <Button
                          key={key}
                          icon="times"
                          tooltip="Unbind"
                          onClick={() =>
                            act('unbind', { id: binding.id, key: key })
                          }
                        >
                          {key}
                        </Button>
                      ))}
                      <Button
                        icon="plus"
                        selected={capturing === binding.id}
                        disabled={bound.length >= max_keys}
                        onClick={() =>
                          setCapturing(
                            capturing === binding.id ? null : binding.id,
                          )
                        }
                      />
                      <Button
                        icon="undo"
                        tooltip="Reset to default"
                        disabled={!customised.includes(binding.id)}
                        onClick={() => act('reset', { id: binding.id })}
                      />
                    </Stack.Item>
                  </Stack>
                </Stack.Item>
              );
            })}
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
