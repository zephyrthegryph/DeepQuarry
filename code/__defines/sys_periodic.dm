// Periodic work declared by state (doc/rewrite/systems.md section 5, runtime code/datums/sys/periodic.dm).
//
// Periodic work that runs while some state holds is declared next to the type, not started and
// stopped by hand around every write of that state:
//
//   DECLARE_PERIODIC_WHILE(/obj/item/pinpointer, PERIODIC_SLOW, "active")
//   DECLARE_PERIODIC_WHILE_ALL(/obj/item/pinpointer, PERIODIC_SLOW, list("active", "powered"))
//   DECLARE_REPEAT(/obj/machinery/magnetic_controller, "magnet_delay", magnet_move_step, "moving")
//
// A FIELD is a declared field of the type (OM_FIELD, OM_FLAG_FIELD, OM_FIELD_SETTER or a derived
// OM_DERIVE_FIELD such as `operable`); "!name" means "while it is false". The declaration watches
// the fields' change channels: when they all hold the work starts, when one stops holding the
// work stops. At materialize it starts when they hold; at dematerialize it stops.
//
// DECLARE_PERIODIC_WHILE: CADENCE is a periodic pipeline (PERIODIC_SLOW, PERIODIC_SECOND, ...),
// whose body is periodic_step(). The body never
// guards on the declared fields and never returns PROCESS_KILL for them (it may still return
// PROCESS_KILL for work of its own that ran out; the next raise of a field channel re-evaluates).
// While the fields don't hold, nothing else can start the work either: om_task_periodic() refuses it. One per type; a
// subtype's declaration replaces its parent's.
//
// DECLARE_REPEAT(TYPE, DELAY, PROC, FIELD): TYPE/proc/PROC runs every DELAY while FIELD holds
// (FIELD null: always while materialized). DELAY is a time, or the name of a var or proc of the
// type read each time it re-arms. PROC takes no arguments and returns nothing; returning
// REPEAT_STOP ends the loop until the field next changes to holding. Several per type (one per
// PROC); a subtype declaring the same PROC replaces it. The pending run is the timer slot
// "sys_repeat:PROC", owned and cancelled with the holder.
//
// Non-atom datums have no materialize: a non-atom type with a declaration calls
// lifecycle_decls_init(src) from its New() (the declarative-lifecycle rule for every non-atom
// declaration), which starts the declaration.

/// Returned by a DECLARE_REPEAT proc: stop repeating until the field changes to holding again.
#define REPEAT_STOP "__repeat_stop"

#define DECLARE_PERIODIC_WHILE_ALL(T, CADENCE, FIELDS) /datum/sys_periodic_def##T/while_state { of = T; cadence = CADENCE; fields = FIELDS };_LIFECYCLE_DECL(T, add_sys_periodic())
#define DECLARE_PERIODIC_WHILE(T, CADENCE, FIELD) DECLARE_PERIODIC_WHILE_ALL(T, CADENCE, list(FIELD))
#define DECLARE_REPEAT(T, DELAY, PROC, FIELD) /datum/sys_periodic_def##T/repeat_##PROC { of = T; delay = DELAY; repeat_proc = TYPE_PROC_REF(T, PROC); field = FIELD };_LIFECYCLE_DECL(T, add_sys_periodic())
