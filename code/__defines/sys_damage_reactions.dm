// Declared damage reactions (doc/rewrite/systems.md section 12, runtime code/datums/sys/damage_reactions.dm).
//
// A fixed thing a type does when it is hit is declared next to the type, not written as an
// override of an entry point (bullet_act, emp_act, ex_act, blob_act, hitby, attack_generic ...):
//
//   DAMAGE_REACTION(/obj/machinery/firealarm, DAMAGE_PROJECTILE, PROC_REF(alarm_on_hit))
//   DAMAGE_REACTION_AFTER(/obj/machinery/door, DAMAGE_PROJECTILE, PROC_REF(update_icon_after_hit))
//   REFLECTS(/mob/living/simple_mob/slime/xenobio/silver, list(/obj/item/projectile/beam, /obj/item/projectile/energy), 100)
//   EMP_DISABLE(/obj/machinery/exonet_node, 300 SECONDS, "emp_until")
//
// Every entry adapter builds a damage packet and hands it to receive_damage(), which runs the
// type's reactions and then its sink (damage_sink()). An entry that lands nothing (a zero-damage
// round, a pulse on a type that takes no ionic damage) still delivers an empty packet when the
// type declares reactions, so a reaction fires on every hit of its trigger.
//
// Triggers: a DAMAGE_* kind (DAMAGE_BLUNT .. DAMAGE_PAIN) fires when the packet carries some of
// that kind; an entry trigger below fires on every hit through that entry, whatever it carries.
// The proc is called on the holder as proc(datum/damage_packet/packet); packet.severity is the
// EMP / explosion severity (0 for other entries). A DAMAGE_REACTION proc returning
// DAMAGE_REACTION_BLOCK stops the hit: no later reaction, no sink (and the entry skips its own
// damage). DAMAGE_REACTION_AFTER procs run after the sink, only if the holder survived it.
//
// Declarations accumulate down the type tree. A subtype changes an inherited reaction by
// overriding the reaction proc, never by overriding the entry point.

#define DAMAGE_ENTRY_PROJECTILE 101
#define DAMAGE_ENTRY_EMP 102
#define DAMAGE_ENTRY_EXPLOSION 103
#define DAMAGE_ENTRY_THROWN 104
#define DAMAGE_ENTRY_BLOB 105
#define DAMAGE_ENTRY_GENERIC 106
#define DAMAGE_ENTRY_WEAPON 107
#define DAMAGE_ENTRY_SHOCK 108

/// Entry triggers (the spelling used in declarations).
#define DAMAGE_PROJECTILE DAMAGE_ENTRY_PROJECTILE
#define DAMAGE_EMP DAMAGE_ENTRY_EMP
#define DAMAGE_EXPLOSION DAMAGE_ENTRY_EXPLOSION
#define DAMAGE_THROWN DAMAGE_ENTRY_THROWN
#define DAMAGE_BLOB DAMAGE_ENTRY_BLOB
#define DAMAGE_GENERIC_ATTACK DAMAGE_ENTRY_GENERIC
#define DAMAGE_WEAPON DAMAGE_ENTRY_WEAPON
#define DAMAGE_ELECTROCUTE DAMAGE_ENTRY_SHOCK

/// A reaction proc's return: the hit stops here.
#define DAMAGE_REACTION_BLOCK (1<<0)

/// Reaction phases (the third slot of a reaction row).
#define DAMAGE_REACTION_PHASE_BEFORE 0
#define DAMAGE_REACTION_PHASE_AFTER 1

/// Runs PROC on the holder when a hit with TRIGGER reaches receive_damage(), before the sink.
#define DAMAGE_REACTION(PATH, TRIGGER, PROC) _LIFECYCLE_DECL(PATH, add_damage_reaction(TRIGGER, PROC, DAMAGE_REACTION_PHASE_BEFORE))
/// Runs PROC on the holder after the sink applied a hit with TRIGGER (only if the holder survived).
#define DAMAGE_REACTION_AFTER(PATH, TRIGGER, PROC) _LIFECYCLE_DECL(PATH, add_damage_reaction(TRIGGER, PROC, DAMAGE_REACTION_PHASE_AFTER))
/// Projectiles matching KINDS (projectile type paths, or the obj damage types BRUTE / BURN) are
/// bounced back towards where they were fired from with CHANCE percent (a number, or the name of
/// a var on the holder), instead of hitting.
#define REFLECTS(PATH, KINDS, CHANCE) _LIFECYCLE_DECL(PATH, set_reflects(KINDS, CHANCE))
/// An EMP disables the holder for DURATION / severity: FIELD (the name of an EXPIRY_DECLAREd var,
/// CLOCK_WORLD) is extended, machinery gains EMPED, and emp_disable_changed(TRUE) runs. When the
/// expiry lapses (section 17) EMPED is cleared and emp_disable_changed(FALSE) runs.
#define EMP_DISABLE(PATH, DURATION, FIELD) _LIFECYCLE_DECL(PATH, set_emp_disable(DURATION, FIELD))
