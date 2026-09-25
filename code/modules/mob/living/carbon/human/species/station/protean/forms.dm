// Forms: one character, one mob, many shapes. See doc/mob_life_architecture.md §6.2.
//
// The character mob never leaves the world. /datum/component/forms holds the
// current /datum/form (human, protean blob, promethean blob). Switching form
// swaps the datum and redraws the appearance; health, reagents, mind, bellies,
// languages and OOC notes stay where they are because nothing changes mobs.
//
// Per-character state (blob style, the protean rig) lives on the component and
// its form instances, never on the species datum.

/mob/living/carbon/human/proc/get_forms()
	RETURN_TYPE(/datum/component/forms)
	return GetComponent(/datum/component/forms)

/// The form the character is currently wearing, or null for ordinary humans.
/mob/living/carbon/human/proc/current_form()
	var/datum/component/forms/F = get_forms()
	return F?.current

/datum/component/forms
	dupe_mode = COMPONENT_DUPE_UNIQUE
	/// Form type -> instance. The instances hold this character's form data.
	var/list/forms
	/// The form being worn right now. Never null while attached.
	var/datum/form/current
	/// Appearances the current form added to the mob.
	var/list/form_overlays
	/// holder_type the mob had before a form replaced it.
	var/prior_holder_type
	/// A switch is in progress (re-entrancy guard).
	var/switching = FALSE
	/// Resting state the current appearance was drawn for.
	var/drawn_resting = FALSE

/// Form types this character can take, first one is the starting form.
/datum/component/forms/proc/get_form_types()
	var/static/list/types = list(/datum/form/human)
	return types

/datum/component/forms/Initialize()
	if(!ishuman(parent))
		return COMPONENT_INCOMPATIBLE
	forms = list()
	var/list/types = get_form_types()
	for(var/form_type in types)
		forms[form_type] = new form_type()
	current = forms[types[1]]

/datum/component/forms/RegisterWithParent()
	var/mob/living/carbon/human/H = parent
	prior_holder_type = H.holder_type
	om_stage_add(parent, /datum/om/stage/life/trait/forms)
	current.on_enter(src, H)
	H.invalidate_factors()

/datum/component/forms/UnregisterFromParent()
	var/mob/living/carbon/human/H = parent
	om_stage_remove(parent, /datum/om/stage/life/trait/forms)
	if(current)
		current.on_exit(src, H)
	H.invalidate_factors()
	clear_form_appearance(H)
	REMOVE_TRAIT(H, TRAIT_FORM_HIDES_BODY, FORM_TRAIT)
	H.holder_type = prior_holder_type

/datum/component/forms/Destroy(force)
	. = ..() // Detaches from the parent first; UnregisterFromParent still needs `current`.
	current = null
	for(var/form_type in forms)
		qdel(forms[form_type])
	forms = null
	form_overlays = null

/// Is the character wearing a form of this type (or a subtype)?
/datum/component/forms/proc/is_form(form_type)
	return istype(current, form_type)

/// Switch to `form_type`. Instant: callers that want a channel do their
/// do_after first. Returns TRUE if the form changed.
/datum/component/forms/proc/set_form(form_type, silent = FALSE)
	var/datum/form/next = forms?[form_type]
	if(!next || next == current || switching)
		return FALSE
	var/mob/living/carbon/human/H = parent
	switching = TRUE
	var/datum/form/old = current
	old.on_exit(src, H)
	current = next
	next.on_enter(src, H)
	H.invalidate_factors()
	if(!silent)
		next.announce_enter(H)
	refresh_appearance()
	H.update_transform(TRUE)
	H.update_canmove()
	switching = FALSE
	log_game("FORMS: [key_name(H)] changed form [old.id] -> [next.id] at [AREACOORD(H)]")
	SEND_SIGNAL(H, COMSIG_FORM_CHANGED, old, next)
	return TRUE

/// Redraw the current form. Human forms hand back to the ordinary body layers.
/datum/component/forms/proc/refresh_appearance()
	var/mob/living/carbon/human/H = parent
	if(QDELETED(H))
		return
	clear_form_appearance(H)
	if(current.draws_body)
		if(HAS_TRAIT(H, TRAIT_FORM_HIDES_BODY))
			REMOVE_TRAIT(H, TRAIT_FORM_HIDES_BODY, FORM_TRAIT)
			H.regenerate_icons()
		return
	if(!HAS_TRAIT(H, TRAIT_FORM_HIDES_BODY))
		ADD_TRAIT(H, TRAIT_FORM_HIDES_BODY, FORM_TRAIT)
		H.cut_overlays()
	drawn_resting = H.resting
	form_overlays = current.build_overlays(src, H)
	if(length(form_overlays))
		H.add_overlay(form_overlays)

/datum/component/forms/proc/clear_form_appearance(mob/living/carbon/human/H)
	if(length(form_overlays))
		H.cut_overlay(form_overlays)
	form_overlays = null

/datum/component/forms/proc/on_life(mob/living/source)
	SIGNAL_HANDLER
	// Shapeless forms draw their own resting states.
	if(!current.draws_body && source.resting != drawn_resting)
		refresh_appearance()
	if(source.stat == DEAD)
		return
	current.on_life(src, source)


// --- Forms --------------------------------------------------------------------------

/datum/form
	var/name = "form"
	/// Short id for logs and serialisation.
	var/id = "form"
	/// FORM_FLAG_* for this form; powers list the flags they allow.
	var/form_flag = NONE
	/// Draw the human body and worn gear. FALSE: the form draws itself.
	var/draws_body = TRUE
	/// Can hold items in its hands.
	var/has_hands = TRUE
	/// TREAT_REGENERATION points per tick a nanoform body may spend in this form.
	var/regeneration = 0
	/// holder_type while in this form (null keeps the mob's own).
	var/holder_type
	/// Messages and sound when entering.
	var/enter_message
	var/enter_sound

/// Verbs this form grants while worn.
/datum/form/proc/get_form_verbs()
	return null

/datum/form/proc/on_enter(datum/component/forms/F, mob/living/carbon/human/H)
	if(!has_hands)
		H.drop_l_hand()
		H.drop_r_hand()
	if(holder_type)
		H.holder_type = holder_type
	var/list/form_verbs = get_form_verbs()
	if(length(form_verbs))
		add_verb(H, form_verbs)

/datum/form/proc/on_exit(datum/component/forms/F, mob/living/carbon/human/H)
	if(holder_type)
		H.holder_type = F.prior_holder_type
	var/list/form_verbs = get_form_verbs()
	if(length(form_verbs))
		remove_verb(H, form_verbs)

/datum/form/proc/announce_enter(mob/living/carbon/human/H)
	if(enter_message)
		H.visible_message(span_infoplain(span_bold("[H.name]") + " [enter_message]"))
	if(enter_sound)
		playsound(H, enter_sound, 15)

/// Appearances drawn instead of the body when draws_body is FALSE.
/datum/form/proc/build_overlays(datum/component/forms/F, mob/living/carbon/human/H)
	return null

/// One Life tick while this form is worn.
/datum/form/proc/on_life(datum/component/forms/F, mob/living/carbon/human/H)
	return

/// Common preparation for collapsing into a shapeless form: nothing can stay
/// buckled, pulled or held in a hand that no longer exists.
/datum/form/proc/release_everything(mob/living/carbon/human/H)
	H.handle_grasp()
	remove_micros(H, H)
	if(H.buckled)
		H.buckled.unbuckle_mob()
	if(LAZYLEN(H.buckled_mobs))
		for(var/buckledmob in H.buckled_mobs.Copy())
			H.riding_datum?.force_dismount(buckledmob)
	if(H.pulledby)
		H.pulledby.stop_pulling()
	H.stop_pulling()
	H.drop_l_hand()
	H.drop_r_hand()

/datum/form/human
	name = "humanoid"
	id = "human"
	form_flag = FORM_FLAG_HUMAN

/datum/form/human/announce_enter(mob/living/carbon/human/H)
	return


// --- Body-drawing hooks ---------------------------------------------------------------

// A form that draws itself keeps the body layer cache up to date but does not
// apply it; returning to a body-drawing form regenerates the icons.
/mob/living/carbon/human/apply_layer(cache_index)
	if(HAS_TRAIT(src, TRAIT_FORM_HIDES_BODY))
		return overlays_standing[cache_index]
	return ..()

// Shapeless forms scale with the mob but never rotate to lie down; they draw
// their own resting states.
/mob/living/carbon/human/update_transform(instant = FALSE)
	if(!HAS_TRAIT(src, TRAIT_FORM_HIDES_BODY))
		return ..()
	var/matrix/M = matrix()
	var/scale_x = size_multiplier * icon_scale_x
	var/scale_y = size_multiplier * icon_scale_y
	M.Scale(scale_x, scale_y)
	M.Translate(0, 16 * (scale_y - 1))
	layer = MOB_LAYER
	if(instant)
		transform = M
	else
		animate(src, transform = M, time = 3)

/// Drop every held mob (micros in holders) the character is carrying anywhere
/// in its inventory. Doesn't handle containment cycles.
/proc/remove_micros(source, mob/root)
	for(var/obj/item/I in source)
		remove_micros(I, root)
		if(istype(I, /obj/item/holder))
			root.remove_from_mob(I)

/// Trait system: form upkeep. Was a COMSIG_LIVING_LIFE listener.
/datum/om/stage/life/trait/forms
	name = "forms"
	component_type = /datum/component/forms

/datum/om/stage/life/trait/forms/tick_component(mob/living/self, datum/component/forms/component)
	component.on_life(self)
