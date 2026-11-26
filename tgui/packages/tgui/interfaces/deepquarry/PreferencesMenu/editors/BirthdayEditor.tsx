// DQAdd — Birthday picker. Two dropdowns: month (Jan-Dec) and day (1-N where N depends
// on the picked month). Sends `set_month` / `set_day` to /datum/preference_editor/birthday.

import { useBackend } from 'tgui/backend';
import { Box, Dropdown } from 'tgui-core/components';
import type { EditorProps } from './index';

export const BirthdayEditor = ({
  data: d,
  staticData: s,
}: EditorProps<'birthday'>) => {
  const { act } = useBackend();
  const months = s?.months ?? [];

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

  // One line: the Birthday label, then the month and the day menus.
  return (
    <Box
      style={{
        display: 'flex',
        alignItems: 'center',
        flexWrap: 'wrap',
        gap: '0.3em 0.75em',
      }}
    >
      <Box color="label">Birthday:</Box>
      <Dropdown
        width="9em"
        // A fixed menu size: sized to its content, the menu's own scrollbar changed that width every frame.
        menuWidth="9em"
        selected={monthVal}
        displayText={monthLabel}
        options={monthOptions}
        onSelected={(v) => send('set_month', String(v))}
      />
      <Dropdown
        width="5em"
        menuWidth="5em"
        selected={dayVal}
        displayText={dayLabel}
        options={dayOptions}
        onSelected={(v) => send('set_day', String(v))}
      />
    </Box>
  );
};
