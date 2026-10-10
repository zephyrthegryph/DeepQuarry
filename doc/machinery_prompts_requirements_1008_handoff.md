# Machinery prompts and requirements handoff (2026-10-08)

Branch: codex/machinery-prompts-reqs-1008, based on origin/master 4375b80682 through tools/dq_merge_master.sh. Batch14 includes the previous AIcore work; the old branch was left unchanged. No master push.

## Converted

- Medical kiosk: native claims cover its service question, then a five-second scan. Cancellation, timeout, panel opening, movement and competing patient paths retain real state/custody assertions. No standalone request or task_start remains.
- Cryopod: passenger consent uses asks(answerer), with loader actor unchanged. Decline/cancel/deletion/movement and clientless fallback use native waits. Removed the legacy consent request type/callback and task_timed.
- Suit cycler: real shock runs in starts and returns a reason before begins/wait. Empty grabs retain the original shock-first ordering, then silently stop. Removed task_timed.
- All three files added to timed_forms_converted; three remaining legacy task call sites -> zero in those files.
- User-approved engine guard returns after a starts handler synchronously cancels/deletes its pending op. Real powered shock tests exercise cancellation, release of claims and absence of a late timer.
- Four former requirement adapters replaced with native declarations: CableLayer any_of(full cable, on); bomb tester any empty tank relation; painter operable selection and empty insert requirement. Exact CableLayer/painter refusal strings are tested.

## Remaining requirements

No executable uppercase REQ macros remain in the two requested folders. The complete old three-argument delegate inventory fell from 43 to 39 (38 machinery, one power across24files). Current custom req(PROC_REF(...)) still booleanizes its result; it cannot consume a single null-to-allow / reason-to-refuse callback. No engine adapter or effect workaround was invented. Exact inventory, existing declarative alternatives and protocol evidence: machinery_requirements_1008_gap.md; gap also recorded in doc/rewrite/framework_gaps.md.

## Pins and baselines

Old-code behavior pins passed before conversion at e03f6c58d6, recorded in e6e9a6b5a3. The scoped conversion pin passed after conversion. Only cryopod changed:13 added menu rows for the native grab operation's menu binding. Per-class causes for all three classes are in intended_changes.md. The identical reviewed cryopod capture is also in the canonical pins directory. Other scoped pins are unchanged. No global sweep was blessed.

Baseline update only reduced escape_hatches usr_content 133 ->132, reflecting already-merged debt removal. No raised baseline, ceiling or new ALLOW. The draw-items lane's charge/shots files were untouched.

## Verification

First prompt compile:0errors,50existingwarnings; lint/DreamChecker0diagnostics and ratchets clean. Focus17:16passed,1failed; actual powered cycler shock found the engine reentrant-cancellation runtime. This prompted the approved guard.

Final production compile:0errors,50existingwarnings; fresh lint/DreamChecker0diagnostics and ratchets clean. Focus24:22passed,2failed,0skipped,zero runtimes. Every prompt, passenger, clientless, powered-shock/empty-grab and engine-form regression passed. Result:data/test-runs/20261008T224315_246f5fe4e4.json. No full suite, shards or Rust build ran.

The two failures were newly added painter/bomb-tester tests using plain clicks: existing interface-generated ui_open at default priority outranks their default-minus-one loading ops. Requirement-menu rows passed. Tests now select the public loading menu ops and keep real state/custody/refusal assertions, rather than calling effect handlers. That separate preexisting plain-click ranking defect is documented in the gap report; no input priority was changed or blessed. Test fixtures now restore lazy diagnostic globals as well.

Approved eight-test repair batch: 8 passed, 0 failed, 0 skipped; compile 0 errors, 50 existing warnings. Result: data/test-runs/20261009T015422_e4eb0ec495.json. Corrected menu-input tests, fixture cleanup, real powered cycler shock/empty grab and reentrant starts refusal all passed.

Logs:data/codex-machinery/prompts-reqs-1008/{prompts,final}-{lint,ratchets,focused}.log.
