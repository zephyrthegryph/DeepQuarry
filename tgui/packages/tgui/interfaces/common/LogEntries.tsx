import type { ReactNode } from 'react';
import { Box, Stack } from 'tgui-core/components';
import { EmptyState } from './EmptyState';

export type LogEntry = {
  time?: ReactNode;
  message: ReactNode;
};

type Props = {
  entries: LogEntry[];
  emptyMessage?: ReactNode;
};

export const LogEntries = (props: Props) => {
  const { entries, emptyMessage = 'No entries.' } = props;
  if (entries.length === 0) {
    return <EmptyState message={emptyMessage} />;
  }
  return (
    <Stack vertical>
      {entries.map((e, i) => (
        <Stack.Item key={i}>
          {e.time !== undefined && (
            <Box inline bold mr={1}>
              {e.time}
            </Box>
          )}
          <Box inline>{e.message}</Box>
        </Stack.Item>
      ))}
    </Stack>
  );
};
