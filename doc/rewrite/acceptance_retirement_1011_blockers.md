# Acceptance retirement preparation

This branch is source preparation until its new lane-ready run completes. No stamp
has been reconstructed from the earlier passing but unstamped 149-table run.

The 149-table cohort and final 24 tables use native acceptance plans, role-aware
requirements and unit-aware numeric thresholds. Runtime identity writers use
registered setters. Six concrete appearance fields are tracked. Saddlebag and
Avida looks now follow a declared weak wearer relation maintained by the real
slot lifecycle; focused tests exercise transfer, drop and wearer destruction.

Capability runtime records use a declared owned associative map. Allocation
honors the inherited declared map shape even when the first key is a type path;
ordinary list declarations retain their old allocation rules. Both ordinary
cleanup and aborted-runtime cleanup detach records before invoking their cleanup
handlers. A narrow generator regression and runtime lifecycle tests cover this.

The user's four reserved constructor assignments remain untouched: material
bracelet, material ring, ranger gloves and ranger boots. Current master's own-
constructor tracking exemption means these do not introduce new tracked-write
sites. No init baseline or ALLOW was added.

The protected analyzer read-walk and tracked-lint files match master. Only the
unowned declaration generator was extended for declared relation storage.

Native request outcome constants such as REQ_CANCELLED remain request protocol
values. They are not renamed to obtain a lexical REQ_ count of zero. The retired
forms are legacy requirement macros and the predicate compiler.

Repair verification at 87fc37268e: all seven failed/new dispatch cases passed (data/test-runs/20261013T225435_87fc37268e.json). Both look pins passed in the preceding repair batch without golden changes. A fresh lane-ready run is required for the final merged commit; partial results have not been used to reconstruct a stamp.

Final merged proof at 4c2262dd6e: 112 tests passed, zero failures, production DreamMaker errors zero, DreamChecker diagnostics zero, analyzer tests passed. The stamp was correctly refused because two draw lint findings remained. The user approved restoring sem/reads.rs and sem/globals.rs exactly from d67f63371a, reinstating master's boot-only global/field classification and its regression tests. No partial proof is used to synthesize a stamp.

The approved exact-master reader restoration is committed at c6e369fea2. The subsequent gate at 84a080c6b2 compiled production with zero DreamChecker diagnostics and zero DreamMaker errors; its queued test job was cancelled after the same two remaining draw findings were diagnosed, so it has no runtime result or stamp. The remaining cause is WriteIndex's name-only mutation proof: the two native marker-beacon icon_base setters make unrelated immutable flooring/material icon_base declarations look mutable. This needs receiver/declaration-scoped writer proof in the owner-controlled reader. Season publication and baseline restoration are not appropriate fixes. The prior complete 112-test result remains evidence only, not a reconstructed stamp.
