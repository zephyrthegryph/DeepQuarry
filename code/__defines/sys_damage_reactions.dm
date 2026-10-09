// Damage reactions (doc/rewrite/reactions.md section 1b, runtime code/datums/sys/damage_reactions.dm).
//
// A fixed thing a type does when it is hit is a reaction on the damage operation, declared in reactions() next to
// the type, never an override of an entry point (bullet_act, emp_act, ex_act, blob_act, hitby, attack_generic ...):
//
//	/obj/machinery/firealarm/reactions()
//		. = ..()
//		. += before_op(damage(DAMAGE_EMP), PROC_REF(firealarm_emp))        // may block the hit
//		. += after_op(damage(DAMAGE_PROJECTILE), PROC_REF(flicker))        // after the sink, if it survived
//	CAPABILITY(/mob/living/simple_mob/slime/xenobio/silver, reflects(list(/obj/item/projectile/beam), 100))
//
// Every entry adapter builds a damage packet and hands it to receive_damage(), which runs the before_op reactions of
// the matching damage keys, then the sink (damage_sink()), then the after_op ones. An entry that lands nothing (a
// zero-damage round, a pulse on a type that takes no ionic damage) still delivers an empty packet when the type has
// damage reactions, so a reaction fires on every hit of its trigger. Capabilities contribute damage reactions
// through their own reactions() (reflects() does).
//
// Triggers: a DAMAGE_* kind (DAMAGE_BLUNT .. DAMAGE_PAIN) fires when the packet carries some of that kind; an entry
// trigger below fires on every hit through that entry, whatever it carries. The handler is called on the holder as
// handler(datum/damage_packet/packet) (a GLOBAL_PROC_REF gets the holder first); packet.severity is the EMP /
// explosion severity (0 for other entries). A before_op handler returning DAMAGE_REACTION_BLOCK (or any reason: a
// /datum/msg type or text) stops the hit: no later reaction, no sink (and the entry skips its own damage).
//
// A subtype changes an inherited reaction by overriding the handler proc, never by overriding the entry point.

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

/// Reaction phases (the third slot of a damage row, /datum/rx_table/var/damage_rows).
#define DAMAGE_REACTION_PHASE_BEFORE 0
#define DAMAGE_REACTION_PHASE_AFTER 1

/// The prefix of a damage key (damage(trigger)).
#define DAMAGE_KEY_PREFIX "damage:"

// ---- LEGACY: thin wrappers over the forms above (the codemod moves their sites; tools/ci ratchets them) ----
/// before_op(damage(TRIGGER), PROC) in PATH's reactions().
#define DAMAGE_REACTION(PATH, TRIGGER, PROC) ##PATH/reactions() { . = ..(); . += before_op(damage(TRIGGER), PROC); }
/// after_op(damage(TRIGGER), PROC) in PATH's reactions().
#define DAMAGE_REACTION_AFTER(PATH, TRIGGER, PROC) ##PATH/reactions() { . = ..(); . += after_op(damage(TRIGGER), PROC); }
/// CAPABILITY(PATH, reflects(KINDS, CHANCE)).
#define REFLECTS(PATH, KINDS, CHANCE) CAPABILITY(PATH, reflects(KINDS, CHANCE))
