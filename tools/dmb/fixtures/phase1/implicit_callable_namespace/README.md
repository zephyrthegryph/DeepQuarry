# Implicit callable namespace controls

Pinned DreamMaker 516.1687 compile-only controls, 2026-10-07. No runtime was launched.

`control.dme` compiled with zero errors and two `override_before_def` warnings
for the deliberately earlier same-owner implicit body. A bare callable can
override an inherited verb and can precede its same-owner formal verb definition.
The semantic tree must retain that verb namespace through override grouping,
body identities and ABI preparation; a Proc-only ABI fallback would lose it.

`duplicate.dme` is an expected rejection: an explicit proc over an inherited
verb and same-owner explicit proc/verb definitions of one name are duplicates.
Explicit namespaces remain authored facts, rather than being rewritten as bare
overrides. The tree regression covers the same-owner duplicate rejection.

Raw compiler receipts and generated outputs are outside Git at
`D:/dmb-native-v2-phase0/implicit-verb-controls/`. These controls establish source
admission, not runtime callback order or a complete unknown-engine-name catalog.
