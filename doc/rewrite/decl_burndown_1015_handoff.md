# Declarative lifecycle burn-down, 2026-10-15

Branch: `codex/decl-burndown`, based on `4ab2e15fe1`.

## Source scope and pending verification

The original baseline contains 47 actual rows: 23 visuals, 10 starting children,
6 destruction drops, 5 destruction effects, and one each of reagent initialization,
registry membership and scheduling. The engine baseline update confirms 41 removals and six retained rows. The earlier
47-to-4 draft passed baseline checking but exposed two additional runtime contract gaps.
No baseline has been raised or manually rewritten. The final lane-ready receipt and focused-run JSON are the authoritative completion and stamp evidence; source is merged through master `dbf38d2b20`.

A shared old-production capture ran 55 selected tests: 50 passed. The three lifecycle
fixture failures were diagnosed before repair: real legacy statue mute leakage (source-scoped stasis already ends automatically),
a flipper emag attempt correctly declining without a passenger, and hexadecimal color
case normalization. The other two failures belong to the requirements lane. The bounded old-code repairs passed before production conversion; the capture-only statue assertion records the old defect rather than blessing it.

## Native contract extensions

`ref_one(..., starts =, starts_args =, early =, starts_after =)` can create a first
reference target without declaring ownership. Ordinary references allocate nothing.
Opt-in starts use the existing construction ordering and argument resolver; the relation
remains REF and the target survives its referrer's deletion. A constructor that deletes
or rejects its target is not adopted. `by =` resolution and opt-in starts are mutually
exclusive. Starting-reference metadata is separate from ownership/deletion policy.

`setup(..., with_params = TRUE)` is an explicit constructor-completion phase after the
complete Initialize chain and before transient parameter dropping. Default setup order
is unchanged. Rejected constructors run neither setup phase; pending completion is
consumed before calling a handler, and parameter/pending indexes are cleaned if it raises.
This is used by the MMI holder that must observe its settled owner and transient supplied
brain together. Tests cover those real paths and a deliberately failing setup.

Registry `when` predicates are initialization conditions, not live reactive predicates.
The analyzer now models that existing runtime behavior while preserving purity/boolean
validation; operation and periodic conditions remain reactive. The declaration lint
recognizes atom lifecycle semantically rather than treating explicitly called datum
business methods named Initialize as InitAtom lifecycle hooks.

## Six deliberately retained rows

* `/obj/on_destroy`: generic micro-target spill remains at its existing LINKS phase.
* `/obj/machinery/on_destroy`: generic human/camera cleanup remains at LINKS.
* `/obj/machinery/atmospherics/on_destroy`: generic ventcrawler cleanup remains at LINKS.

Moving those generic callbacks into GUARD would reorder them before untouched descendant
callbacks that inspect contents/occupants (DNA scanner, clonepod, mecha, communicator,
capture crystal and mob holders). The six concrete converted types have their own native
ending declarations; there is no global `/obj` ending binding.

* Unknown overmap sector concealment remains between overmap registration and the ship's
  registration tail. Root-time concealment changes earlier registration, while completion
  setup exposes the real sector name to flight vessel identity. No broad phase-weaving
  contract was invented for this single row.

* Living body construction remains at the original living.Initialize boundary. Robot
  Initialize constructs its components before calling its living parent; on_part_changed
  deliberately returns while body is absent. Phase-zero starts made body present during
  the partial component list and caused null.idle_draw runtimes. Replacing that guard
  with optional calls would conceal the broader early power/movement side effects.
  Original body source and ownership declaration are restored byte-for-byte.
* PDA pen presentation remains original. Master `7de6599bbc` now gives the global
  `contents_of()` and `contents_count()` native `READS_AS(..., SLOT_OCCUPANCY_KEY)`
  metadata (`code/engine/refs/containment/spatial.dm:92–117`), and their physical
  contents return values are suitable for drawing. The missing part is publication:
  `ledger.dm:348/375/416` publishes occupancy on ledger entry, exit and reslot;
  `atoms_movable.dm:451–456` notifies an existing ledger or creates one only for a
  declared-slot holder (`ledger.dm:96–100`). Direct constructor adoption likewise
  only calls an existing ledger (`atoms_initializing_EXPENSIVE.dm:111`). PDA has
  independent named ownership, not a physical contents slot, so inserting/removing
  its pen has no corresponding occupancy publication. A global `contents_of(src)`
  draw could start correctly but remain stale on removal. Adding a slot would change
  propagation, reach and destruction contracts. The actual gap is a physical-contents
  publication contract covering constructor/adoption, movement, deletion and legacy
  paths without imposing ledger topology; it is not absent read metadata or a scope
  restriction. Both pda.dm and app.dm retain original behavior. Existing constructor
  appearance assertions remain; the new live-redraw test covers privacy only.

## Coverage

Real construction/destruction coverage includes identification, species bodies, frame
circuits, energy cells, flipper pAI, paired cubes, MMI adoption, landmarks, eight visual
families, four archaeological find families, released humans/ghosts/ventcrawlers, normal
and forced deletion, deletion veto, and actual crystal products. Native-reference and
parameter-completion contract fixtures are new-code tests and were excluded from the
old-production capture. The temporary `statue_legacy_stasis` selector was capture-only and has
been removed from the final source; `statue_releases_stasis` is its corrected regression.

The analyzer confirms 47 baseline rows reduced to 6, with 41 deletions and no
additions. All ratchets pass. Three focused Rust regressions pass: manual datum
Initialize classification, initialization-only registry conditions, and quoted
registry text preserving reactive conditions. The constructor-completion fixture
uses published list mutations and declared references for its fault observation.

The focused lane gate and stamp are pending. Its list includes the constructor,
visual, cleanup and reference tests above, both mandatory requirement/conversion
pins, the look pin, and AI/combat-AI regressions for living-body initialization.
Do not interpret the source checks as a passing runtime gate or completed landing.

## First final-code gate and repair

Root ran the first coordinated gate at ce0f0c2652: production compile and DreamChecker
had zero errors/diagnostics and ratchets passed; runtime batch had 180 passing and 14
failing selectors. Concrete scoped causes were phase-zero body creation (four robot
constructor pins), unsupported PDA slot reads (two visual tests), and a fixture passing
FALSE to keeps_if instead of the required pure callback. The body/PDA conversions are
withdrawn, not papered over; the rejection fixture now uses a genuine FALSE-returning
callback. The unchanged-master diagnostic batch reproduced both healer-fixture consent failures and the incompatible living attacker reference. Those concrete causes are repaired, and prone density now composes through its native stat contribution; both new density regressions await the final repair batch.
Look-pin differences must be reconsidered after those reversals, not blessed blindly.
The final baseline update, failure-only repair, stamp and push remain pending root.

### Look-fixture explosion cleanup

The first combined run reported two explosion particles during `dx_menu_order`, which runs after the look sweep. Look captures delete real mated telecubes; their ending hook submits blast work at the independent mate’s turf, beyond an immediate floor sweep. All manual look-capture/probe/drain deletions now use one test-only disposal helper that moves only the actual telecube pair to nullspace after observation and before real deletion. It neither clears queues nor changes production behavior. `dq_look_telecube_cleanup` asserts real reciprocal pairing on the floor, unchanged capture rows, actual unlinking, the independent mate’s survival, and unchanged pending/submission counts. This repair has not yet been executed; root owns verification.


## Final repair scope

The final focused repair list includes the 14 diagnosed failures from the first native runtime gate, two actual prone-density regressions, telecube teardown, and both typed-constructor regressions (19 selectors, including both mandatory pins). Earlier compilation had zero errors and DreamChecker diagnostics. Root runs the final lane-ready gate and reports its exact receipt and pushed commit; this document does not substitute evidence from earlier passing tests for that gate. No full suite is run, and runtime failures are not re-blessed. The native `devour` key added by master `2136172edc` is the only inherited inventory refresh in this repair cohort.

## Compiler cross-check

The repair gate explicitly uses DreamMaker, the supported production cross-check documented in doc/testing.md. A same-plan requirements-lane diagnostic after master 663e85e2ae changed the default to native exposed host-dependent look sampling (the first 24 vars are selected before the analyzer-plan filter). Existing goldens are retained; no appearance differences from that sampler are blessed here. The actual final receipt and JSON record the backend and gate result.
