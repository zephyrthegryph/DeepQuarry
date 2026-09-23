/**
 * Combat mode (doc/rewrite/interactions.md §12, roadmap I6).
 *
 * Replaces the four intents. A Use now has one of four outcomes, chosen by:
 * * `combat_mode`: a mob action, toggled with a key (F, G or Insert; 1 and 4
 *   set it off and on) or the HUD button. With it on, hostile interactions
 *   win Use (the resolver, code/datums/interactions/resolver.dm) and legacy
 *   handlers take their harm branch; off, help and neutral ones win.
 * * `attack_variant`: Disarm or Grab. The Disarm and Grab keys (2 and 3) are
 *   held like modifiers: while one is down, clicks, bumps and struggles are
 *   disarms or grabs, and releasing it clears the variant. The Disarm and Grab
 *   interactions (the Menu on a living target, the attack category key) run
 *   one Use as that variant with use_attack_variant(). AI brains set it to
 *   hold their chosen special attack (set_use_stance()).
 *
 * Legacy handlers read the outcome with IS_HELPING/IS_HARMING/IS_DISARMING/
 * IS_GRABBING (code/__defines/combat_mode.dm) or switch on use_stance().
 */

/// Whether combat mode is on. Write it with set_combat_mode().
/mob/var/combat_mode = FALSE
/// ATTACK_VARIANT_* the current Use is running as, or null. Write it with use_attack_variant() or set_use_stance().
/mob/var/attack_variant = null

/**
 * Read-only mirror of use_stance() for the files the body rewrite owns
 * (medical, surgery, organs, species; list in doc/rewrite/interactions.md §12).
 * Only set_combat_mode() and set_attack_variant() write it. Nothing else may read
 * it: the "combat mode: a_intent" lint in tools/ci/check_grep.sh allows it only
 * in those files. It is deleted when they move to use_stance() or the IS_* macros.
 */
/mob/var/tmp/a_intent = I_HELP

/mob/Initialize(mapload)
	. = ..()
	if(combat_mode) // A type that starts in combat mode.
		sync_use_stance()

/// The outcome of a Use right now: I_HELP, I_DISARM, I_GRAB or I_HURT.
/mob/proc/use_stance()
	switch(attack_variant)
		if(ATTACK_VARIANT_DISARM)
			return I_DISARM
		if(ATTACK_VARIANT_GRAB)
			return I_GRAB
	return combat_mode ? I_HURT : I_HELP

/// Turns combat mode on or off and updates the HUD button.
/mob/proc/set_combat_mode(new_mode)
	new_mode = !!new_mode
	if(combat_mode == new_mode)
		return
	combat_mode = new_mode
	sync_use_stance()
	SEND_SIGNAL(src, COMSIG_MOB_COMBAT_MODE_CHANGED, new_mode)
	update_combat_mode_hud()

/// Sets the attack variant (an ATTACK_VARIANT_* or null).
/mob/proc/set_attack_variant(variant)
	attack_variant = variant
	sync_use_stance()

/// Keeps the body rewrite's read-only mirror current.
/mob/proc/sync_use_stance()
	PRIVATE_PROC(TRUE)
	a_intent = use_stance()

/**
 * Sets combat mode and the variant from one of the four outcomes. For AI brains,
 * admin tools and mob transformations, which pick a behaviour as data.
 */
/mob/proc/set_use_stance(stance)
	switch(stance)
		if(I_HURT)
			attack_variant = null
			set_combat_mode(TRUE)
		if(I_DISARM)
			set_attack_variant(ATTACK_VARIANT_DISARM)
		if(I_GRAB)
			set_attack_variant(ATTACK_VARIANT_GRAB)
		else
			attack_variant = null
			set_combat_mode(FALSE)
	sync_use_stance()

/// Predicate procs for REQ_COMBAT_MODE and REQ_NO_COMBAT_MODE.
/mob/proc/pred_combat_mode(mob/actor, atom/target, obj/item/held)
	return combat_mode

/mob/proc/pred_no_combat_mode(mob/actor, atom/target, obj/item/held)
	return !combat_mode

/**
 * Runs one Use on `target` as `variant` (the Disarm or Grab interaction), then
 * puts the previous variant back. Returns what the Use returned.
 */
/mob/proc/use_attack_variant(atom/target, variant)
	var/previous = attack_variant
	set_attack_variant(variant)
	var/datum/input_adapter/adapter = input_adapter()
	. = adapter.use_variant(src, target, variant)
	if(!QDELETED(src))
		set_attack_variant(previous)

// ---------------------------------------------------------------------------
// Controls

/// The combat mode key. `mode` is "toggle", "on" or "off".
/mob/verb/combat_mode_key(mode as text)
	set name = ".combat-mode"
	set hidden = TRUE
	set instant = FALSE

	switch(mode)
		if("on")
			set_combat_mode(TRUE)
		if("off")
			set_combat_mode(FALSE)
		else
			set_combat_mode(!combat_mode)

/// The Disarm and Grab keys, pressed: the variant holds until the key is released.
/mob/verb/attack_variant_key(variant as text)
	set name = ".attack-variant"
	set hidden = TRUE
	set instant = TRUE

	if(!(variant in list(ATTACK_VARIANT_DISARM, ATTACK_VARIANT_GRAB)))
		return
	set_attack_variant(variant)

/// The Disarm and Grab keys, released.
/mob/verb/attack_variant_key_release(variant as text)
	set name = ".attack-variant-release"
	set hidden = TRUE
	set instant = TRUE

	if(attack_variant == variant)
		set_attack_variant(null)

/mob/Login()
	. = ..()
	// A player taking a mob starts with no variant held: not one an AI brain
	// chose, nor a key whose release was lost when the last player left.
	if(attack_variant)
		set_attack_variant(null)

/// Redraws the combat mode HUD button, if the mob has one.
/mob/proc/update_combat_mode_hud()
	var/atom/movable/screen/combat_mode/button = hud_used?.combat_mode_button
	button?.update_for(src)

/**
 * The combat mode HUD button. It replaces the intent selector: clicking it
 * toggles combat mode. Each HUD style names its off and on icon states.
 */
/atom/movable/screen/combat_mode
	name = "combat mode"
	desc = "Toggle combat mode. With it on, attacks come first when you use things."
	var/off_state = "intent_help"
	var/on_state = "intent_harm"

/atom/movable/screen/combat_mode/Click(location, control, params)
	usr.set_combat_mode(!usr.combat_mode)
	return TRUE

/atom/movable/screen/combat_mode/proc/update_for(mob/owner)
	icon_state = owner.combat_mode ? on_state : off_state

/// Builds the combat mode button for a HUD. Callers set icon, colour, alpha and layer.
/datum/hud/proc/make_combat_mode_button(mob/owner, off_state = "intent_help", on_state = "intent_harm")
	var/atom/movable/screen/combat_mode/button = new
	button.off_state = off_state
	button.on_state = on_state
	button.screen_loc = ui_acti
	button.hud = src
	button.update_for(owner)
	combat_mode_button = button
	return button

// ---------------------------------------------------------------------------
// The Disarm and Grab interactions, listed on living targets (Menu, examine,
// the attack category key). Running one is one Use as that variant.

/datum/interaction/attack_variant
	category = INTERACTION_CAT_ATTACK
	requires = list(REQ_NOT_SELF)
	effect = /mob/living/proc/receive_attack_variant
	/// ATTACK_VARIANT_* this runs.
	var/variant

/datum/interaction/attack_variant/applies_to(atom/target)
	return isliving(target)

/datum/interaction/attack_variant/disarm
	id = "disarm"
	name = "Disarm"
	variant = ATTACK_VARIANT_DISARM
	tags = list(INTERACTION_TAG_HOSTILE)

/datum/interaction/attack_variant/grab
	id = "grab"
	name = "Grab"
	variant = ATTACK_VARIANT_GRAB

/mob/living/declare_interactions(list/into)
	. = ..()
	into += list(/datum/interaction/attack_variant/disarm, /datum/interaction/attack_variant/grab)
	// Abilities (doc/rewrite/rules.md §5): every ability type is offered to
	// every living mob; a grant (ability.dm's has_ability()) decides who can
	// actually use one.
	into += GLOB.ability_interaction_types

/// Effect of the Disarm and Grab interactions.
/mob/living/proc/receive_attack_variant(mob/actor, obj/item/held, datum/interaction/attack_variant/interaction)
	actor.use_attack_variant(src, interaction.variant)
	return TRUE
