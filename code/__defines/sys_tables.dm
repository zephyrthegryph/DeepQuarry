// Per-type constant tables (doc/rewrite/systems.md section 7).
//
//   TYPE_TABLE_DECLARE(/datum/cargo_market_profile, accepted_departments, null)
//   TYPE_TABLE(/datum/cargo_market_profile/medical_goods, accepted_departments, list(DEPARTMENT_MEDICAL))
//   var/list/depts = TYPE_TABLE_GET(profile, accepted_departments)   // shared, read-only
//
// A table is inherited and overridable per subtype. Its value is built once per concrete type
// (on first read) and stored in the shared cache `tt_<name>`, keyed by type path: a read is one
// list index, with nothing allocated per instance or per call. Table names are global: two
// declarations of the same name on different roots collide at compile time (rename one).
//
// Values handed out are SHARED. Never write into one; test builds runtime on a mutation (the
// shared-cache guard). A caller that needs its own list takes TYPE_TABLE_COPY().
//
// Copy on write, for an instance var that starts as the type's table and is edited per instance:
//
//   /obj/machinery/vending/var/list/products          // null until written (or map-varedited)
//   TYPE_TABLE(/obj/machinery/vending/coffee, products, list(...))
//   var/list/p = COW_READ(src, products)               // the instance's list, else the table
//   COW_LIST(src, products)[/obj/item/soap] = 3        // copies the table into the var first

/// Declares table N on root type T with default value V (usually null or a list). Once per name.
#define TYPE_TABLE_DECLARE(T, N, V...) T/proc/_tt_##N() {return V};/proc/_tt_build_##N(datum/instance) {return call(instance, TYPE_PROC_REF(T, _tt_##N))()};DECLARE_SHARED_CACHE(tt_##N, GLOBAL_PROC_REF(_tt_build_##N), SC_NEVER)
/// Overrides table N for type T (and its subtypes, until they override it again).
#define TYPE_TABLE(T, N, V...) T/_tt_##N() {return V}
/// The shared table N of instance I's type. Read-only.
#define TYPE_TABLE_GET(I, N) CACHED_KEY(tt_##N, (I).type, I)
/// A private copy of table N of I's type (a new empty list when the table is null).
#define TYPE_TABLE_COPY(I, N) type_table_copy(TYPE_TABLE_GET(I, N))
/// Instance var N of I if set, else I's type table N. Read-only.
#define COW_READ(I, N) ((I).N || TYPE_TABLE_GET(I, N))
/// Instance var N of I, copied from the type table on first use. Writable.
#define COW_LIST(I, N) ((I).N || ((I).N = TYPE_TABLE_COPY(I, N)))
