// The construction plan of an atom type (doc/rewrite/proposals/init_plan.md, E2). Every map-loaded atom asked the same per-type questions of a
// dozen tables on its way through InitAtom(), Initialize(), lifecycle_decls_init() and caps_init(): does it have early occupants, early params,
// early setup rows, preinit work, starting occupants, declared gas, engine init work, per-instance every() work, is it on the init_from_table
// path, is it a map resolver. Those are facts of the type. The plan is their CTOR_* bits (code/defines/engine/ctor_plan.dm), one number per type,
// built once; InitAtom() fetches it once and the steps below it read it from ctor_plan_current, so an atom answers the questions from one lookup
// and skips every step it has nothing for. A plan is built only once the declaration globals exist (init_plan_of() answers); before that every
// step takes its old path, and so it does with ctor_plan_off set (a debug toggle; dq_init_plan_parity proves both leave an instance alike).

/// type -> its CTOR_* bits (CTOR_PLANNED always set). A real global: atoms initialize while the globals are still being made.
GLOBAL_REAL_VAR(list/ctor_plans)
/// The CTOR_* bits of the atom whose Initialize() chain InitAtom() runs (GLOB.atom_initializing's), or 0. Saved and restored around a nested init.
GLOBAL_REAL_VAR(ctor_plan_current) = 0
/// TRUE runs every step's old per-type lookups (parity tests, debugging).
GLOBAL_REAL_VAR(ctor_plan_off) = FALSE
/// Plans built (the bench reads it).
GLOBAL_REAL_VAR(ctor_plans_built) = 0

/// The CTOR_* bits of A's type, or 0 while they cannot be worked out yet (the steps take their old path then).
/proc/ctor_plan_of(atom/A)
	if(ctor_plan_off)
		return 0
	var/bits = ctor_plans?[A.type]
	if(bits)
		return bits
	var/datum/type_table/T = table_of(A)
	if(!init_plan_of(A, T) || !GLOB?.init_from_table_types || !GLOB.map_resolvers || !islist(GLOB.rx_enrol_cache))
		return 0
	bits = CTOR_PLANNED
	var/datum/own_table/own = own_table_of(A)
	if(own.early_vars)
		bits |= CTOR_EARLY_STARTS
	if(own.start_vars)
		bits |= CTOR_STARTS
	if(own.engine_hooks & ENGINE_HOOK_PREINIT)
		bits |= CTOR_PREINIT
	if(own.engine_hooks & ENGINE_HOOK_INIT)
		bits |= CTOR_ENGINE_INIT
	if(T.hook_flags & ENGINE_HOOK_LIFEFORMS)
		var/datum/lifeform_plan/LP = lifeform_plan_of(A)
		if(LP.param_early)
			bits |= CTOR_PARAM_EARLY
		if(LP.setup_rows_early)
			bits |= CTOR_SETUP_EARLY
	if(GLOB.init_from_table_types[A.type])
		bits |= CTOR_FROM_TABLE
	if(GLOB.map_resolvers[A.type])
		bits |= CTOR_RESOLVER
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(A)
	if(decls && (decls.work & DECL_WORK_INIT) && decls.gas)
		bits |= CTOR_DECLS_INIT
	if(rx_type_enrols(A))
		bits |= CTOR_ENROLS
	if(!ctor_plans)
		ctor_plans = list()
	ctor_plans[A.type] = bits
	ctor_plans_built++
	return bits
