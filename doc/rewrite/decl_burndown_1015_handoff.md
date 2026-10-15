# Declarative lifecycle burn-down, 2026-10-15

Branch: `codex/decl-burndown`, based on `4ab2e15fe1`.

## Source scope and pending verification

The original baseline contains 47 actual rows: 23 visuals, 10 starting children,
6 destruction drops, 5 destruction effects, and one each of reagent initialization,
registry membership and scheduling. The supported source draft targets 43 removals;
the expected residual is four. These are source-audit counts, not an analyzer result.
No baseline has been raised or manually rewritten. No verification stamp exists yet.

A shared old-production capture ran 55 selected tests: 50 passed. The three lifecycle
fixture failures were diagnosed before repair: real legacy statue mute leakage (source-scoped stasis already ends automatically),
a flipper emag attempt correctly declining without a passenger, and hexadecimal color
case normalization. The other two failures belong to the requirements lane. A bounded
failure-only old-code repair capture is being coordinated by the root agent.

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

## Four deliberately retained rows

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

## Coverage

Real construction/destruction coverage includes identification, species bodies, frame
circuits, energy cells, flipper pAI, paired cubes, MMI adoption, landmarks, eight visual
families, four archaeological find families, released humans/ghosts/ventcrawlers, normal
and forced deletion, deletion veto, and actual crystal products. Native-reference and
parameter-completion contract fixtures are new-code tests and were excluded from the
old-production capture. The temporary `statue_legacy_stasis` selector was capture-only and has
been removed from the final source; `statue_releases_stasis` is its corrected regression.

The analyzer confirms 47 baseline rows reduced to 4, with 43 deletions and no
additions. All ratchets pass. Three focused Rust regressions pass: manual datum
Initialize classification, initialization-only registry conditions, and quoted
registry text preserving reactive conditions. The constructor-completion fixture
uses published list mutations and declared references for its fault observation.

The focused lane gate and stamp are pending. Its list includes the constructor,
visual, cleanup and reference tests above, both mandatory requirement/conversion
pins, the look pin, and AI/combat-AI regressions for living-body initialization.
Do not interpret the source checks as a passing runtime gate or completed landing.
