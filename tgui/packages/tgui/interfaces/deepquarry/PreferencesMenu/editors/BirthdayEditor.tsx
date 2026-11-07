// DQAdd — Birthday picker. Two dropdowns: month (Jan-Dec) and day (1-N where N depends
// on the picked month). Sends `set_month` / `set_day` to /datum/preference_editor/birthday.

import { useBackend } from 'tgui/backend';
import { Button, Dropdown, Stack } from 'tgui-core/components';
import type { EditorProps } from './index';

type Data = {
  month: number;
  day: number;
  max_day_for_month: number;
};

type Static = {
  months: string[];
};

export const BirthdayEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as Data;
  const s = (staticData ?? {}) as Static;
  const months = s.months ?? [];

  const monthOptions = months.map((name, i) => ({
    value: String(i + 1),
    displayText: name,
  }));

  const dayMax = d.max_day_for_month || 31;
  const dayOptions = Array.from({ length: dayMax }, (_, i) => ({
    value: String(i + 1),
    displayText: String(i + 1),
  }));

  const send = (action: string, value: string) =>
    act('dq_editor_action', {
      editor: 'birthday',
      action,
      params: { value },
    });

  const monthVal = String(d.month ?? 1);
  const monthLabel =
    monthOptions.find((o) => o.value === monthVal)?.displayText ?? monthVal;
  const dayVal = String(d.day ?? 1);
  const dayLabel =
    dayOptions.find((o) => o.value === dayVal)?.displayText ?? dayVal;

  return (
    // Wraps in a narrow column instead of pushing Announce? over the next panel.
    <Stack align="center" style={{ flexWrap: 'wrap', rowGap: '0.3em' }}>
      <Stack.Item color="label">Month</Stack.Item>
      <Stack.Item>
        <Dropdown
          width="11.667em"
          // A fixed menu size: sized to its content, the menu's own scrollbar changed that width every frame.
          menuWidth="11.667em"
          selected={monthVal}
          displayText={monthLabel}
          options={monthOptions}
          onSelected={(v) => send('set_month', String(v))}
        />
      </Stack.Item>
      <Stack.Item color="label" ml={1}>
        Day
      </Stack.Item>
      <Stack.Item>
        <Dropdown
          width="6.667em"
          menuWidth="6.667em"
          selected={dayVal}
          displayText={dayLabel}
          options={dayOptions}
          onSelected={(v) => send('set_day', String(v))}
        />
      </Stack.Item>
    </Stack>
  );
};
