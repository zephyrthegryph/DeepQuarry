// CTOR_* bits of a construction plan (code/engine/declare/ctor_plan.dm).
/// Has owns_*(early = TRUE) starting occupants (own_table.early_vars).
#define CTOR_EARLY_STARTS (1<<0)
/// Declares a param(early = TRUE) (lifeform_plan.param_early).
#define CTOR_PARAM_EARLY (1<<1)
/// Declares a setup(early = TRUE) (lifeform_plan.setup_rows_early).
#define CTOR_SETUP_EARLY (1<<2)
/// On the init_from_table path (GLOB.init_from_table_types).
#define CTOR_FROM_TABLE (1<<3)
/// A map resolver (GLOB.map_resolvers).
#define CTOR_RESOLVER (1<<4)
/// engine_holder_preinit() has work (own_table.engine_hooks & ENGINE_HOOK_PREINIT).
#define CTOR_PREINIT (1<<5)
/// Has starting occupants (own_table.start_vars).
#define CTOR_STARTS (1<<6)
/// Its lifecycle declarations have init work (gas).
#define CTOR_DECLS_INIT (1<<7)
/// engine_holder_init() has work (own_table.engine_hooks & ENGINE_HOOK_INIT).
#define CTOR_ENGINE_INIT (1<<8)
/// Declares per-instance every() work (rx_type_enrols()).
#define CTOR_ENROLS (1<<9)
/// engine_holder_init()'s only work is noting the setup() rows (the init plan's one step is the lifecycle forms, and their only init form is plain
/// setup rows): caps_init() skips the engine init and InitAtom() runs the rows itself, without setup_pending.
#define CTOR_SETUP_ONLY (1<<11)
/// Set on every built plan, so a plan with no other fact is still told from "not built".
#define CTOR_PLANNED (1<<10)
/// The CTOR_* bits of `D` when it is the atom whose Initialize() chain InitAtom() is running, else 0 (the caller takes its old path).
#define CTOR_PLAN_FOR(D) ((ctor_plan_current && (D) == GLOB.atom_initializing) ? ctor_plan_current : 0)
