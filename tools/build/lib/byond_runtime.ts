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
  explicitExecutable: string | undefined = process.env.DQ_DD_EXE,
): Promise<string> {
  const dmPath = await lookup(namedVersion);
  const baseDir = path.dirname(dmPath);
  const executable = platform === 'win32' ? 'dd.exe' : 'DreamDaemon';
  const sibling = baseDir === '.' ? executable : path.join(baseDir, executable);
  if (explicitExecutable) {
    const expected = path.resolve(sibling);
    const actual = path.resolve(explicitExecutable);
    const equal = platform === 'win32' ? actual.toLowerCase() === expected.toLowerCase() : actual === expected;
    if (!path.isAbsolute(explicitExecutable) || baseDir === '.' || !equal) {
      throw new Error('Explicit DreamDaemon must be the selected DreamMaker console sibling');
    }
    return actual;
  }
  return sibling;
}
