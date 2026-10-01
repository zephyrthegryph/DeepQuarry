# Bounded residual operand audit

Read-only audit of `D:/opendream-diagnostic/latest-parity.ndjson` against the native matched reference and `deepquarry-current.dmb`. This precedes the final refreshed game emission. No production/comparator normalization was changed and DreamDaemon was not run.

## Branch-only category: 36 procedures

A standalone diagnostic compiled against the existing Rust library inspected all 36 procedure pairs. Excluding debug markers, it aligned instruction indices and checked branch destinations. A differing destination was accepted only when following unconditional jumps or repeated **same-polarity** short-circuit jumps reached the same instruction index. Repeated short-circuit jumps inspect the retained value and do not evaluate another expression. Opposite polarity, side-effecting intermediate instructions, loops in the chase, different instruction counts, and unsupported branch shapes were rejected.

- **34 procedure pairs:** every differing simple branch destination satisfied that bounded chase. Their other operands were already equal in this parity category. Existing null guards had equal destinations.
- **2 switch pairs:** `/datum/controller/subsystem/state_letter` and `/datum/tgui_module/appearance_changer/vore/changed_hook` differed only in case-entry order within groups selecting the same body. Manual inspection confirmed the same keys, the same target per key, and the same default target. There were no duplicate keys whose ordering could change dispatch.

The diagnostic and complete per-procedure results are `D:/opendream-diagnostic/branch_chain_probe.rs`, `branch_pairs.tsv`, and `branch_chain_probe.txt`. This is a proof of the specified branch transformations in these 36 pairs, not a general equivalence checker for arbitrary mixed instruction layouts.

## Other-operands category: 187 procedures

All 187 entries were classified by their complete reported operand differences. Most contain explicit cache-owner selectors, short-circuit targets, or native static selectors versus translated dynamic selectors. The refreshed selector comparer and cache-owner audit must assess those respective categories; this inspection does not assume unknown receiver identities are equal.

The only ordinary scalar string-value differences occurred in five procedures:

- `/datum/data_rc_msg/New`, `/datum/disease/advance/SetDanger`, `/proc/department_flag_to_name`, `/obj/item/clothing/mask/synthfacemask/update_icon`: switch default body placement shifts the corresponding string-valued bodies. Direct inspection of the department and mask tables confirmed that case and default targets still select the correct string and join.
- `/mob/living/simple_mob/animal/synx::<class initializer>`: independent list initializers containing `"clawed"` and `"smacked"` appear in a different store order. The source assigns them to separate fields. This is a bounded source inspection; it does not establish general constructor-store reordering safety.

No additional concrete non-harmless defect was established by this audit. Unresolved cache/reference pairs remain unresolved, and the fresh final parity must be checked separately.

## Final refreshed pair

The final audit uses `D:/opendream-diagnostic/final-parity.ndjson`, the matched native reference, and `deepquarry-final.dmb`. Counts below are procedure records, including distinct overrides with the same normalized path.

### Branch/switch-only: 58 procedures

All 58 satisfy a bounded static check with equal executable instruction counts and opcodes:

- 49 contain simple branches. Differing destinations reach the same executable instruction through unconditional `Jmp` or repeated same-polarity short-circuit branches. The check does **not** skip `JmpLoop`, opposite-polarity branches, or effectful instructions.
- Nine contain switches. Exact keys, disjoint numeric ranges, and defaults select the same executable bodies after the same bounded jump chase. Duplicate keys or overlapping ranges with different targets are rejected. `/datum/player_tips/pick_tip` additionally retains every weighted-pick threshold in its original order; only physical destinations differ.

Read-only diagnostic: `D:/opendream-diagnostic/final-branch-semantic-probe.rs`; complete results: `final-branch-semantic-probe.txt`; inputs: `final-branch-pairs.tsv`. No comparer rules were changed.

### Other-operands-only: 191 procedures

There are 191 procedure records and 189 unique normalized paths. Many arrivals moved from earlier mixed-layout categories after lowering fixes, so the increase is not a count of newly introduced operand defects.

The refreshed ordinary scalar differences are:

- Five switch-body placements: the four previously listed switch procedures plus `/datum/affliction/cardiac_arrhythmia/recompute_stage_from_severity` (`Sinus`/`Asystole`). Positional string differences require dispatch-to-body analysis; equal strings at the same instruction index are not required by switch semantics.
- The previously listed independent `synx` initializer store ordering.
- Three implicit-input declarations (`synx/ai/pet/debug/rename`, `redesc`, `resprite`): native Input mask 0 versus translated mask 4. Their source omits an `as` clause. The follow-up below resolves this writer-contract discrepancy by preserving omitted syntax; runtime equivalence is not assumed.

Cache-owner references and static/dynamic selectors still require their separate contextual audits. This refresh establishes no additional concrete non-harmless lowering defect and does not declare the 191 records equivalent wholesale.

### Implicit Input contract correction

A nine-procedure native paired fixture (`fixtures/translation/input_default/input_default.dme`) establishes that omitting `as` writes Input type mask **0**, while explicitly writing `as text` writes **4**. This holds with four arguments, omitted/default arguments, variable choice lists, and an authored null choice list. Explicit `as anything` with choices writes **4096**. Authored list presence remains the separate Input operand **64**, including `in null`.

OpenDream previously replaced the absent source type with its text/anything runtime default before export, losing this distinction. The exporter now retains omission in bit29 of the existing Prompt operand; lowering consumes that provenance and writes native mask0. Bits30/31 continue to represent choice presence/explicit anything and are stripped from native output. This reproduces the native writer contract without assuming runtime equivalence of masks0 and4 or weakening the comparer. The three observed synx prompt cases are instances of the omitted-type form.

## Fresh core503 audit and concrete operand defects

The refreshed pair is `next-core-classified-parity.ndjson`: fresh native `D:/dmb-fresh-reference-20260928/paired/deepquarry-static-ref.dmb` versus `deepquarry-next-core.dmb`. The bounded branch diagnostic proves all **76 branch/switch-only pairs**, preserving executable opcodes and counts, dispatched keys/ranges/defaults, and effectful or budgeted branches. Results are `next-branch-semantic-probe.txt`. This conclusion does not apply to mixed layouts or other-operands pairs.

Inspection of **193 other-operands procedure records** found concrete defects, so this category must not be described as equivalent wholesale:

- **Verb namespace:** 19 reported selector rows in 17 procedures used translated DynamicProc for native DynamicVerb/StaticVerb. Proc and verb namespaces can legally share the same display name. Lowering now preserves the resolved verb namespace for typed, bare-self, inherited, guarded, computed and argument-list calls. The portable 18-caller `verb_selectors` fixture passes complete-body comparisons in both debug modes. StaticVerb normalization is limited to the actual referenced descriptor's display name in the same verb namespace; installed VM dispatch proves modes 1/9 match DynamicVerb. Negative controls retain proc/verb and name distinctions.
- **Indexed augmented-subtraction entry:** `contracts/unsubscribe` and `mob/living/revoke_ability` branch into relocated owner evaluation after skipping the RHS argument load. A source branch entering the whole assignment must enter its relocated first expression. A paired correction is in progress; the original artifact remains harmful evidence.
- **Output entry:** `synx/randomspeech` branches directly into the output string after skipping the newly inserted world receiver. Source labels at the RHS beginning must move to the inserted receiver beginning. The paired `output_branch_entries` fixture covers early returns, else arms, backward labels, formatting, conditional values, and field/index receivers. All twelve complete native-body comparisons pass in both debug modes against the fresh9:00:36 library.
- **Short-circuit guarded RHS cleanup:** `mob/me_wrapper` and `mob/subtle_wrapper` send the skipped And path into an RHS PopCache without acquiring that RHS cache frame. The join must follow the skipped frame cleanup. A paired correction is in progress.

These defects require revalidation on a fresh emitted pair after their fixes. Ordinary switch-body positional string/global differences and independent constructor stores retain their bounded earlier classifications; unresolved receiver/reference differences remain unresolved. No runtime execution was used.
## Final classified pair after the 522-test gate

The read-only refresh uses `final-classified-parity.ndjson`, fresh native `D:/dmb-fresh-reference-20260928/paired/deepquarry-static-ref.dmb`, and `deepquarry-final.dmb`: **89 branch/switch-only**, **181 other-operands-only**, with metadata differences zero. This artifact precedes the following newly identified constructor correction.

The existing bounded branch diagnostic proves **86 of89** without skipping effects or budgeted branches. Two additional cases (`linked/link_portal`, `filingcabinet/Initialize`) require recognizing unchanged JzLoop(FA) targets: native and translated both return to the aligned IterNext; their differing Or/And routes reach the same final Test through same-polarity short-circuit jumps. The diagnostic's unsupported-FA response is not a semantic mismatch.

The final remaining pair, **`/proc/log_research`**, exposes a real constructor entry defect: native Jz enters the inserted file-type PushVal before argument evaluation, while translated Jz skips that type and enters the first argument. A private expression-prefix insertion helper now keeps source labels at the whole constructor beginning. The paired constructor fixture also checks conditional argument diamonds, whose start must be determined from the complete closed expression rather than its final linear arm. All nineteen complete native bodies pass in both debug modes against the focused corrected Cargo gate; this original pair remains harmful evidence pending fresh game emission.

Other-operands scalar follow-up confirmed meteor-wave case3 selects the storm message and default selects shower in both artifacts, although bodies appear in opposite physical order. Synthfacemask case2 selects the dead icon string and default selects live in both. Unresolved receiver/selector cases remain outside this bounded scalar proof.
The refreshed read-only diagnostic now recognizes unchanged F9/FA branch instructions and machine-checks all **88 remaining branch-only pairs** (`final503-branch-semantic-probe.rs`, `final503-branch-semantic.txt`). It never skips those budgeted instructions. The only failed target remains the original log_research constructor entry.


## Reachable loop-budget residual audit (latest 503 snapshot)

A read-only typed control-flow scan of the 80 procedures with fewer translated F8 words found 78 with the same number of reachable budgeted transfers. The missing native words are unreachable tails; this is a bounded scheduling count proof, not general procedure equivalence. Branch-table, catch and ordinary instruction-entry destinations are included.

The two reachable deficits were `/proc/reject_bad_name` and `/datum/admins/Topic`. Both have an authored `continue` as a switch default. Native tables target the default's F8 instruction; translation had consumed its OpenDream Jump directly into the table destination, bypassing its budget check. All seven switch-table default handlers now preserve authored continue/goto/protected-transfer provenance while retaining synthetic routing-jump folding. Five keyed-arm native pairs pass both debug modes; the production comparer remains unchanged.

A background-loop probe found another scheduling issue: the exporter inserted synthetic `sleep(-1)` calls on continues and natural backedges although native background procs rely on their attribute and budgeted transfers. The compiler removes these synthetic sleeps while retaining authored sleep. Eight complete paired bodies and explicit Sleep counts pass both debug modes.

Constant-true do/while authored continue now targets the body directly, avoiding an additional natural-backedge budget check. Seventeen complete-body pairs pass; an eighteenth all-path continue/break control compares its reachable budget graph because native keeps an unreachable natural tail removed by source optimization. Combined full-package gates remain the parent task's responsibility.

### Typed world and equal-address backedge followup

The two negative FA-count witnesses (`build_click` and `build_drag`) came from typed world iteration. Native atom loops enumerate world.contents with a coarse atom category and the applicable IsType/JzLoop filter; the translator had used the nonatom type-universe mode16384 and omitted that budget operation. The resolver now selects native atom masks using actual ancestry; exact mob/turf/area roots retain native filter elision. Eight complete paired bodies pass both debug modes. Datum/client universe enumeration remains mode16384.

Empty while(1) and do{}while(1) have a backedge whose source and target are equal. Native F8 performs budget dispatch there; strict-backward comparison emitted plain Jmp. Backward-or-equal transfers now use F8. Two complete native pairs pass both debug modes. Legacy backward/equal switch defaults retain their budgeted transfer even without authored-goto metadata.

A full-game lowering rejection in fake_attacker/process exposed nested constructor/output prefix accounting around lazy picks. Native79 spans now exclude inserted receiver/type prefixes; B1 spans begin at their exact probability arguments. Five complete native output bodies pass both debug modes, with previous constructor19/lazy22/weighted18 focused regressions passing. Final combined package gates are pending in the parent task.

## Iteration3 full-pair flow validation

Against fresh `deepquarry-iteration3.dmb`, a read-only audit paired all 62,318 procedures using the production comparer's class-binding ordering. Its typed control-flow traversal preserves every branch, table and catch target. The total-and-conservatively-reachable vector for F8/F9/FA/Catch/TryJmp matched exactly for 62,233 pairs. The remaining 85 differed only by unreachable native F8 tails: 78 lacked one tail, 4 lacked two, 3 lacked three. No pair had a reachable budget/handler-transfer count mismatch. This establishes counts under the bounded CFG model, not general semantic equivalence or scheduling placement.

All 93 branch/switch-only candidate routes pass the existing keyed-table/typed-target audit. The fresh OTHER 182 group has 168 passing branch-route checks and 14 cases with documented physical switch-body reordering or unsupported range-table position matching; no ordinary target, opcode or instruction-count failures were found. Five newly-entered OTHER paths contain cache-selector differences alongside equivalent plain-jump/short-circuit routes. Their receiver lifetime semantics remain the separate cache audit's responsibility.

Evidence: `D:/opendream-diagnostic/iteration3-all-budget.{rs,txt}`, `iteration3-branch-semantic-probe.txt`, `iteration3-other-branch-probe.txt`. Final combined package gates are tracked by the parent task.
