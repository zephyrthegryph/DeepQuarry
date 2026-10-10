// Tourniquets: stop a limb bleed by stopping the limb's blood flow
// (doc/health_system_review.md §5.5).
//
// A tourniquet cinched on an arm or leg occludes flow to that limb and every
// limb distal to it (/obj/item/organ/external/proc/flow_occluded()). Occluded
// limbs don't bleed: their wounds report bleeding() FALSE, the blood system
// skips them, and arterial tears below the tourniquet stop draining. Nothing
// is deleted; loosening the tourniquet restores flow and the bleed resumes.
//
// The price is limb ischemia: /datum/affliction/limb_ischemia grows on the
// limb while flow is cut, and past LIMB_ISCHEMIA_NECROSIS_SEVERITY the tissue
// dies (tissue_necrosis, which only surgery removes). Once flow returns the
// ischemia recedes. Every step is logged under "TOURNIQUET:".

/obj/item/tourniquet
	name = "combat tourniquet"
	desc = "A windlass strap that cinches around an arm or leg to stop all blood flow below it. It stops a limb bleed dead, but the limb starts to die if it stays on too long."
	icon = 'icons/obj/stacks.dmi'
	icon_state = "tape-splint"
	w_class = ITEMSIZE_SMALL
	drop_sound = SFX_ITEMS_DROP_HAT
	pickup_sound = SFX_ITEMS_PICKUP_HAT
	/// world.time it was cinched on, or null while loose.
	EXPIRY_DECLARE(applied_at)
	/// Limbs a tourniquet can go on.
	var/static/list/applicable_zones = list(BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG)

/obj/item/tourniquet/examine(mob/user)
	. = ..()
	. += span_notice("It goes on an arm or a leg and stops every bleed below it. Loosen it (right-click the patient) as soon as the bleeding is controlled.")

// A tourniquet goes on the limb the user is aiming at. Every refusal is a balloon over the user, as before; the limb is the one aimed at when the cinch
// begins, and the wait ends if the user moves, loses the tourniquet or lets the patient go.
CAPABILITIES(/obj/item/tourniquet)
	op("cinch", at_target(/mob/living), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Cinch"),
		needs(req(PROC_REF(target_is_human), because = MSG(tourniquet/wont_fit)), req(PROC_REF(user_is_dexterous), because = MSG(tourniquet/clumsy))),
		starts(PROC_REF(cinch_started)), wait(TOURNIQUET_APPLY_TIME), on_interrupt(PROC_REF(cinch_failed)), then(PROC_REF(cinch_done)))

MSG_BALLOON(tourniquet/wont_fit, "it won't fit them!")
MSG_BALLOON(tourniquet/clumsy, "you don't have the dexterity to do this!")
MSG_BALLOON(tourniquet/wrong_limb, "a tourniquet goes on an arm or a leg!")
MSG_BALLOON(tourniquet/no_flow, "there's no blood flow to stop in that!")
MSG_BALLOON(tourniquet/limb_taken, "that limb already has a tourniquet!")

/obj/item/tourniquet/proc/target_is_human(datum/act/op/A)
	return ishuman(A.target) ? null : MSG(tourniquet/wont_fit)

/obj/item/tourniquet/proc/user_is_dexterous(datum/act/op/A)
	var/mob/living/user = A.actor
	return user.IsAdvancedToolUser() ? null : MSG(tourniquet/clumsy)

/// The limb being cinched: the one the user was aiming at when the cinch began, else the one they aim at now.
/obj/item/tourniquet/proc/cinch_limb(datum/act/op/A)
	var/obj/item/organ/external/E = A.arg("limb")
	if(E)
		return E
	var/mob/living/carbon/human/H = A.target
	var/mob/living/user = A.actor
	return istype(H) ? H.get_organ(user.zone_sel?.selecting) : null

/// The cinch begins: the limb aimed at must take a tourniquet (a balloon says why not), it is fixed now, and everyone around sees it.
/obj/item/tourniquet/proc/cinch_started(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/carbon/human/H = A.target
	var/obj/item/organ/external/E = cinch_limb(A)
	if(!E || !(E.organ_tag in applicable_zones))
		return MSG(tourniquet/wrong_limb)
	if(E.is_robotic())
		return MSG(tourniquet/no_flow)
	if(E.tourniquet)
		return MSG(tourniquet/limb_taken)
	LAZYSET(A.args, "limb", E)
	user.balloon_alert_visible("[user] starts cinching \a [src] around [H == user ? "their" : "[H]'s"] [E.name].", "cinching \the [src] around the [E.name].")

/obj/item/tourniquet/proc/cinch_failed(datum/act/op/A)
	balloon_alert(A.actor, "hold still to cinch the tourniquet!")

/obj/item/tourniquet/proc/cinch_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/carbon/human/H = A.target
	var/obj/item/organ/external/E = A.arg("limb")
	// Re-validate after the delay.
	if(loc != user || E.owner != H || E.tourniquet || !user.Adjacent(H))
		return OP_DECLINE
	if(!E.apply_tourniquet(src, user))
		user.put_in_hands(src)
		return
	user.balloon_alert_visible("[user] cinches \the [src] tight around [H == user ? "their" : "[H]'s"] [E.name].", "cinched \the [src] around the [E.name].")
	play_sfx(H, SFX_EFFECTS_TAPE)

// --- Limb side ---------------------------------------------------------------------

/obj/item/organ/external
	/// Tourniquet cinched on this limb, or null. Stops flow to it and every limb below it.
	var/obj/item/tourniquet/tourniquet

// Owned: a cinched tourniquet sits in the limb and is deleted with it.

/// A cinched tourniquet that leaves the limb by any path (moved, deleted, stripped by
/// a raw forceMove) stops occluding it (audit D15a).
/obj/item/organ/external/Exited(atom/movable/AM, atom/new_loc)
	. = ..()
	if(AM && AM == tourniquet)
		release_lost_tourniquet()

/// Clear a tourniquet that is no longer physically on this limb, restoring flow.
/obj/item/organ/external/proc/release_lost_tourniquet()
	var/obj/item/tourniquet/T = tourniquet
	rel_take(src, nameof(tourniquet))
	if(T)
		T.applied_at = null
	log_game("TOURNIQUET: [T] left [key_name(owner)]'s [name] without being loosened; flow restored.")
	if(!QDELETED(src))
		update_damages()

/obj/item/tourniquet/on_destroy(force)
	var/obj/item/organ/external/E = loc
	if(istype(E) && E.tourniquet == src)
		E.release_lost_tourniquet()
	..()

/// Is blood flow into this limb cut off by a tourniquet here or on a limb above it?
/obj/item/organ/external/proc/flow_occluded()
	var/obj/item/organ/external/E = src
	while(E)
		if(E.tourniquet)
			return TRUE
		E = E.parent
	return FALSE

/// Cinch `T` on this limb. Flow stops at once; ischemia starts.
/obj/item/organ/external/proc/apply_tourniquet(obj/item/tourniquet/T, mob/user)
	if(tourniquet || !istype(T))
		return FALSE
	if(!move_into(src, nameof(tourniquet), T, user))
		return FALSE
	EXPIRY_STAMP(T, applied_at, CLOCK_WORLD)
	afflict_ischemia_below()
	update_damages()
	log_game("TOURNIQUET: [key_name(user)] applied [T] to [key_name(owner)]'s [name] at [AREACOORD(owner || src)]; flow below it stopped.")
	if(user && owner && user != owner)
		add_attack_logs(user, owner, "Applied a tourniquet to [name]")
	return TRUE

/// Ischemia on this limb and every limb distal to it: flow_occluded() starves them all, so each
/// one grows its own ischemia (audit D15b: only the cinched limb used to).
/obj/item/organ/external/proc/afflict_ischemia_below()
	if(!owner?.body)
		return
	var/list/queue = list(src)
	while(length(queue))
		var/obj/item/organ/external/E = queue[length(queue)]
		queue.len--
		if(!E || E.owner != owner || E.is_stump())
			continue
		owner.body.afflict(/datum/affliction/limb_ischemia, E)
		for(var/obj/item/organ/external/child as anything in E.children)
			queue += child

/// Loosen this limb's tourniquet, restoring flow. Returns the tourniquet
/// (dropped at the patient's feet) or null if there was none.
/obj/item/organ/external/proc/remove_tourniquet(mob/user)
	if(!tourniquet)
		return null
	var/obj/item/tourniquet/T = tourniquet
	rel_take(src, nameof(tourniquet))
	var/minutes = T.applied_at ? round((world.time - T.applied_at) / (1 MINUTES), 0.1) : 0
	T.applied_at = null
	if(T.loc == src)
		T.dropInto(owner ? owner.loc : loc)
	update_damages()
	log_game("TOURNIQUET: [key_name(user)] removed [T] from [key_name(owner)]'s [name] at [AREACOORD(owner || src)] after [minutes] minutes; flow restored.")
	if(user && owner && user != owner)
		add_attack_logs(user, owner, "Removed a tourniquet from [name] after [minutes] minutes")
	return T

/// Loosen a tourniquet on someone within reach.
/mob/living/carbon/human/verb/loosen_tourniquet()
	set name = "Loosen Tourniquet"
	set category = VERB_CAT_IC
	set src in view(1)

	var/mob/living/user = usr
	if(!istype(user) || user.incapacitated() || !user.Adjacent(src))
		return
	var/list/cinched = list()
	for(var/obj/item/organ/external/E as anything in organs)
		if(E.tourniquet)
			cinched[E.name] = E
	if(!length(cinched))
		to_chat(user, span_warning("[src == user ? "You have" : "[src] has"] no tourniquet on."))
		return
	open_request(src, /datum/prompt/choice/loosen_tourniquet, PROC_REF(loosen_tourniquet_chosen), answerer = user, choices = cinched)

/datum/prompt/choice/loosen_tourniquet
	question = "Loosen which tourniquet?"
	title = "Tourniquet"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/loosen_tourniquet/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/user = answerer
	var/mob/living/carbon/human/patient = owner
	if(!istype(user) || user.incapacitated() || !user.Adjacent(patient))
		return "cannot reach the tourniquet"
	if(!isnull(value))
		var/list/cinched = list()
		for(var/obj/item/organ/external/limb as anything in patient.organs)
			if(limb.tourniquet)
				cinched[limb.name] = limb
		if(length(cinched) > 1 && !(value in cinched))
			return "the selected tourniquet is no longer there"
	return null

/mob/living/carbon/human/proc/loosen_tourniquet_chosen(datum/act/request/A)
	if(!A.answer)
		if(!isnull(A.request.value) && !QDELETED(A.request.answerer))
			SStgui.update_uis(src)
		return
	apply_tourniquet_choice(A)
	SStgui.update_uis(src)

/mob/living/carbon/human/proc/apply_tourniquet_choice(datum/act/request/A)
	var/mob/living/user = A.request.answerer
	var/list/cinched = list()
	for(var/obj/item/organ/external/limb as anything in organs)
		if(limb.tourniquet)
			cinched[limb.name] = limb
	if(!length(cinched))
		to_chat(user, span_warning("[src == user ? "You have" : "[src] has"] no tourniquet on."))
		return
	var/_answer_k142 = A.request.value
	var/choice = length(cinched) == 1 ? cinched[1] : _answer_k142
	if(!choice)
		return
	var/obj/item/organ/external/E = cinched[choice]
	perform_op(user, src, "loosen_tourniquet", null, ORIGIN_SYSTEM, with = list("limb" = E))

/// The line said when the loosening starts.
/mob/living/carbon/human/proc/loosen_tourniquet_begins(datum/act/op/A)
	var/obj/item/organ/external/E = A.arg("limb")
	return msg_text(span_notice("You start loosening the tourniquet on the [E.name]."), span_notice("%U% starts loosening the tourniquet on [src == A.actor ? "their" : "%T%'s"] [E.name]."))

/// Re-validate after the delay (the limb is still there and still tied).
/mob/living/carbon/human/proc/loosen_tourniquet_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/organ/external/E = A.arg("limb")
	if(QDELETED(E) || E.owner != src || !E.tourniquet)
		return
	var/obj/item/tourniquet/T = E.remove_tourniquet(user)
	if(T)
		user.put_in_hands(T)
		act_message(user, src, MSG_SELF(span_notice("You loosen the tourniquet on the [E.name]. Blood rushes back into it.")), \
			MSG_OTHERS(span_notice("%U% loosens the tourniquet on [src == user ? "their" : "%T%'s"] [E.name].")))

// --- Ischemia -------------------------------------------------------------------------

/// A limb starved of blood behind a tourniquet. Grows while the flow is cut,
/// recedes once it returns; left too long, the tissue dies.
/datum/affliction/limb_ischemia
	name = "limb ischemia"
	category = "Limbs"
	clinical_description = "A limb cut off from its blood supply, usually by a tourniquet. The tissue starves while the flow is stopped; left too long, it dies and must be cut away. Restoring flow lets it recover."
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	progression_rate = LIMB_ISCHEMIA_OCCLUDED_RATE
	// Loosening the tourniquet reperfuses the limb and the ischemia recedes.
	recedes_without_cause = TRUE
	pain_at_max = 40
	symptom_pool = list(
		/datum/affliction_symptom/cold_mottled_skin = 70,
		/datum/affliction_symptom/burning_limb      = 60,
		/datum/affliction_symptom/throbbing_pain    = 50,
	)
	min_symptoms = 0
	max_symptoms = 2
	factors = alist(BF_ACCURACY = -10)

/datum/affliction/limb_ischemia/on_added()
	. = ..()
	log_game("TOURNIQUET: [key_name(owner)] limb ischemia began on [location].")

/datum/affliction/limb_ischemia/on_removed()
	log_game("TOURNIQUET: [key_name(owner)] limb ischemia on [location] resolved at severity [round(severity, 0.1)].")
	return ..()

/// Grows while the limb is occluded, recedes once flow returns. Crossing the
/// necrosis line kills the starved tissue.
/datum/affliction/limb_ischemia/progress()
	var/obj/item/organ/external/E = location
	var/occluded = istype(E) && E.flow_occluded()
	progression_rate = occluded ? LIMB_ISCHEMIA_OCCLUDED_RATE : LIMB_ISCHEMIA_REPERFUSED_RATE
	..()
	if(QDELETED(src) || !body || severity < LIMB_ISCHEMIA_NECROSIS_SEVERITY)
		return
	if(body.find_affliction(/datum/affliction/tissue_necrosis, location))
		return
	if(spawn_child_affliction(/datum/affliction/tissue_necrosis))
		log_game("TOURNIQUET: [key_name(owner)] [location] went necrotic after prolonged ischemia (severity [round(severity, 0.1)]).")
		to_chat(owner, span_danger("Your [E ? E.name : "limb"] has gone cold and dead."))

