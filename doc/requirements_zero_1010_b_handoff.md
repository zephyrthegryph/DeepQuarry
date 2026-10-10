# Boolean requirement burn-down: second sweep

Branch: `codex/requirements-zero-1010-b`, created from master `59dbe6b9a0`
and merged with the first sweep at `a87bce594a`.

## Counts and changes

`requirement_bool`: **664 -> 507**, 157 normalized rows removed.
Together with the first sweep: **831 -> 507**, 324 removed (39%).
No baseline entries, ceilings or debt annotations were added.

Converted local object and machinery checks, inherited maintenance/button gates,
SMES and lighting requirements, resleever admission, shared storage/buckle/climb
and occupant-pod requirements, injection and reagent capabilities, mob attacks,
food/table selectors, fabricator requirements and edible requirements.
Paired refusal helpers were merged or reused and obsolete wrappers removed.
Pure Boolean selectors stay Boolean through native `when(PROC_REF(...))`.
Edible's mixed selector uses its real requirement condition; fabricator's print
operation keeps its distinct busy text through the native `because` override.

## Old behavior and verification

Committed 28 old-code pins separately (`4c45709c8e`, 2,061 lines). The capture
initially failed only because the requested patch pin filename omitted `/pill`;
correcting that uncommitted input and rerunning the failed pin test passed with
clean boot, without a new compile. No runtime/self-deletion placeholder was
accepted as a capture, and no existing behavior pin was re-blessed.
Green old-code result: `data/test-runs/20261010T192434_81d9ac2831.json`.

Five new behavior tests assert exact requirement refusal and real state:
storage insertion after its acceptance rules change, occupied pod menu entry,
injector missing limb, dose mouth/limb coverage, and resleever linked-passenger
refusal plus recovery. Existing focused tests cover the other converted paths.
Post-edit lane-ready results are pending and will be recorded after the run.

## Remaining work and boundaries

507 Boolean-requirement baseline rows remain. The admin/modular-computer cohort
is still a draft while its actual compiled-requirement/UI fixtures are prepared.
Ten semantic samples were supplied before broader conversion.

The refreshed `REQ_*` inventory has 160 executable predicate-declaration lines;
other counted references are compiler/error labels or legitimate request enums.
These remaining declarations feed equipment-fit tables, predicate slot accepts
and simulation rule conditions. Native op requirements cannot replace their
list specifications alone. Equipment/slot consumers and the absent final
body-fit requirement must migrate together; no aliases or renamed macros were
introduced. Shared consumer/relations work requires coordination with its owner.

Machinery/power channels and looks, then tracked access lists, remain next.
The audits identify AccessViewer's missing invalidation and stateful legacy
draws, rather than proposing blind channel renames.

The first sweep's verification base was `87ecdb82a4`, not the later
`59dbe6b9a0`; the earlier handoff is corrected here. Its combined evidence and
authorized unstamped status remain unchanged.
