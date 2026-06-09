// DQAdd — Birthday picker. Two dropdowns: month (Jan-Dec) and day (1-N where N depends
// on the picked month). Sends `set_month` / `set_day` to /datum/preference_editor/birthday.

import { useBackend } from 'tgui/backend';
import { Dropdown, Stack } from 'tgui-core/components';
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

  const monthOptions = [
    { value: '0', displayText: '— Unset —' },
    ...months.map((name, i) => ({
      value: String(i + 1),
      displayText: name,
    })),
  ];

  const dayMax = d.max_day_for_month || 31;
  const dayOptions = [
    { value: '0', displayText: '—' },
    ...Array.from({ length: dayMax }, (_, i) => ({
      value: String(i + 1),
      displayText: String(i + 1),
    })),
  ];

  const send = (action: string, value: string) =>
    act('dq_editor_action', {
      editor: 'birthday',
      action,
      params: { value },
    });

  const monthVal = String(d.month ?? 0);
  const monthLabel =
    monthOptions.find((o) => o.value === monthVal)?.displayText ?? monthVal;
  const dayVal = String(d.day ?? 0);
  const dayLabel = dayOptions.find((o) => o.value === dayVal)?.displayText ?? dayVal;

  return (
    <Stack align="center">
      <Stack.Item color="label">Month</Stack.Item>
      <Stack.Item>
        <Dropdown
          width="140px"
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
          width="80px"
          selected={dayVal}
          displayText={dayLabel}
          options={dayOptions}
          onSelected={(v) => send('set_day', String(v))}
        />
      </Stack.Item>
    </Stack>
  );
};
