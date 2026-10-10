import path from 'node:path';

export function acquiredWorldArguments(args: any[], originalDmb: string, acquired: boolean): any[] {
  return acquired && !args.includes('-cd')
    ? [...args, '-cd', path.dirname(path.resolve(originalDmb))]
    : args;
}

// Hosting resolves its runtime independently of a prepared compilation request.
export async function resolveDreamDaemonExecutable(
  namedVersion: string | null | undefined,
  lookup: (version?: string | null) => Promise<string>,
  platform: string = process.platform,
): Promise<string> {
  const dmPath = await lookup(namedVersion);
  const baseDir = path.dirname(dmPath);
  const executable = platform === 'win32' ? 'dreamdaemon.exe' : 'DreamDaemon';
  return baseDir === '.' ? executable : path.join(baseDir, executable);
}
