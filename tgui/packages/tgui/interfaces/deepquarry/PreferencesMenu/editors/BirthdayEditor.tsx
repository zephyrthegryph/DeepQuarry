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

  // One grid: the labels share a column and the two menus share a width, so Month and Day line up.
  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns: 'max-content max-content',
        columnGap: '0.75em',
        rowGap: '0.3em',
        alignItems: 'center',
      }}
    >
      <Box color="label">Month</Box>
      <Dropdown
        width="11.667em"
        // A fixed menu size: sized to its content, the menu's own scrollbar changed that width every frame.
        menuWidth="11.667em"
        selected={monthVal}
        displayText={monthLabel}
        options={monthOptions}
        onSelected={(v) => send('set_month', String(v))}
      />
      <Box color="label">Day</Box>
      <Dropdown
        width="11.667em"
        menuWidth="11.667em"
        selected={dayVal}
        displayText={dayLabel}
        options={dayOptions}
        onSelected={(v) => send('set_day', String(v))}
      />
    </Box>
  );
};
