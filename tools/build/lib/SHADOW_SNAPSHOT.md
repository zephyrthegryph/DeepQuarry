# Shadow source authority

Shadow records structural comparison results and a separate source-snapshot
contract. The current contract is **incomplete**: `compileByond` supplies command
and observed compiler version metadata, but no authenticated input/resource
closure. Even a complete comparison with zero discrepancies cannot establish
shadow parity without that authority. The comparison label hashes explicit
requested configuration, manifest/compiler identity and output identities; it
is an evidence label, not a complete input snapshot ID.

`ByondCompilationResult` now has a future optional `AuthenticatedByondSnapshot`
producer contract: exact file roster/bytes, ordered resource search roots,
effective defines/compiler hash/version, immutable source root, and output
hashes. No producer currently issues it, and shadow does not trust a supplied
object, branding flag, external receipt path or callback cast as proof.

## Producer integration point

The producer belongs around `selectedCompiler` after its build prerequisites
have completed, before either compiler starts. `DmTarget.executes` reaches this
boundary after icon repack, manifest validation, binding checks and generated
source checks. `compileDerived` first writes the derived manifest, so the same
boundary covers actual test/benchmark defines and generated includes.

A complete implementation must:

1. Resolve the actual DreamMaker executable/version before capture. Preserve
   exact effective define order/last-wins behavior and implicit version defines.
2. Issue one private immutable source/resource snapshot for both compiler
   invocations, including ordered resource search and negative lookup authority.
   Reject escaping absolute includes/resource paths unless captured explicitly.
   A before/after manifest hash or independently captured native journal cannot
   prove which intermediate bytes DreamMaker read.
3. Pass that snapshot's manifest to both compilers. The current BYOND callback
   already accepts a captured manifest override and prepared compiler identity;
   selection currently supplies no override because the closed snapshot issuer
   is missing. Keep normal BYOND output installation behavior through explicit
   verified output transfer afterward.
4. Authenticate the issued closure/configuration and compiler output hashes in
   the admission consumer. Native replay must use the same authority; avoid a
   separate weaker equivalence check. Record source/configuration proof and
   structural coverage/discrepancy proof independently.

Until that integration exists, shadow fails with incomplete source authority
and retains the named structural report plus context receipt. Native success,
typed source-error/cancellation behavior and BYOND fallback remain unchanged.
