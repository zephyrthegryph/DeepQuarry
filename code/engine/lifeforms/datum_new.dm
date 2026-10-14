// Declarations that start with the instance (doc/rewrite/dx_conventions.md §5.6).
//
// Atoms run their init declarations from Initialize() / table_initialize(). A non-atom datum has
// no Initialize(), so /datum/New() starts them: a type with declarations carries
// has_declarations = TRUE (set by the declaration macros), and nothing is called by hand.

/// Set on a type by its declaration macros: /datum/New() starts the declarations of a non-atom
/// instance. A type-level default: no per-instance cost.
/datum/var/tmp/has_declarations = FALSE

/datum/New()
	if(!isatom(src))
		if(lifeform_declared)
			lifeform_datum_new(src) // the lifecycle forms of a plain datum, its make() record and its owns_* starts = (code/engine/lifeforms/)
		else if(has_declarations)
			lifecycle_initialize(src)
		if(rx_type_enrols(src))
			rx_enrol(src) // per-instance every() work: a type that declares it is enrolled by being made
	return ..()
