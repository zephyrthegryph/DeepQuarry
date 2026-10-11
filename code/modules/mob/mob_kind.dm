// What kind of mob this is: the mob_kind() type trait (doc/rewrite/proposals/base_vars.md). Class, unarmed attack delay and look, death
// message, emote kind and the like are per-type data in CAPABILITIES (configure(mob_kind(mob_class = MOB_CLASS_ANIMAL))), read with
// kind_of(M).mob_class; set_<old var>() writes the mob's own copy.

STATIC_ENTRY(mob_kind)

/proc/mob_kind(mob_class = null, attack_cooldown = null, self_surgery = null, inventory_panel = null, can_be_antagged = null, use_me = null, emote_type = null, death_message = null, attack_icon = null, attack_icon_state = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_MOB_KIND, null, list("mob_class" = mob_class, "attack_cooldown" = attack_cooldown, "self_surgery" = self_surgery, "inventory_panel" = inventory_panel, "can_be_antagged" = can_be_antagged, "use_me" = use_me, "emote_type" = emote_type, "death_message" = death_message, "attack_icon" = attack_icon, "attack_icon_state" = attack_icon_state))

/datum/type_trait/mob_kind
	var/mob_class	// MOB_CLASS_*: human, mechanical, animal, ... (projectile effects)
	var/attack_cooldown = DEFAULT_ATTACK_COOLDOWN	// its unarmed click delay
	var/self_surgery = FALSE	// can operate on itself
	var/inventory_panel = /datum/inventory_panel	// the inventory window it opens
	var/can_be_antagged = FALSE	// auto-antag modes may pick it
	var/use_me = 1	// may use the me verb
	var/emote_type = 1	// 1: seen emotes, 2: heard
	var/death_message = "seizes up and falls limp..."	// what others see when it dies
	var/attack_icon	// the icon of its unarmed attack animation
	var/attack_icon_state	// its state

/datum/type_trait/mob_kind/copy_values(datum/type_trait/mob_kind/into)
	into.mob_class = mob_class
	into.attack_cooldown = attack_cooldown
	into.self_surgery = self_surgery
	into.inventory_panel = inventory_panel
	into.can_be_antagged = can_be_antagged
	into.use_me = use_me
	into.emote_type = emote_type
	into.death_message = death_message
	into.attack_icon = attack_icon
	into.attack_icon_state = attack_icon_state

/datum/entry_engine/type_trait/mob_kind
	kind = ENTRY_MOB_KIND
	trait_type = /datum/type_trait/mob_kind
	publish_key = MOB_KIND_KEY
	base_type = /mob
	var_names = list("mob_class" = "mob_class", "base_attack_cooldown" = "attack_cooldown", "allow_self_surgery" = "self_surgery", "inventory_panel_type" = "inventory_panel", "can_be_antagged" = "can_be_antagged", "use_me" = "use_me", "emote_type" = "emote_type", "death_message" = "death_message", "attack_icon" = "attack_icon", "attack_icon_state" = "attack_icon_state")

/// The holder's mob_kind values (its own once one was set at run time). Read only.
READS_AS(/proc/kind_of, MOB_KIND_KEY)
/proc/kind_of(mob/holder) as /datum/type_trait/mob_kind
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_MOB_KIND)

/// What a type declares (no instance): the old initial().
/proc/kind_of_type(type) as /datum/type_trait/mob_kind
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_MOB_KIND)

/mob/proc/set_mob_class(value)
	return set_trait(src, ENTRY_MOB_KIND, "mob_class", value)

/mob/proc/set_base_attack_cooldown(value)
	return set_trait(src, ENTRY_MOB_KIND, "attack_cooldown", value)

/mob/proc/set_allow_self_surgery(value)
	return set_trait(src, ENTRY_MOB_KIND, "self_surgery", value)

/mob/proc/set_inventory_panel_type(value)
	return set_trait(src, ENTRY_MOB_KIND, "inventory_panel", value)

/mob/proc/set_can_be_antagged(value)
	return set_trait(src, ENTRY_MOB_KIND, "can_be_antagged", value)

/mob/proc/set_use_me(value)
	return set_trait(src, ENTRY_MOB_KIND, "use_me", value)

/mob/proc/set_emote_type(value)
	return set_trait(src, ENTRY_MOB_KIND, "emote_type", value)

/mob/proc/set_death_message(value)
	return set_trait(src, ENTRY_MOB_KIND, "death_message", value)

/mob/proc/set_attack_icon(value)
	return set_trait(src, ENTRY_MOB_KIND, "attack_icon", value)

/mob/proc/set_attack_icon_state(value)
	return set_trait(src, ENTRY_MOB_KIND, "attack_icon_state", value)
