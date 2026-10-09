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
 * The two together are the Use's stance (I_HELP, I_DISARM, I_GRAB, I_HURT).
 * Nothing but the input layer reads it (input_stance()): ops declare the
 * stance they answer (stance(I_X)), the resolver offers only the ones that
 * match, and the effect of the op that runs takes the intent from its own
 * declaration (or from the `stance` argument its caller passes on).
 */

/// Whether combat mode is on. Write it with set_combat_mode().
/mob/var/combat_mode = FALSE
/// ATTACK_VARIANT_* the current Use is running as, or null. Write it with use_attack_variant() or set_use_stance().
/mob/var/attack_variant = null

/**
 * The stance of the input this mob is making now: I_HELP, I_DISARM, I_GRAB or I_HURT.
 * The input layer's reading of combat mode and the held variant. Only the
 * resolver's stance clauses, the actor adapters and the mob-action entries
 * (click, bump, resist, throw, an AI brain's own choice) call it; everything
 * downstream gets the stance from the interaction that ran or as an argument.
 * tools/ci/stance_examine_lint.py enforces the allowlist.
 */
/mob/proc/input_stance()
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
	update_combat_mode_hud()

/// Sets the attack variant (an ATTACK_VARIANT_* or null).
/mob/proc/set_attack_variant(variant)
	attack_variant = variant

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

/// Stance clauses (dq_stance_clause()): the actor's input has that stance.
/proc/dq_pred_stance_help(mob/actor, atom/target, obj/item/held)
	return istype(actor) && actor.input_stance() == I_HELP

/proc/dq_pred_stance_disarm(mob/actor, atom/target, obj/item/held)
	return istype(actor) && actor.input_stance() == I_DISARM

/proc/dq_pred_stance_grab(mob/actor, atom/target, obj/item/held)
	return istype(actor) && actor.input_stance() == I_GRAB

/proc/dq_pred_stance_harm(mob/actor, atom/target, obj/item/held)
	return istype(actor) && actor.input_stance() == I_HURT

/// The selector clause for an interaction that answers `stance`, with the reason shown when it doesn't match.
/proc/dq_stance_clause(stance)
	switch(stance)
		if(I_HELP)
			return REQ_PROC(/proc/dq_pred_stance_help, "combat mode is on")
		if(I_DISARM)
			return REQ_PROC(/proc/dq_pred_stance_disarm, "hold Disarm")
		if(I_GRAB)
			return REQ_PROC(/proc/dq_pred_stance_grab, "hold Grab")
		if(I_HURT)
			return REQ_PROC(/proc/dq_pred_stance_harm, "combat mode is off")
	CRASH("dq_stance_clause: unknown stance [stance]")

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

CAPABILITIES(/atom/movable/screen/combat_mode)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/combat_mode/proc/click_input(datum/act/input/A)
	return toggle_combat_mode_with_actor(A.actor)

/atom/movable/screen/combat_mode/proc/toggle_combat_mode_with_actor(mob/user)
	if(user)
		user.set_combat_mode(!user.combat_mode)
	return TRUE

/atom/movable/screen/combat_mode/proc/update_for(mob/owner)
	icon_state = owner.combat_mode ? on_state : off_state

/// Builds the combat mode button for a HUD. Callers set icon, colour, alpha and layer.
/datum/hud/proc/make_combat_mode_button(mob/owner, off_state = "intent_help", on_state = "intent_harm")
	var/atom/movable/screen/combat_mode/button = new
	button.off_state = off_state
	button.on_state = on_state
	button.screen_loc = ui_acti
	rel_set(button, nameof(button.hud), src)
	button.update_for(owner)
	// The caller owns the button through one of its screen lists (adding); this names it.
	rel_set(src, nameof(combat_mode_button), button)
	return button

// ---------------------------------------------------------------------------
// The Disarm and Grab ops, listed on living targets (Menu, examine, the attack category key). Running one is one Use as that variant.
// Every living mob brings this capability (CAPABILITIES(/mob/living), combat_ai/integration/mob_living.dm).

MSG_DEF_SELF(attack_variant/self, "You can't do that to yourself.")

CAPABILITY_DEF(attack_variants, CAP_ATTACK_VARIANTS, key = NONE)

/datum/capability/def/attack_variants/entries()
	return list(
		op("disarm", menu(), label("Disarm"),
			needs(req(TYPE_PROC_REF(/mob/living, attack_variant_not_self), because = MSG(attack_variant/self))),
			then(TYPE_PROC_REF(/mob/living, attack_variant_disarm))),
		op("grab", menu(), label("Grab"),
			needs(req(TYPE_PROC_REF(/mob/living, attack_variant_not_self), because = MSG(attack_variant/self))),
			then(TYPE_PROC_REF(/mob/living, attack_variant_grab))))

/// The actor is somebody else.
/mob/living/proc/attack_variant_not_self(datum/act/op/A)
	return A.actor != src

/mob/living/proc/attack_variant_disarm(datum/act/op/A)
	A.actor.use_attack_variant(src, ATTACK_VARIANT_DISARM)
	return OP_OK

/mob/living/proc/attack_variant_grab(datum/act/op/A)
	A.actor.use_attack_variant(src, ATTACK_VARIANT_GRAB)
	return OP_OK
