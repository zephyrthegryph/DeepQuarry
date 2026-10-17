import { expect, test } from 'bun:test';
import os from 'node:os';
import { execLowPriority, lowPriorityLevel } from './low_priority';

test('below normal by default, DQ_PRIORITY=normal opts out', () => {
  expect(lowPriorityLevel({})).toBe(os.constants.priority.PRIORITY_BELOW_NORMAL);
  expect(lowPriorityLevel({ DQ_PRIORITY: 'normal' })).toBeNull();
  expect(lowPriorityLevel({ DMB_PRIORITY: 'idle' })).toBe(os.constants.priority.PRIORITY_LOW);
});

test('runs a command and reports a failing exit code', async () => {
  await execLowPriority(process.execPath, ['-e', '0']);
  await expect(execLowPriority(process.execPath, ['-e', 'process.exit(3)'])).rejects.toThrow('exited with 3');
});
