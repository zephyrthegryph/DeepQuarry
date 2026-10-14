// Ports for test worlds. The OS hands out a free port, but it is free only until another world (another worktree's run) picks the
// same one before DreamDaemon binds it: the daemon then dies with "FAILED to open port". So a port is checked on every interface the
// daemon binds, claimed machine-wide with a lock file (owner pid, stale when the pid is gone), and a world that dies at boot is
// relaunched on another port (shouldRetryBoot).
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';

/** A port the OS says is free on all interfaces (what DreamDaemon binds), picked by the OS. */
export function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on('error', reject);
    server.listen(0, '0.0.0.0', () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : 0;
      server.close(() => resolve(port));
    });
  });
}

export function portLocksDir(): string {
  if (process.env.DQ_PORTS_DIR) return process.env.DQ_PORTS_DIR;
  if (process.platform === 'win32' && fs.existsSync('E:/dq-cache')) return 'E:/dq-cache/ports';
  return path.join(os.homedir(), '.cache', 'dq', 'ports');
}

function pidAlive(pid: number): boolean {
  if (!pid || Number.isNaN(pid)) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export interface PortClaim {
  port: number;
  release(): void;
}

/** Take the lock file for `port`; false when a live process holds it. A stale lock (dead owner) is replaced. */
export function tryClaimPort(dir: string, port: number, pid = process.pid): PortClaim | null {
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${port}.lock`);
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      fs.writeFileSync(file, String(pid), { flag: 'wx' });
      return {
        port,
        release() {
          try {
            if (fs.readFileSync(file, 'utf-8') === String(pid)) fs.unlinkSync(file);
          } catch {
            // already gone
          }
        },
      };
    } catch {
      let owner = 0;
      try {
        owner = Number(fs.readFileSync(file, 'utf-8'));
      } catch {
        // vanished between the two calls: try again
      }
      if (owner && pidAlive(owner)) return null;
      try {
        fs.unlinkSync(file);
      } catch {
        // someone else replaced it
      }
    }
  }
  return null;
}

/** A free, unclaimed port, with its machine-wide claim. `pick` is the source of candidates (the OS by default). */
export async function claimFreePort(pick: () => Promise<number> = freePort, dir = portLocksDir(), tries = 20): Promise<PortClaim> {
  for (let i = 0; i < tries; i++) {
    const claim = tryClaimPort(dir, await pick());
    if (claim) return claim;
  }
  throw new Error(`no free unclaimed TCP port after ${tries} tries (${dir})`);
}

/** A daemon that exits this fast without a results file or a clean-run marker never booted: its port was taken. */
export const BOOT_FAIL_MS = 30_000;
export function shouldRetryBoot(elapsedMs: number, hasResults: boolean, clean: boolean, attempt: number, maxAttempts = 4): boolean {
  return attempt < maxAttempts && !hasResults && !clean && elapsedMs < BOOT_FAIL_MS;
}
