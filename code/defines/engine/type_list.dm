// Per-type lists (doc/rewrite/dx_conventions.md §2). Runtime: code/datums/declarations/type_list.dm.
//
// A per-type list is an override of a well-known proc that returns a literal:
//
//	/obj/machinery/iv_drip/interactions()
//		return ..() + list(hand("Remove container", PROC_REF(detach)))
//
// The framework reads it through type_list(D, PROC_REF(interactions)): called on the first
// instance of each type, cached per (type, proc), shared. The proc must not read instance state;
// test builds compare the first two instances' results and runtime on a difference.

/// The runtime message a test build raises when a per-type list read instance state.
#define TYPE_LIST_IMPURE(TYPE, PROC) "TYPE_LIST: [TYPE].[PROC] read instance state: two instances returned different lists"
