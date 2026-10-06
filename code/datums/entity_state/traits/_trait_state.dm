/**
 * Trait states: the per-mob state of a trait/species/perk ability (burning in light, weaving,
 * gargoyle energy, radiation effects, ...). These replaced the old trait components.
 *
 * A trait state is a plain datum OWNED by its mob, held in `/mob/living/var/list/trait_states`
 * and deleted with it. Add one with `L.add_trait_state(/datum/trait_state/x, args...)`, look it
 * up with `L.get_trait_state(/datum/trait_state/x)` (matches subtypes) and remove it with
 * `L.remove_trait_state(/datum/trait_state/x)` or `qdel()`.
 *
 * A state that needs to tick each Life() cycle declares its step in `life_steps()` (usually
 * `seq_step(PROC_REF(life_tick), key = "life_trait_<name>", after = ...)`): it joins the mob's Life table
 * while the state is attached (seq_extra_add()) and runs as a contributed step, life_tick(mob, frame).
 */
/datum/trait_state
	/// When set, a mob holds at most one state of this type (or any subtype of it): adding another
	/// returns the existing one. Defaults to the state's own exact type.
	var/unique_type

/// The mob holding this state: a one-sided relation view (the mob owns us in trait_states).
/datum/trait_state/var/mob/living/owner

/datum/trait_state/New(mob/living/owner)
	..()
	rel_set(src, nameof(owner), owner)

/// Called once after New() with the extra add_trait_state() args. Return FALSE when the state
/// can't live on this mob (was COMPONENT_INCOMPATIBLE); it is then deleted without attaching.
/datum/trait_state/proc/setup()
	return isliving(owner)

/// Called when the state joins its mob (was RegisterWithParent). Hook events here.
/datum/trait_state/proc/attach()
	SHOULD_CALL_PARENT(TRUE)
	if(length(life_steps()))
		seq_extra_add(owner, /datum/sequence/life, src)

/// Called when the state leaves its mob (was UnregisterFromParent). Undo attach().
/datum/trait_state/proc/detach()
	SHOULD_CALL_PARENT(TRUE)
	unobserve_all(src)
	if(owner)
		seq_extra_remove(owner, /datum/sequence/life, src)

/// The Life steps this state contributes while attached (seq_step()s); none by default.
/datum/trait_state/proc/life_steps()
	return null

/// One Life() cycle, when the state's life_steps() declares it as its step.
/datum/trait_state/proc/life_tick()
	return

// a state leaving its mob takes its life stage, hooks and verbs with it.
/datum/trait_state/lifecycle_prerelease()
	..()
	if(owner)
		detach() // phase 2 then drops us from owner.trait_states (our owner's OWN list)

// --- Mob API ------------------------------------------------------------------------------------

/mob/living/var/list/trait_states

/// First trait state of `state_type` (or a subtype) this mob holds, or null.
/mob/living/proc/get_trait_state(state_type)
	RETURN_TYPE(/datum/trait_state)
	for(var/datum/trait_state/S as anything in trait_states)
		if(istype(S, state_type))
			return S
	return null

/// Adds a trait state of `state_type`, passing any extra args to its setup(). Returns the new
/// state, the existing one when the mob already holds one of its unique type, or null when the
/// state refused this mob.
/mob/living/proc/add_trait_state(state_type, ...)
	RETURN_TYPE(/datum/trait_state)
	if(!ispath(state_type, /datum/trait_state))
		CRASH("add_trait_state: [state_type] is not a /datum/trait_state")
	var/datum/trait_state/proto = state_type
	var/unique = initial(proto.unique_type) || state_type
	var/datum/trait_state/existing = get_trait_state(unique)
	if(existing)
		return existing
	var/datum/trait_state/S = new state_type(src)
	var/list/setup_args = args.Copy(2)
	if(!S.setup(arglist(setup_args)))
		log_game("TRAIT_STATE: [state_type] refused [key_name(src)] ([type]); not attached.")
		spent(S)
		return null
	rel_add(src, nameof(trait_states), S)
	S.attach()
	return S

/// Deletes this mob's trait state of `state_type` (or a subtype), if any. TRUE when one went.
/mob/living/proc/remove_trait_state(state_type)
	var/datum/trait_state/S = get_trait_state(state_type)
	if(!S)
		return FALSE
	own_remove(src, nameof(trait_states), S)
	return TRUE
