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

/// Runs `ability_id` on `actor`: the keybind path (code/modules/keybindings/abilities.dm),
/// used instead of the general resolver because a key binds to one specific
/// ability, not "the best interaction of a category". A /self ability always
/// targets the actor; any other ability targets whatever's hovered (or the
/// tile in front, same fallback as a category key - hover.dm).
/proc/dq_use_ability(mob/living/actor, id)
	var/datum/interaction/ability/A = ABILITY_BY_ID(id)
	if(!istype(A))
		return FALSE
	var/atom/target = istype(A, /datum/interaction/ability/self) ? actor : (actor.client?.hovered_atom() || get_step(actor, actor.dir))
	if(!target || !A.applies_to(target))
		return FALSE
	return A.attempt(actor, target, actor.get_active_hand()) == INTERACTION_TRY_RAN

// ---------------------------------------------------------------------------
// Grants: source-tracked, so an ability stays available while any source remains.

/// id -> list of sources currently granting it. LAZYLIST: null for a mob with no grants.
/mob/living/var/list/ability_grants

/// `source` now grants `id`. Idempotent: granting the same (id, source) twice is a no-op.
/mob/living/proc/grant_ability(id, source)
	if(!id || !source)
		CRASH("grant_ability() needs both an id and a source")
	LAZYINITLIST(ability_grants)
	LAZYINITLIST(ability_grants[id])
	ability_grants[id] |= source

/// `source` no longer grants `id`. The ability stays available if another source still does.
/mob/living/proc/revoke_ability(id, source)
	if(!ability_grants || !ability_grants[id])
		return
	ability_grants[id] -= source
	if(!length(ability_grants[id]))
		ability_grants -= id

/// TRUE if any source currently grants `id`.
/mob/living/proc/has_ability(id)
	return length(ability_grants?[id]) > 0

/// The sources currently granting `id` (for UI/debugging), or null.
/mob/living/proc/ability_sources(id)
	return ability_grants?[id]

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
