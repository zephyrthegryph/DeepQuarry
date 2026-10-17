import { spawn } from 'node:child_process';
import os from 'node:os';

/** DQ_PRIORITY=normal opts every low-priority helper out; `idle` goes lower still. Same variable as dmbc's DMB_PRIORITY. */
export function lowPriorityLevel(env: NodeJS.ProcessEnv = process.env): number | null {
  switch (env.DQ_PRIORITY ?? env.DMB_PRIORITY ?? '') {
    case 'normal': return null;
    case 'idle': return os.constants.priority.PRIORITY_LOW;
    default: return os.constants.priority.PRIORITY_BELOW_NORMAL;
  }
}

/**
 * Run a long background tool (DreamChecker) at below-normal priority so it never starves the desktop. The priority is set on
 * the child right after spawn: Windows applies a process priority class to every thread, Unix `setpriority` to the process.
 * Failure to lower it is not an error. Output goes straight to this process's stdout/stderr.
 */
export function execLowPriority(command: string, args: string[], options: { cwd?: string } = {}): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: options.cwd, stdio: 'inherit' });
    const level = lowPriorityLevel();
    if (level !== null && child.pid !== undefined) {
      try { os.setPriority(child.pid, level); } catch { /* the OS refused; the tool still runs at normal priority */ }
    }
    child.on('error', reject);
    child.on('close', (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} exited with ${code ?? signal}`));
    });
  });
}
