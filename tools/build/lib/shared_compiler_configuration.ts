/** Configuration prerequisite for a future shared closure producer.
 * No caller-supplied version object or native read journal is an authority.
 */
import { currentDreamMakerConfiguration, type PreparedDreamMaker } from './byond';
import { currentNativeTargetConfiguration } from './compiler_selection';
import type { NativePairOutput } from './native_pair';

export function sharedCompilerConfiguration(prepared: PreparedDreamMaker, defines: readonly string[], native: NativePairOutput) {
  const byond = currentDreamMakerConfiguration(prepared, defines);
  const issuedNative = currentNativeTargetConfiguration(native);
  // These are the current native pinned_target policy's only admitted version.
  // Its full engine/predefine receipt is not yet exported to this consumer.
  if (byond.version !== 516 || byond.build !== 1687) {
    throw new Error('Shared compiler configuration requires the native pinned BYOND 516.1687 target.');
  }
  const effectiveDefines = new Map<string, string>();
  for (const define of defines) {
    const at = define.indexOf('=');
    const name = at < 0 ? define : define.slice(0, at);
    const value = at < 0 ? '1' : define.slice(at + 1);
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error('Unsupported shared compiler define spelling.');
    effectiveDefines.set(name, value);
  }
  for (const [name, expected] of [['DM_VERSION', '516'], ['DM_BUILD', '1687']]) {
    if (effectiveDefines.has(name) && effectiveDefines.get(name) !== expected) {
      throw new Error(`Shared compiler configuration conflicts with native pinned ${name}=${expected}.`);
    }
    effectiveDefines.set(name, expected);
  }
  const canonical = (values: Readonly<Record<string, string>>) => JSON.stringify(Object.entries(values).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0));
  if (canonical(Object.fromEntries(effectiveDefines)) !== canonical(issuedNative.configuration.effective_defines)) {
    throw new Error('Issued native and DreamMaker effective defines differ.');
  }
  return Object.freeze({ schema: 1 as const, status: 'incomplete' as const, byond,
    native: issuedNative, nativeTargetProfileAuthenticated: false as const, inputClosureAuthenticated: false as const,
    reason: 'Issued DreamMaker executable/version/ordered defines checked; native engine/predefined-macro profile and shared source/resource closure are not issued.' });
}
