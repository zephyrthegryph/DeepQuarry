// ---- how an item fights: the item_combat() type trait (doc/rewrite/proposals/base_vars.md) ----
//
// An item's melee numbers are per-type data in its CAPABILITIES block, not vars on /obj/item:
//
//	CAPABILITIES(/obj/item/material/knife)
//		configure(item_combat(force = 10, sharp = TRUE, edge = TRUE))
//
// force (damage), sharp (cuts), edge (dismembers), armor_penetration, windup / recovery (deciseconds; 0: the w_class default), sweep
// (TRUE: a 3-tile arc, FALSE: one tile, null: the size default), can_cleave, attack_speed (click delay), reach (tiles) and attack_verbs (the
// attack verb list, shared: never mutate it, write a new list). Read with combat_of(I).force (combat_of_type(path) for a type's
// declaration). A value that changes at run time (a lit energy sword) is written with set_<old var>(), which gives the item its own copy
// and publishes ITEM_COMBAT_KEY.

STATIC_ENTRY(item_combat)

/proc/item_combat(force = null, sharp = null, edge = null, armor_penetration = null, windup = null, recovery = null, sweep = null, can_cleave = null, attack_speed = null, reach = null, attack_verbs = null, no_attack_log = null, no_random_knockdown = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_ITEM_COMBAT, null, list("force" = force, "sharp" = sharp, "edge" = edge, "armor_penetration" = armor_penetration, "windup" = windup, "recovery" = recovery, "sweep" = sweep, "can_cleave" = can_cleave, "attack_speed" = attack_speed, "reach" = reach, "attack_verbs" = attack_verbs, "no_attack_log" = no_attack_log, "no_random_knockdown" = no_random_knockdown))

/datum/type_trait/item_combat
	var/force = 0
	var/sharp = FALSE
	var/edge = FALSE
	var/armor_penetration = 0
	var/windup = 0
	var/recovery = 0
	var/sweep = null
	var/can_cleave = FALSE
	var/attack_speed = DEFAULT_ATTACK_COOLDOWN
	var/reach = 1
	var/list/attack_verbs
	var/no_attack_log = FALSE
	var/no_random_knockdown = FALSE

/datum/type_trait/item_combat/copy_values(datum/type_trait/item_combat/into)
	into.force = force
	into.sharp = sharp
	into.edge = edge
	into.armor_penetration = armor_penetration
	into.windup = windup
	into.recovery = recovery
	into.sweep = sweep
	into.can_cleave = can_cleave
	into.attack_speed = attack_speed
	into.reach = reach
	into.attack_verbs = attack_verbs
	into.no_attack_log = no_attack_log
	into.no_random_knockdown = no_random_knockdown

/datum/entry_engine/type_trait/item_combat
	kind = ENTRY_ITEM_COMBAT
	trait_type = /datum/type_trait/item_combat
	publish_key = ITEM_COMBAT_KEY
	base_type = /obj/item
	var_names = list("force" = "force", "sharp" = "sharp", "edge" = "edge", "armor_penetration" = "armor_penetration", "melee_windup" = "windup", "melee_recovery" = "recovery", "melee_sweep" = "sweep", "can_cleave" = "can_cleave", "attackspeed" = "attack_speed", "reach" = "reach", "attack_verb" = "attack_verbs", "no_attack_log" = "no_attack_log", "no_random_knockdown" = "no_random_knockdown")

/// How `I` fights (its own values once one was set at run time). Read only.
READS_AS(/proc/combat_of, ITEM_COMBAT_KEY)
/proc/combat_of(obj/item/I) as /datum/type_trait/item_combat
	READS_FROM(I)
	return type_trait_of(I, ENTRY_ITEM_COMBAT)

/// How an item type declares it fights (no instance): the old initial(force).
/proc/combat_of_type(type) as /datum/type_trait/item_combat
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_ITEM_COMBAT)

/obj/item/proc/set_force(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "force", value)

/obj/item/proc/set_sharp(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "sharp", value)

/obj/item/proc/set_edge(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "edge", value)

/obj/item/proc/set_armor_penetration(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "armor_penetration", value)

/obj/item/proc/set_melee_windup(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "windup", value)

/obj/item/proc/set_melee_recovery(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "recovery", value)

/obj/item/proc/set_melee_sweep(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "sweep", value)

/obj/item/proc/set_can_cleave(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "can_cleave", value)

/obj/item/proc/set_attackspeed(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "attack_speed", value)

/obj/item/proc/set_reach(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "reach", value)

/obj/item/proc/set_attack_verb(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "attack_verbs", value)

/obj/item/proc/set_no_attack_log(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "no_attack_log", value)

/obj/item/proc/set_no_random_knockdown(value)
	return set_trait(src, ENTRY_ITEM_COMBAT, "no_random_knockdown", value)
