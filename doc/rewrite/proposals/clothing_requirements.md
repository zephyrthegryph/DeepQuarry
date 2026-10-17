# Proposal: retiring the legacy `REQ_*` predicate language, mostly clothing fit and equip (design only)

Status: proposal, awaiting decisions D1 to D7. Scope: doc section 9 (`final_api.html`: requirements return null or a reason), section 17 (old forms),
section 19 (migration), and the remaining `REQ_*` sites at `cee490f697` (origin/master).

## 0. Summary

1. **The target form already exists and is in use.** `acceptance(channel, req..., mode)` (`code/engine/parts/acceptance.dm`) declares an ordered, immutable plan on a type;
   `fits(list(...), exclude =)`, `req_acceptance_type`, `req_acceptance_tag`, `req_acceptance_max_size` and others (`code/library/requirements/acceptance.dm`) return null to allow or
   the exact reason. Channels are `fit`, `equip`, `hold` and `suit_storage`. Master has about 163 `acceptance("...")` declarations (fit 67, suit_storage 72, hold 7, equip 4) and
   `dq_constraint_refusal()` prefers a native plan over the legacy `TYPE_TABLE(... fit_spec | equip_spec | hold_spec | suit_storage_spec)` predicate.
   So this is a **remaining-sweep** problem, not a design problem (as with the relations proposal).
2. **Codex's requirement work is mostly merged and is a different thing.** `codex/requirements-zero-1010` to `-g` (merged) removed the boolean requirement protocol:
   requirements return null or a reason. `codex/requirements-hard-ban-1010` (unmerged, handoff `doc/requirements_hard_ban_1010_handoff.md`) deletes the constructor and hard-bans
   `boolean_callback` in the `requirement_bool` lint. `codex/req-burndown` (unmerged, 344 files, mostly a merge of master plus `requirement_bool` and `lint_scopes.toml` edits)
   fixes saddlebag, Avida hat, holder size and cloning-console behaviour. **Neither touches the `REQ_*` macro language** (`PRED_*`, `/datum/predicate`). That is this proposal.
   Merge or rebase those two first (D7); they own `tools/analyze/src/lints/requirement_bool.rs` and `lint_scopes.toml`.
3. **Census: 326 raw grep lines, but only about 100 are the legacy language.** The rest is the kernel request-outcome enum (`REQ_ANSWERED`, `REQ_CANCELLED`, `REQ_TIMED_OUT`,
   `REQ_TRANSPORT_FAILED`, `REQ_NO_RESULT`, `REQ_FAILED`: doc section 9 keeps them; `tools/ci/legacy_form_counts.sh` already excludes them), `FREQ_*`, comments saying "was REQ_*" (about 25,
   delete), and the language's own definitions and tests. The doc names the outcomes `REQ_*` too, so the lint must key on the macro list, not the prefix (D6).
4. **Most remaining content sites are the `fit_spec` declarations (29 `REQ_FITS_BODYTYPES`) and `equip_spec` clearance procs (37 `REQ_ON`, 5 of them `taur_fit`).** They convert mechanically.
   About 115 `HOLD_ONLY/HOLD_NOT/HOLD_MAX_SIZE` uses (suit storage and holders; they expand to `REQ_BECAUSE`/`REQ_TYPE`) are the same language by another name and go in the same sweep.

## 1. Census

### 1.1 Language machinery (deleted at the end, not converted)

| Where | Lines | Notes |
|---|---|---|
| `code/__defines/predicates.dm` 33, `sys_requirements.dm` 15, `constraints.dm` 6 | 54 | the macros (`REQ_ALL/ANY/NOT/BECAUSE/TAG/CMP/ON/PROC/FIELD*/PANEL/ACCESS ...`) |
| `code/engine/parts/predicates.dm` 13, `code/datums/sys/requirements.dm` 12, `properties/constraints.dm` 3, `engine/time/records.dm` 3, `datums/operations/native_requirement_adapter.dm` 2 (`OP_LEGACY_REQ_FORMS`) | ~33 | compiler, evaluator, adapter |
| `code/datums/properties/equip_slots.dm` | 28 + 2 | per-slot equip spec (the "slot accepts" tags: `REQ_TAG(PRED_TARGET, TAG_WEAR_x)`, uniform present, pocket size). Slot data, not item content (D3) |
| unit tests (`dq_predicate_tests.dm` 56, `dq_sys_requirements_tests.dm` 26) | 82 | deleted with the language; `dq_acceptance_*` tests stay |

### 1.2 Content sites (the sweep), about 73 lines by pattern

| Pattern | Sites | Typical | Target |
|---|---|---|---|
| **Species fit** `REQ_FITS_BODYTYPES` in a `fit_spec` | 29 (rig pieces 4 plus 4 protean, teshari clothing 12, void/zaddat 6, shoes, `punpun`, altevian admiral, radiation teshari) | `TYPE_TABLE(/obj/item/clothing/under/teshari, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_TESHARI))))` | `acceptance("fit", fits(list(SPECIES_TESHARI)), mode = ACCEPTANCE_REPLACE)` in the type's block (67 already) |
| **Body-part presence / clearance** `REQ_ON(PRED_TARGET, proc, reason)` in `equip_spec` | 37 (`taur_fit` x5: saddlebags, wolftaur vest, drake cloak, barding; `limb_clearance`, `plate_clearance`; arm guards already native) | "you need a hindquarters to wear this" | a named library requirement per meaning; `req_acceptance_arm_clearance()` is the model; add `req_acceptance_taur_body()` and a limb clearance one (D5) |
| **Slot compatibility** (slot accepts item, uniform present, ear and pocket size) | ~28 in `equip_slots.dm` plus `dq_equip_has_uniform`, `dq_equip_suit_storage_takes` | ID needs `TAG_WEAR_ID` and a uniform; "too big for a pocket" | `req_acceptance_tag`, `req_acceptance_max_size`, `req_acceptance_has_uniform`, `req_acceptance_left_ear_free` exist; the table becomes `acceptance("equip")` on the slot type (D3) |
| **Size** `REQ_AT_MOST(PROP_SIZE_CLASS)` | in `equip_slots.dm` and `HOLD_MAX_SIZE` | pockets, ears, holders | `req_acceptance_max_size(size, unit)` (exists) |
| **Covering / stacking** (glove layering, accessory attach, suit over uniform) | few; most already native | | `req_acceptance_glove_layering`, `req_acceptance_accessory_attachable` exist |
| **Item flags / type allow-lists** `REQ_TYPE`, `REQ_TAG`, `HOLD_ONLY` in `hold_spec` / `suit_storage_spec` | 2 literal + ~115 `HOLD_*` (grippers 8, folders, internal storage "it can't be worn", closet `slot_loose`) | `HOLD_ONLY(list(POCKET_GENERIC, POCKET_CULT))` | `req_acceptance_type(list(...), because =)`, `req_acceptance_tag` (72 suit_storage and 7 hold done) |
| **Combat stance** `REQ_PROC(dq_pred_stance_*)` | 5 (`combat_mode.dm`) | "hold Grab" | a stance requirement as `needs()` on the combat ops, not an acceptance channel (D4) |
| **Vore consent** `REQ_BECAUSE(REQ_ON(PRED_TARGET, vore_pref_*))` | 12 in `vore_consent.dm`, 14 in custom clothes | "they don't allow digestion" | one `req(PROC_REF(x), because = ...)` per preference (D4) |
| **Access / emag / field / panel** (`REQ_ACCESS`, `REQ_FIELD*`, `REQ_ANCHORED`, `REQ_PANEL`) | none left in content (machinery moved to `req_is`/`req_rights`/`req_operable` in the earlier sweeps) | | only definitions and tests |
| Stale "was REQ_*" comments | ~25 | `/// Requirement (was REQ_* can_spin): ...` | delete |

Counts are from `git grep` and hand classification (+/- 10%); wave 0 replaces them with an exact `analyze` report.

## 2. What exists today

| Form | State | Notes |
|---|---|---|
| `acceptance(channel, reqs..., mode)` with `ACCEPTANCE_APPEND/REPLACE/EMPTY`, compiled per type table, instance overrides | on master | unkeyed entries survive parent/child compilation in order |
| `fits()`, `req_acceptance_type/tag/max_size`, `_has_uniform`, ear-free, glove layering, accessory attach, backpack takes, suit storage takes | on master | each returns null or the reason; `because =` overrides the text; reads recorded for the menu cache |
| `req_*` library (`req_is`, `req_rights`, `req_operable`, `req_worn_by_actor`, `req_not_worn`, `req(PROC_REF(x), because =)`) | on master | what `needs()` takes |
| `dq_constraint_refusal()` native-first, legacy predicate fallback; `dq_constraint_has_legacy_override()` | on master | the seam this sweep removes |
| `TYPE_TABLE(... fit_spec / equip_spec / hold_spec / suit_storage_spec)` and `dq_spec_join(..(), list(REQ_ON...))` | legacy | the declarations being converted |
| `/datum/predicate`, `dq_predicate_for`, `PRED_*`, `REQ_*` macros | legacy | deleted at the end |

AGENTS.md section 3a lists "Refusals" as **new**; for item admission it is on master as acceptance plans and `needs()` (D6 updates the table).

## 3. Decisions

### D1. Carrier for item admission (fit, equip, hold, suit_storage)
- (a) the existing `acceptance("channel", ...)` plans; finish the sweep.
- (b) re-express as `extend(/datum/act/equip | /datum/act/insert, needs(...))` per the doc's literal text.
- (c) keep both.

**Recommend (a).** It is the form 163 sites already use, it evaluates the same requirement objects, and it has pins (`dq_acceptance_*`, `dq_conversion_pin`). (b) renames the carrier
with no behaviour change; add it later only if `act/equip` becomes the one entry point. (c) is rejected (two systems is the current state).

### D2. Species fit as a table
- (a) per-type `acceptance("fit", fits(list(...)))`; the shared 19-species lists stay copied.
- (b) a registry: one named list per shared set (`RIG_FITTING`, `VOID_FITTING`) and `fits(RIG_FITTING)`.
- (c) invert it: each species declares what it can wear and each item a `FIT_*` tag.

**Recommend (b) for the three big shared lists (rig 19 species, protean 18, void 7: about 12 sites) and (a) for single-species items (teshari, vox, zaddat).** A new species is one edit, not ~25.
(c) is the cleaner model but moves data ownership to species files and must reconcile `sprite_sheets` (`dq_fits_bodytype` also reads it), so it is a later wave, not this sweep.
Reason text stays "it doesn't fit a [bodytype]".

### D3. Slot-level rules (`equip_slots.dm`)
- (a) convert each slot spec to `acceptance("equip", ...)` with the slot definition as declarer.
- (b) keep slot specs as a compiled table of requirement objects inside `/datum/slot_def`.
- (c) leave as legacy.

**Recommend (a)** (`slot_def.dm` already calls `dq_constraint_refusal`). Then `equip_slots.dm` is the last consumer of `/datum/predicate` and the language can be deleted. (c) blocks the hard ban.

### D4. Non-admission uses (combat stance, vore consent, closet `slot_loose`)
- (a) `needs(req(PROC_REF(x), because = ...))` on the owning op, procs taking `(datum/act/A)`.
- (b) fold into acceptance channels.

**Recommend (a).** They are not admission questions. Vore consent becomes one named list of `req(...)` entries shared by the vore ops; stance becomes a library requirement.
Pin behaviour first with the existing vore preference tests.

### D5. Taur and clearance procs (`taur_fit`, `limb_clearance`, `plate_clearance`)
- (a) one library requirement per meaning, reading body state through tracked reads, no side effects.
- (b) keep the proc, wrap as `req(PROC_REF(x), because =)`.

**Recommend (a) for `taur_fit` (5 sites, one meaning) and (b) for the two one-off clearances.** A requirement is pure (doc section 9): verify none of these procs write. Saddlebag and wolftaur
vest behaviour was the subject of `codex/req-burndown`'s fixes, so take its tests with it.

### D6. Ban mechanism and docs
- (a) hard-ban the macro list in `[lint.legacy_forms.lists] banned` (baseline empty), name the outcome enum explicitly as kept, delete the macros, `/datum/predicate` and `OP_LEGACY_REQ_FORMS`.
- (b) ratchet only.

**Recommend (a) at the last wave**, with the existing `legacy_form_counts.sh` ratchet through the waves. In the same commit update AGENTS.md sections 3a (Refusals row) and 3b.

### D7. Sequencing with Codex's branches
- (a) merge `codex/requirements-hard-ban-1010` and `codex/req-burndown` first, then start.
- (b) start now; rebase later.

**Recommend (a).** The hard-ban branch's `requirement_bool` and `lint_scopes.toml` edits overlap this proposal's lint changes, and `req-burndown` carries behaviour fixes to the same
saddlebag, internal-storage and cloning-owner code. The merge agent decides.

## 4. Waves

Each wave edits everything first, then one compile and one focused test batch (`dq_acceptance_*`, `dq_conversion_pin`, equip pins); fit pins per converted type; `analyze baseline --update` after.

| Wave | Content | Est. sites | End state |
|---|---|---|---|
| 0 | exact `analyze` report; delete "was REQ_*" comments; named shared fit lists (D2); library `req_acceptance_taur_body`, stance requirement | ~25 comments | counts exact; no behaviour change |
| 1 | species fit: `REQ_FITS_BODYTYPES` to `acceptance("fit", ...)` (rigs, protean, void, teshari, vox, zaddat, misc) | 29 | no `fit_spec` TYPE_TABLE left |
| 2 | equip clearance (`taur_fit` x5, `limb_clearance`, `plate_clearance`, `slot_loose`, internal storage, folders) | ~45 | no `equip_spec` left |
| 3 | holders: `HOLD_ONLY/NOT/MAX_SIZE` to `req_acceptance_type/tag/max_size` (grippers, suit storage, holsters) | ~115 | no `hold_spec`, `suit_storage_spec` left |
| 4 | slot specs (D3), stance and vore consent (D4) | ~50 | `dq_constraint_has_legacy_override` and the fallback in `dq_constraint_refusal` deleted |
| 5 | delete the language: macros, `/datum/predicate`, `predicates.dm`, `sys/requirements.dm`, adapter, 82 test lines; hard-ban the macro list | about -150 lines | `REQ_*` macros hard-banned, baseline empty; only the outcome enum remains |

Waves 1 to 3 are independent by directory. A file moves into the new tree only when fully migrated (AGENTS.md section 3c).

## 5. Risks

1. **Behaviour parity of reasons and ordering.** Acceptance plans run in order and report the first refusal; the legacy predicate generated reasons from its tree. Pin refusal text per converted type
   (existing `dq_acceptance_old_grouped` tests) and keep `because =` where the old text was custom.
2. **Parent and child merge.** `ACCEPTANCE_REPLACE` versus `APPEND` decides whether a subtype keeps its parent's rule; `dq_spec_join(..(), ...)` meant append. Convert each by that rule and test one subtype per base.
3. **Conditional or capability-owned channels crash the compiler** (`acceptance_compile_table`); a clothing capability wanting a conditional fit needs the activation-aware compiler first.
4. **Species lists.** A missed species silently stops fitting. D2(b) shared lists plus a test that every rig species wears every rig piece.
5. **Purity.** `REQ_ON` procs reading volatile state (`taur_fit`) are re-run by menus and screentips under the pure guard; a write inside would trip it.
6. **Outcome enum confusion.** The doc keeps `REQ_ANSWERED` etc.; a prefix-based ban would remove them. Ban the macro names only (D6).
7. **Overlap with Codex branches** (D7) and open equip or vore work; counts are approximate until wave 0.
