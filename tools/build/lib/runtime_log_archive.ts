import { createHash, randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export type RuntimeLogArchive = { manifest?: string; sha256?: string; complete?: boolean; error?: string; worldSpawned?: boolean };

/** Called after the owned world has ended. Bounds are evidence limits, not log truncation. */
export function archiveRuntimeLogs(source: string, daemonLog: string | null, archiveRoot = 'data/runtime-evidence'): RuntimeLogArchive {
  const destination = path.resolve(archiveRoot, randomUUID());
  fs.mkdirSync(destination, { recursive: true });
  fs.mkdirSync(path.join(destination, 'world'));
  const files: { name: string; bytes: number; sha256: string }[] = [];
  const omitted: { name: string; reason: string }[] = [];
  let total = 0;
  try {
    const exists = fs.existsSync(source);
    const entries = exists ? fs.readdirSync(source, { withFileTypes: true }) : [];
    if (!exists) omitted.push({ name: source, reason: 'world log directory missing' });
    const candidates = entries.slice(0, 256).map(entry => ({ name: `world/${entry.name}`, file: path.join(source, entry.name) }));
    if (entries.length > 256) omitted.push({ name: source, reason: 'directory exceeds 256 entries' });
    if (daemonLog) {
      if (fs.existsSync(daemonLog)) candidates.push({ name: 'daemon.log', file: daemonLog });
      else omitted.push({ name: 'daemon.log', reason: 'owned daemon log missing' });
    }
    for (const candidate of candidates) {
      const stat = fs.lstatSync(candidate.file);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 64 * 1024 * 1024 || total + stat.size > 256 * 1024 * 1024) {
        omitted.push({ name: candidate.name, reason: 'not a regular file or archive byte bound exceeded' });
        continue;
      }
      // Archive one bounded chunk at a time; large logs must not accumulate
      // whole-file buffers in the long-lived build runner between worlds.
      const buffer = Buffer.alloc(Math.min(stat.size, 1024 * 1024));
      const hash = createHash('sha256');
      const fd = fs.openSync(candidate.file, 'r');
      let destinationFd: number | undefined;
      try {
        destinationFd = fs.openSync(path.join(destination, candidate.name), 'wx');
        let read = 0;
        while (read < stat.size) {
          const count = fs.readSync(fd, buffer, 0, Math.min(buffer.length, stat.size - read), read);
          if (count === 0) throw new Error('log shortened during archival');
          let written = 0;
          while (written < count) {
            const amount = fs.writeSync(destinationFd, buffer, written, count - written);
            if (amount === 0) throw new Error('log archive write made no progress');
            written += amount;
          }
          hash.update(buffer.subarray(0, count));
          read += count;
        }
        if (fs.fstatSync(fd).size !== stat.size) throw new Error('log changed during archival');
      } finally {
        if (destinationFd !== undefined) fs.closeSync(destinationFd);
        fs.closeSync(fd);
      }
      files.push({ name: candidate.name, bytes: stat.size, sha256: hash.digest('hex') });
      total += stat.size;
    }
  } catch (error) {
    omitted.push({ name: source, reason: String(error) });
  }
  const manifest = path.join(destination, 'manifest.json');
  const bytes = Buffer.from(JSON.stringify({ schema: 1, source: path.resolve(source), files, omitted, complete: omitted.length === 0 }, null, 2) + '\n');
  fs.writeFileSync(manifest, bytes, { flag: 'wx' });
  return { manifest, sha256: createHash('sha256').update(bytes).digest('hex'), complete: omitted.length === 0 };
}
