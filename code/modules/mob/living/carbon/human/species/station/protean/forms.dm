// Forms: one character, one mob, many shapes. See doc/mob_life_architecture.md §6.2.
//
// The character mob never leaves the world. /datum/forms (owned by the mob's `character_forms` var) holds the
// current /datum/form (human, protean blob, promethean blob). Switching form
// swaps the datum and redraws the appearance; health, reagents, mind, bellies,
// languages and OOC notes stay where they are because nothing changes mobs.
//
// Per-character state (blob style, the protean rig) lives on the forms datum and
// its form instances, never on the species datum.

/mob/living/carbon/human/var/datum/forms/character_forms
// Form type -> this character's form instance; `current` is one of them.

/mob/living/carbon/human/proc/get_forms()
	RETURN_TYPE(/datum/forms)
	return character_forms

/// Gives the character a forms datum of `forms_type` unless it already has one.
/mob/living/carbon/human/proc/add_forms(forms_type = /datum/forms)
	RETURN_TYPE(/datum/forms)
	if(!character_forms)
		rel_set(src, nameof(character_forms), new forms_type(src))
	return character_forms

/// Removes the character's forms datum if it is of `forms_type` (or a subtype).
/mob/living/carbon/human/proc/remove_forms(forms_type = /datum/forms)
	if(istype(character_forms, forms_type))
		own_clear(src, nameof(character_forms), OWN_DELETE)

/// The form the character is currently wearing, or null for ordinary humans.
/mob/living/carbon/human/proc/current_form()
	var/datum/forms/F = get_forms()
	return F?.current

/datum/forms
	/// The character wearing these forms.
	var/mob/living/carbon/human/owner
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

CAPABILITIES(/datum/forms)
	owns_many(nameof(forms))

/// Form types this character can take, first one is the starting form.
TYPE_TABLE_DECLARE(/datum/forms, get_form_types, list(/datum/form/human))

/datum/forms/New(mob/living/carbon/human/H)
	..()
	if(!ishuman(H))
		log_runtime("FORMS: forms datum created for a non-human ([H]).")
		return
	rel_set(src, nameof(owner), H)
	own_take_all(src, nameof(forms))
	var/list/types = TYPE_TABLE_GET(src, get_form_types)
	for(var/form_type in types)
		rel_add(src, nameof(forms), new form_type(), form_type)
	rel_set(src, nameof(current), forms[types[1]])
	attach()

/// Joins the owner (was RegisterWithParent).
/datum/forms/proc/attach()
	var/mob/living/carbon/human/H = owner
	prior_holder_type = H.holder_type
	seq_extra_add(H, /datum/sequence/life, src)
	current.on_enter(src, H)
	H.invalidate_factors()

/// Leaves the owner (was UnregisterFromParent).
/datum/forms/proc/detach()
	var/mob/living/carbon/human/H = owner
	seq_extra_remove(H, /datum/sequence/life, src)
	if(current)
		current.on_exit(src, H)
	H.invalidate_factors()
	clear_form_appearance(H)
	remove_trait(H, TRAIT_FORM_HIDES_BODY, FORM_TRAIT)
	H.holder_type = prior_holder_type

// its form mobs are deleted after it detaches.
/datum/forms/on_destroy(force)
	if(owner)
		detach()
	..()

/// Is the character wearing a form of this type (or a subtype)?
/datum/forms/proc/is_form(form_type)
	return istype(current, form_type)

/// Switch to `form_type`. Instant: callers that want a channel do their
/// do_after first. Returns TRUE if the form changed.
/datum/forms/proc/set_form(form_type, silent = FALSE)
	var/datum/form/next = forms?[form_type]
	if(!next || next == current || switching)
		return FALSE
	var/mob/living/carbon/human/H = owner
	switching = TRUE
	var/datum/form/old = current
	old.on_exit(src, H)
	rel_set(src, nameof(current), next)
	next.on_enter(src, H)
	H.invalidate_factors()
	if(!silent)
		next.announce_enter(H)
	refresh_appearance()
	H.update_transform(TRUE)
	H.update_canmove()
	changed(H, CHANGE_EXPLICIT) // wake the forms life stage for the new form's upkeep
	switching = FALSE
	log_game("FORMS: [key_name(H)] changed form [old.id] -> [next.id] at [AREACOORD(H)]")
	return TRUE

/// Redraw the current form. Human forms hand back to the ordinary body layers.
/datum/forms/proc/refresh_appearance()
	var/mob/living/carbon/human/H = owner
	if(QDELETED(H))
		return
	clear_form_appearance(H)
	if(current.draws_body)
		if(has_trait(H, TRAIT_FORM_HIDES_BODY))
			remove_trait(H, TRAIT_FORM_HIDES_BODY, FORM_TRAIT)
			H.regenerate_icons()
		return
	if(!has_trait(H, TRAIT_FORM_HIDES_BODY))
		add_trait(H, TRAIT_FORM_HIDES_BODY, FORM_TRAIT)
		H.cut_overlays()
	drawn_resting = H.resting
	form_overlays = current.build_overlays(src, H)
	if(length(form_overlays))
		H.add_overlay(form_overlays)

/datum/forms/proc/clear_form_appearance(mob/living/carbon/human/H)
	if(length(form_overlays))
		H.cut_overlay(form_overlays)
	form_overlays = null

/datum/forms/proc/on_life(mob/living/source)
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
	/// Has per-tick upkeep in on_life(); forms without it let the forms life stage sleep.
	var/ticks = FALSE
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
TYPE_TABLE_DECLARE(/datum/form, get_form_verbs, null)

/datum/form/proc/on_enter(datum/forms/F, mob/living/carbon/human/H)
	if(!has_hands)
		H.drop_l_hand()
		H.drop_r_hand()
	if(holder_type)
		H.holder_type = holder_type
	var/list/form_verbs = TYPE_TABLE_GET(src, get_form_verbs)
	if(length(form_verbs))
		om_grant_each(H, GRANT_VERB, form_verbs, src)

/datum/form/proc/on_exit(datum/forms/F, mob/living/carbon/human/H)
	if(holder_type)
		H.holder_type = F.prior_holder_type
	var/list/form_verbs = TYPE_TABLE_GET(src, get_form_verbs)
	if(length(form_verbs))
		om_revoke_each(H, GRANT_VERB, form_verbs, src)

/datum/form/proc/announce_enter(mob/living/carbon/human/H)
	if(enter_message)
		act_message(H, null, others = span_infoplain(span_bold("%U%") + " [enter_message]"))
	if(enter_sound)
		playsound(H, enter_sound, 15)

/// Appearances drawn instead of the body when draws_body is FALSE.
/datum/form/proc/build_overlays(datum/forms/F, mob/living/carbon/human/H)
	return null

/// One Life tick while this form is worn.
/datum/form/proc/on_life(datum/forms/F, mob/living/carbon/human/H)
	return

/// Common preparation for collapsing into a shapeless form: nothing can stay
/// buckled, pulled or held in a hand that no longer exists.
/datum/form/proc/release_everything(mob/living/carbon/human/H)
	H.handle_grasp()
	remove_micros(H, H)
	if(H?.buckled_to())
		var/atom/movable/_tmp_buck_16 = H?.buckled_to()
		_tmp_buck_16.unbuckle_mob()
	if(LAZYLEN(H?.buckled_mob_list()))
		var/list/_tmp_buck_17 = H?.buckled_mob_list()
		for(var/buckledmob in _tmp_buck_17.Copy())
			H.riding_datum?.force_dismount(buckledmob)
	var/mob/H_puller = H?.pulled_by_mob()
	if(H_puller)
		H_puller.stop_pulling()
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
	if(has_trait(src, TRAIT_FORM_HIDES_BODY))
		return overlays_standing[cache_index]
	return ..()

// Shapeless forms scale with the mob but never rotate to lie down; they draw
// their own resting states.
/mob/living/carbon/human/update_transform(instant = FALSE)
	if(!has_trait(src, TRAIT_FORM_HIDES_BODY))
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

/// Life: form upkeep, a step the forms datum contributes while attached. set_form() and stat changes wake it.
/datum/forms/proc/life_steps()
	return list(seq_step(PROC_REF(life_trait_forms), after = list(LIFE_INPUT, "life_type_pre"), key = "life_trait_forms", 		reads = CHANGE_MOB_STAT | CHANGE_EXPLICIT, should_run = PROC_REF(life_trait_forms_due), woken_by = "set_form(); set_stat()"))

/datum/forms/proc/life_trait_forms(mob/living/carbon/human/H, datum/seq_frame/life/F)
	H.character_forms?.on_life(H)

/// Has work while the current form has per-tick upkeep (`ticks`) or draws itself (it follows resting).
/datum/forms/proc/life_trait_forms_due(mob/living/carbon/human/H)
	if(!current)
		return FALSE
	if(!current.draws_body)
		return TRUE
	return current.ticks && H.stat != DEAD
