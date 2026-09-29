// Declarations that start with the instance (doc/rewrite/dx_conventions.md §5.6).
//
// Atoms run their init declarations from Initialize() / table_initialize(). A non-atom datum has
// no Initialize(), so /datum/New() starts them: a type with declarations carries
// has_declarations = TRUE (set by the declaration macros), and nothing is called by hand.

/// Set on a type by its declaration macros: /datum/New() starts the declarations of a non-atom
/// instance. A type-level default: no per-instance cost.
/datum/var/tmp/has_declarations = FALSE

/datum/New()
	if(has_declarations && !isatom(src))
		lifecycle_decls_init(src)
	return ..()
