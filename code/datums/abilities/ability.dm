/**
 * Abilities (doc/rewrite/rules.md §5): an interaction the actor performs on
 * themselves or a target. Built on I2 (code/datums/interactions/interaction.dm)
 * - an ability is a /datum/interaction/ability, one shared singleton per type,
 * offered by every living mob's declare_interactions() (combat_mode.dm's
 * /mob/living override) and filtered per actor by a **grant** (below) plus
 * whatever the ability itself requires.
 *
 * ---- Grants and sources ----
 *
 * An ability only runs for an actor who has been granted it. A grant is
 * source-tracked: `grant_ability(actor, id, source)` records that `source`
 * (a species datum, a trait, an item, a component instance, ...) grants `id`;
 * `revoke_ability(actor, id, source)` removes just that source's claim. The
 * ability stays available as long as ANY source remains - two traits granting
 * the same ability, or an item and an innate grant overlapping, don't fight
 * each other or need reference counting by the caller. Whoever creates a
 * grant owns revoking it: a component revokes in its Destroy()/UnregisterFromParent,
 * an item revokes on unequip, a status revokes on its own removal - the same
 * discipline as signals and modifiers.
 *
 *	// Granting (species, trait, item, component, ...):
 *	L.grant_ability(ABILITY_ID_SHADEKIN_PHASE_SHIFT, SK) // SK is the source
 *	// ... and on that source's removal:
 *	L.revoke_ability(ABILITY_ID_SHADEKIN_PHASE_SHIFT, SK)
 *
 *	// Reading (rare - why_not()/attempt() already check this):
 *	L.has_ability(id)          // any source grants it right now?
 *	L.ability_sources(id)      // the list of sources, for UI/debugging
 *
 * Species `inherent_verbs` grants and item/trait ability grants are meant to
 * move onto this same API (DQ Medical's protean powers registry is the first
 * consumer built on it): call grant_ability()/revoke_ability() from wherever
 * the source is added/removed, same as above.
 *
 * ---- Requirements, cost and effect (rules.md's "Requirements / Cost / Commit") ----
 * - Requirements are `requires` clauses, same as any interaction, plus one
 *   REQ_RESOURCE() clause when the ability spends a resource.
 * - Cost is a formula over properties/state, computed by the REQ_RESOURCE
 *   cost proc and cached on the actor so pay_cost() spends exactly the amount
 *   that was checked - never a value recomputed after time has passed.
 * - Commit happens in attempt() (interaction.dm): why_not() must pass in full
 *   BEFORE pay_cost() runs, and pay_cost() runs BEFORE the effect. An ability
 *   can never spend its cost and then fail a requirement - that ordering is
 *   the framework's, not each ability's, so it can't be gotten wrong per-ability
 *   the way the legacy shadekin phase shift did (doc/rewrite/fixes.md B13).
 *
 * Declaring a self-targeted one (the common shape - phase shift, dark
 * respite, create shade, ...; REQ_SELF is enforced by the /self subtype so it
 * can never run against some OTHER mob, however it was reached):
 *
 *	/datum/interaction/ability/self/example
 *		id = "example"
 *		name = "Example"
 *		category = ABILITY_CAT_UTILITY
 *		requires = list(REQ_CONSCIOUS, REQ_RESOURCE(/mob/living/proc/dq_example_afford))
 *		effect = /mob/living/proc/dq_do_example
 *
 * `effect` runs as target.effect(actor, held, interaction); for a /self
 * ability target and actor are the same mob, so this is simply a proc on the
 * acting mob. A targeted ability (heal another creature, ...) instead extends
 * /datum/interaction/ability directly and is declared on whatever can be its
 * target (declare_interactions()), with `effect` running on the target.
 */
/datum/interaction/ability
	tags = list(INTERACTION_TAG_ABILITY)
	/// Not reachable through a click or tool; only the Menu and its keybind.
	default_action = null

/datum/interaction/ability/applies_to(atom/target)
	return isliving(target)

/// A grant is checked before anything in `requires`: an actor who was never
/// granted this ability never even gets a requirements-based reason - "you
/// don't have that ability" is the one answer, from one place.
/datum/interaction/ability/why_not(mob/actor, atom/target, obj/item/held)
	if(!isliving(actor))
		return "you don't have that ability"
	var/mob/living/L = actor
	if(!L.has_ability(id))
		return "you don't have that ability"
	return ..()

/**
 * A self-targeted ability: the common shape (phase shift, dark respite, ...).
 * An ability that instead acts on another creature (heal another shadekin, ...)
 * extends /datum/interaction/ability directly and is declared wherever it can
 * be targeted, not just on the actor's own type.
 */
/datum/interaction/ability/self

/datum/interaction/ability/self/full_spec()
	// REQ_SELF first: this ability must never run with some OTHER mob as the
	// target, however it was reached (Menu on a third party, a stale keybind,
	// ...). Every subtype's own requires are checked only once this holds.
	return list(REQ_SELF) + ..()

/**
 * A targeted ability whose target isn't known in advance (self, hover, or a
 * click) but is chosen interactively from a candidate list at use time -
 * "feed the nearest mob", "mount someone", "heal whoever's closest and hurt" -
 * the shape the legacy verb argument syntax (`mob/living/T in living_mobs(1)`)
 * used to give for free. Subtypes override candidates() (and optionally
 * picker_title/picker_prompt); the keybind path (dq_use_ability()) calls
 * pick_target() instead of the hover/self fallback. Reached through the Menu
 * too, same as any ability - there candidates() isn't consulted, the target
 * is whatever the Menu is open on, same as a plain targeted ability.
 *
 *	/datum/interaction/ability/picker/example
 *		id = "example"
 *		name = "Example"
 *		picker_title = "Pick a target"
 *		picker_prompt = "Feed whom?"
 *		effect = /mob/living/proc/dq_do_example
 *
 *	/datum/interaction/ability/picker/example/candidates(mob/living/actor)
 *		return living_mobs_in_view(1, actor) - actor
 */
/datum/interaction/ability/picker
	/// tgui_input_list()'s title.
	var/picker_title = "Choose a target"
	/// tgui_input_list()'s message.
	var/picker_prompt = "Select:"

/// The atoms `actor` could target right now, or an empty list for none. Called
/// fresh every time (never cached): the world moves between key presses.
/datum/interaction/ability/picker/proc/candidates(mob/living/actor)
	return list()

/**
 * Asks `actor` to pick one candidate without waiting and returns null;
 * the pick runs the ability through target_picked(). Tells `actor` why if
 * there's nothing to pick. Overridable for a picker whose "no valid target"
 * case is itself an action (robot_mount's dismount) rather than a plain refusal.
 */
/datum/interaction/ability/picker/proc/pick_target(mob/living/actor)
	var/list/choices = candidates(actor)
	if(!length(choices))
		to_chat(actor, span_warning("There's nothing nearby to [lowertext(name)]."))
		return null
	open_request(src, /datum/prompt/choice/ability_target, PROC_REF(target_picked), answerer = actor, question = picker_prompt, title = picker_title, choices = choices, ask_flags = ASK_CAPABLE)
	return null

/// pick_target()'s answer: the pick must still be a candidate (re-checked now), then the
/// ability runs on it as the keybind would have.
/datum/interaction/ability/picker/proc/target_picked(datum/act/request/A)
	if(!A.answer)
		return
	. = target_picked_apply(A)

/datum/interaction/ability/picker/proc/target_picked_apply(datum/act/request/A)
	var/datum/prompt/choice/ability_target/ask = A.answer
	var/mob/living/actor = ask.answerer
	var/atom/target = ask.value
	if(!istype(actor) || !target || !(target in candidates(actor)))
		return
	if(!applies_to(target))
		return
	attempt(actor, target, actor.get_active_hand())

/// Runs `ability_id` on `actor`: the keybind path (code/modules/keybindings/abilities.dm),
/// used instead of the general resolver because a key binds to one specific
/// ability, not "the best interaction of a category". A /self ability always
/// targets the actor; a /picker ability asks pick_target(); any other ability
/// targets whatever's hovered (or the tile in front, same fallback as a
/// category key - hover.dm).
/proc/dq_use_ability(mob/living/actor, id)
	var/datum/interaction/ability/A = ABILITY_BY_ID(id)
	if(!istype(A))
		return FALSE
	var/atom/target
	if(istype(A, /datum/interaction/ability/self))
		target = actor
	else if(istype(A, /datum/interaction/ability/picker))
		var/datum/interaction/ability/picker/P = A
		target = P.pick_target(actor)
	else
		target = actor.client?.hovered_atom() || get_step(actor, actor.dir)
	if(!target || !A.applies_to(target))
		return FALSE
	return A.attempt(actor, target, actor.get_active_hand()) == INTERACTION_TRY_RAN

/// Runs a /self ability on `actor` without any picker path, so it can be called from code
/// that must not sleep (Life stages, behaviours). Abilities that need a target go through
/// dq_use_ability() from player input instead.
/proc/dq_use_self_ability(mob/living/actor, id)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/interaction/ability/self/A = ABILITY_BY_ID(id)
	if(!istype(A) || !A.applies_to(actor))
		return FALSE
	return A.attempt(actor, actor, actor.get_active_hand()) == INTERACTION_TRY_RAN

// ---------------------------------------------------------------------------
// Grants: source-tracked, so an ability stays available while any source remains. They are OM
// grants (object_model_core.md §8, GRANT_ABILITY with the ability id as key): one store for
// every grant, released when the source is deleted, readable with grants_given_by(). (The
// rewrite/grants branch's own grant store is superseded by this.)

/// `source` now grants `id`. Idempotent: granting the same (id, source) twice is a no-op.
/mob/living/proc/grant_ability(id, datum/source)
	if(!id || !source)
		CRASH("grant_ability() needs both an id and a source")
	grant_hold(src, GRANT_ABILITY, id, source)

/// `source` no longer grants `id`. The ability stays available if another source still does.
/mob/living/proc/revoke_ability(id, datum/source)
	grant_release(src, GRANT_ABILITY, id, source)

/// TRUE if any source currently grants `id`.
/mob/living/proc/has_ability(id)
	return grant_held(src, GRANT_ABILITY, id)

/// The sources currently granting `id` (for UI/debugging), or null.
/mob/living/proc/ability_sources(id)
	return grant_sources(src, GRANT_ABILITY, id)

// ---------------------------------------------------------------------------
// Shared requirement helpers (code/__defines/abilities.dm's REQ_CONSCIOUS, REQ_ON_TURF).

/// TRUE if `actor` is conscious, else a reason.
/mob/living/proc/dq_pred_conscious(mob/living/actor, atom/target, obj/item/held)
	return !stat || "you can't do that in your state"

/// TRUE if `actor` is standing on a real turf, else a reason.
/mob/living/proc/dq_pred_on_turf(mob/living/actor, atom/target, obj/item/held)
	return get_turf(actor) ? TRUE : "you can't use that here"

/// TRUE unless `actor` is in a VR simulation, else a reason. VR can't run most
/// shadekin abilities (comp_helpers.dm's special_considerations()).
/mob/living/proc/dq_pred_not_vr(mob/living/actor, atom/target, obj/item/held)
	return !istype(get_area(actor), /area/vr) || "the VR systems cannot comprehend this power"

// ---------------------------------------------------------------------------
// Registry: every ability type is offered by every living mob's
// declare_interactions() (the /mob/living override lives in combat_mode.dm,
// alongside the other mob-wide interactions); who can actually use one is
// entirely down to the grant check in why_not() above; applies_to() below
// that (component/state checks) and each ability's own requires.

GLOBAL_LIST_INIT(ability_interaction_types, init_ability_interaction_types())

/proc/init_ability_interaction_types()
	. = list()
	for(var/datum/interaction/ability/path as anything in subtypesof(/datum/interaction/ability))
		if(initial(path.id))
			. += path

/datum/prompt/choice/ability_target
	timeout = 0

/datum/prompt/choice/ability_target/recheck_extra()
	if(isnull(value))
		return
	var/atom/selected = value
	if(!istype(selected) || QDELETED(selected))
		return "gone"
