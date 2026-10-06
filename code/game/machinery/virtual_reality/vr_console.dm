/obj/machinery/vr_sleeper
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "virtual reality sleeper"
	desc = "A fancy bed with built-in sensory I/O ports and connectors to interface users' minds with their bodies in virtual reality."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "body_scanner_0"
	flags = REMOTEVIEW_ON_ENTER

	var/base_state = "body_scanner_"

	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/vr_sleeper
	// No view fields (OM relations step 3): `occupant` is still an ordinary
	// var every reader here uses, but this slot's own on_link()/on_unlink()
	// (below) are its only writer now.
	var/mob/living/carbon/human/avatar
	var/datum/mind/vr_mind
	var/datum/effect/effect/system/smoke_spread/bad/smoke

	var/eject_dead = TRUE

	var/mirror_first_occupant = TRUE	// Do we force the newly produced body to look like the occupant?

	var/spawn_with_clothing = TRUE		// Do we spawn the avatar with clothing?

	/// If we have a perfect replica of the mob's species that is entering us!
	/// Because of our player population, I have defaulted this to TRUE.
	/// If you are a downstream and want to have people spawn as VR prometheans by default, change this to FALSE
	var/perfect_replica = TRUE

	use_power = USE_POWER_IDLE
	idle_power_usage = 15
	active_power_usage = 200
	light_color = "#FF0000"

CAPABILITIES(/obj/machinery/vr_sleeper)
	started_work(step = PROC_REF(work_step), starts = TRUE, gate = PROC_REF(vr_occupied))
	owns_one(nameof(smoke), /datum/effect/effect/system/smoke_spread/bad)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(vr_sleeper_emp))))

/obj/machinery/vr_sleeper/perfect
	perfect_replica = TRUE

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3).
/datum/om/relation/slot/occupant/vr_pod
	holder = /obj/machinery/vr_sleeper
	slot_id = OCCUPANT_SLOT_VR_POD
	name = "VR pod"

/// Derived field: the pod holds someone. The occupant slot's link/unlink raises
/// CHANGE_RELATION_ADDED/REMOVED on the pod (om_link/om_unlink).
OM_DERIVE_FIELD(/obj/machinery/vr_sleeper, vr_occupied, list(CHANGE_RELATION_ADDED, CHANGE_RELATION_REMOVED))
/obj/machinery/vr_sleeper/proc/vr_occupied()
	return slot_item(OCCUPANT_SLOT_VR_POD) ? TRUE : FALSE

/// Watches its occupant (death, power loss) while it has one.
/obj/machinery/vr_sleeper/Initialize(mapload)
	. = ..()
	default_apply_parts()
	rel_set(src, nameof(smoke), new /datum/effect/effect/system/smoke_spread/bad)

// its occupant exits VR (phase 2, while the slot still holds them; phase 3 spills them).
/obj/machinery/vr_sleeper/lifecycle_dematerialize()
	var/mob/living/carbon/human/occupant = slot_item(OCCUPANT_SLOT_VR_POD)
	if(occupant && occupant.vr_link)
		occupant.vr_link.exit_vr()
	..()

/// Watches its occupant (death, power loss) while it has one (the declaration above).
/obj/machinery/vr_sleeper/proc/work_step(datum/act/timer/A)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!operable())
		if(occupant)
			occupant.exit_vr(FALSE)
			visible_message(span_infoplain(span_bold("\The [src]") + " emits a low droning sound, before the pod door clicks open."))
		return
	else if(eject_dead && occupant && occupant.stat == DEAD) // If someone dies somehow while inside, spit them out.
		visible_message(span_warning("\The [src] sounds an alarm, swinging its hatch open."))
		occupant.exit_vr(FALSE)

/// The look (the draw sweep: from its template).
/obj/machinery/vr_sleeper/draw(datum/look/look)
	..()
	look.state("[base_state][appearance_occupied()]")

/// 1 while the pod holds an occupant, else 0.
/obj/machinery/vr_sleeper/proc/appearance_occupied()
	return slot_item(OCCUPANT_SLOT_VR_POD) ? 1 : 0

/obj/machinery/vr_sleeper/examine(mob/user)
	var/mob/living/carbon/human/occupant = slot_item_real(OCCUPANT_SLOT_VR_POD)
	. = ..()
	if(occupant)
		. += span_notice("[occupant] is inside.")


/obj/machinery/vr_sleeper/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/vr_sleeper_scan,
		/datum/interaction/machine_drag/vr_sleeper_enter,
		/datum/interaction/machine_verb/vr_sleeper_eject,
		/datum/interaction/machine_verb/vr_sleeper_climb_in,
	)
	..()

/// Old attackby: always fingerprints, then lets a medical scanner analyze the occupant.
/datum/interaction/machine_item/vr_sleeper_scan
	id = "vr_sleeper_scan"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/vr_sleeper/proc/interaction_scan

/obj/machinery/vr_sleeper/proc/interaction_scan(mob/user, obj/item/I, datum/interaction/interaction)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	add_fingerprint(user)

	if(occupant && (istype(I, /obj/item/healthanalyzer) || istype(I, /obj/item/robotanalyzer)))
		I.attack(occupant, user)
	return TRUE

/obj/machinery/vr_sleeper/crowbar_act(mob/user, obj/item/tool)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	if(occupant && avatar())
		avatar().exit_vr()
		rel_clear(src, nameof(avatar))
		perform_exit()
	return ..()

/datum/interaction/machine_drag/vr_sleeper_enter
	id = "vr_sleeper_enter"
	name = "Insert"
	held_type = /mob
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/vr_sleeper/proc/drag_meant, null))
	effect = /obj/machinery/vr_sleeper/proc/interaction_enter

/// The old MouseDrop_T guard for the dragged mob.
/obj/machinery/vr_sleeper/proc/drag_meant(mob/actor, atom/target, mob/dropping)
	return isliving(dropping)

/obj/machinery/vr_sleeper/proc/interaction_enter(mob/user, atom/movable/dropping, datum/interaction/interaction)
	var/mob/target = dropping
	if(user.stat || user.lying || !Adjacent(user) || !target.Adjacent(user)|| !isliving(target))
		return TRUE
	go_in(target, user)
	return TRUE

/// An EMP throws the occupant out of VR, maybe frying their brain on the way.
/obj/machinery/vr_sleeper/proc/vr_sleeper_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	var/mob/living/carbon/human/occupant = slot_item(OCCUPANT_SLOT_VR_POD)
	if(!operable())
		return HOOK_DECLINE
	var/severity = packet.severity

	if(occupant)
		// This will eject the user from VR
		// ### Fry the brain? Yes. Maybe.
		if(prob(15 / ( severity / 4 )) && occupant.species.has_organ[O_BRAIN] && occupant.organ_in(O_BRAIN))
			var/obj/item/organ/O = occupant.organ_in(O_BRAIN)
			occupant.injure(INJURY_NEURAL, severity * 2, O, src)
			visible_message(span_danger("\The [src]'s internal lighting flashes rapidly, before the hatch swings open with a cloud of smoke."))
			smoke.set_up(severity, 0, src)
			smoke.start("#202020")
		perform_exit()
	return HOOK_DECLINE

/datum/interaction/machine_verb/vr_sleeper_eject
	id = "vr_sleeper_eject"
	name = "Eject VR Capsule"
	category = INTERACTION_CAT_EJECT
	requires = list(REQ_INTERACTION_REACH, REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now"))
	effect = /obj/machinery/vr_sleeper/proc/interaction_eject

/obj/machinery/vr_sleeper/proc/interaction_eject(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!operable() || occupant && occupant.stat == DEAD)
		perform_exit()
	else
		go_out()
	add_fingerprint(user)
	return TRUE

/datum/interaction/machine_verb/vr_sleeper_climb_in
	id = "vr_sleeper_climb_in"
	name = "Enter VR Capsule"
	category = INTERACTION_CAT_INSERT
	requires = list(REQ_INTERACTION_REACH, REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now"))
	effect = /obj/machinery/vr_sleeper/proc/interaction_climb_in

/obj/machinery/vr_sleeper/proc/interaction_climb_in(mob/user, obj/item/held, datum/interaction/interaction)
	go_in(user, user)
	add_fingerprint(user)
	return TRUE

/obj/machinery/vr_sleeper/relaymove(mob/user as mob)
	..()
	if(user.incapacitated())
		return 0 //maybe they should be able to get out with cuffs, but whatever
	perform_exit()

/obj/machinery/vr_sleeper/proc/go_in(mob/M, mob/user)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!M)
		return
	if(!operable())
		return
	if(!ishuman(M))
		to_chat(user, span_warning("\The [src] rejects [M] with a sharp beep."))
		return
	if(occupant)
		to_chat(user, span_warning("\The [src] is already occupied."))
		return

	if(M == user)
		act_message(user, src, others = "%U% starts climbing into %T%.")
	else
		act_message(user, M, others = "%U% starts putting %T% into \the [src].")

	om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(go_in_timed_done), done_args = list(M, user))
	return

/obj/machinery/vr_sleeper/proc/go_in_timed_done(mob/M, mob/user)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(occupant)
		to_chat(user, span_warning("\The [src] is already occupied."))
		return
	M.stop_pulling()
	if(!move_into(src, OCCUPANT_SLOT_VR_POD, M))
		return


	if(M.has_brain_worms())
		to_chat(user, span_warning("\The [src] rejects [M] with a sharp beep."))
		return

	set_use_power(USE_POWER_ACTIVE)
	enter_vr()

/obj/machinery/vr_sleeper/proc/go_out()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!occupant)
		return

	if(avatar())
		ask_leave_vr(PROC_REF(perform_exit_confirmed))
		return

	perform_exit()

/// The avatar is asked to leave; `handler` runs on a yes.
/obj/machinery/vr_sleeper/proc/ask_leave_vr(handler)
	open_request(src, /datum/prompt/yes_no, handler, valid = PROC_REF(asked_is_avatar), answerer = avatar(), title = "Leave VR?", question = "Someone wants to remove you from virtual reality. Do you want to leave?", timeout = 0)

/// Re-checked on the answer: they are still this pod's avatar.
/obj/machinery/vr_sleeper/proc/asked_is_avatar(datum/request/R)
	return avatar() == R.answerer

/obj/machinery/vr_sleeper/proc/perform_exit_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	perform_exit()

//The actual bulk of the exit code.
/obj/machinery/vr_sleeper/proc/perform_exit()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!occupant)
		return

	rel_clear(src, nameof(avatar))

	if(occupant.vr_link)
		occupant.vr_link.exit_vr(FALSE)

	occupant.reset_perspective() // Needed for returning from VR
	// The occupant slot is the only thing in this machine that should ever
	// leave here: everything else (circuit, parts) lives in its own default
	// slot (machine_internals) now, so the old "eject everything except a
	// hand-kept exclude list" loop is gone.
	slot_remove(occupant, get_turf(src))
	set_use_power(USE_POWER_IDLE)

/obj/machinery/vr_sleeper/proc/enter_vr()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)

	// No mob to transfer a mind from
	if(!occupant)
		return

	// No mind to transfer
	if(!occupant.mind)
		return

	// Mob doesn't have an active consciousness to send/receive from
	if(occupant.stat == DEAD)
		return

	if(QDELETED(occupant.vr_link)) //Hardrefs...
		rel_clear(occupant, nameof(occupant.vr_link))

	rel_set(src, nameof(avatar), occupant.vr_link)
	// If they've already enterred VR, and are reconnecting, prompt if they want a new body
	if(avatar())
		open_request(src, /datum/prompt/yes_no, PROC_REF(vr_reuse_answered), answerer = occupant, title = "New avatar", question = "You already have a [avatar().stat == DEAD ? "" : "deceased "]Virtual Reality avatar. Would you like to use it?", ask_flags = ASK_INSIDE, timeout = 0)
		return
	vr_choose_avatar(occupant)

/obj/machinery/vr_sleeper/proc/vr_reuse_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/carbon/human/occupant = A.request.answerer
	if(A.answer.value && avatar())
		vr_reenter(occupant)
		return
	// Delink the mob
	rel_clear(occupant, nameof(occupant.vr_link))
	rel_clear(src, nameof(avatar))
	vr_choose_avatar(occupant)

/// Asks where the new avatar spawns and whether it is a creature; vr_avatar_chosen() makes it.
/obj/machinery/vr_sleeper/proc/vr_choose_avatar(mob/living/carbon/human/occupant)
	var/list/vr_landmarks = list()
	for(var/obj/effect/landmark/virtual_reality/sloc in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		vr_landmarks += sloc.name
	open_request(src, /datum/prompt/choice, PROC_REF(location_chosen), valid = PROC_REF(occupant_inside), answerer = occupant, title = "Spawn location", question = "Please select a location to spawn your avatar at:", choices = vr_landmarks, timeout = 0)

/// Re-checked on every answer of the avatar choice: the asked is still the one inside the pod.
/obj/machinery/vr_sleeper/proc/occupant_inside(datum/request/R)
	return slot_item(OCCUPANT_SLOT_VR_POD) == R.answerer

/// Which creature to be: the spawn location is kept on the question.
/datum/prompt/yes_no/vr_avatar_mob
	var/location

/datum/prompt/choice/vr_avatar_creature
	var/location

/// Spawn location, then "as a creature?", then which creature. The occupant stays in the pod throughout.
/obj/machinery/vr_sleeper/proc/location_chosen(datum/act/request/A)
	if(!A.answer)
		return
	open_request(src, /datum/prompt/yes_no/vr_avatar_mob, PROC_REF(as_mob_answered), valid = PROC_REF(occupant_inside), answerer = A.request.answerer, title = "Join as a mob?", question = "Would you like to play as a different creature?", location = A.answer.value, timeout = 0)

/obj/machinery/vr_sleeper/proc/as_mob_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/yes_no/vr_avatar_mob/R = A.request
	if(A.answer.value)
		open_request(src, /datum/prompt/choice/vr_avatar_creature, PROC_REF(creature_chosen), valid = PROC_REF(occupant_inside), answerer = R.answerer, title = "Mob list", question = "Please select a creature:", choices = GLOB.vr_mob_tf_options, location = R.location, timeout = 0)
		return
	vr_avatar_chosen(R.answerer, R.location, null)

/obj/machinery/vr_sleeper/proc/creature_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/vr_avatar_creature/R = A.request
	vr_avatar_chosen(R.answerer, R.location, GLOB.vr_mob_tf_options[A.answer.value])

/obj/machinery/vr_sleeper/proc/vr_avatar_chosen(mob/living/carbon/human/occupant, S, tf)
	if(avatar())
		return
	for(var/obj/effect/landmark/virtual_reality/i in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		if(i.name == S)
			S = i
			break

	if(!perfect_replica)
		rel_set(src, nameof(avatar), new /mob/living/carbon/human(S, "Virtual Reality Avatar"))
	else
		rel_set(src, nameof(avatar), new /mob/living/carbon/human(src, occupant.species.name))

	// If the user has a non-default (Human) bodyshape, make it match theirs.
	if(occupant.species.name != "Promethean" && occupant.species.name != "Human" && mirror_first_occupant)
		avatar().shapeshifter_change_shape(occupant.species.name)
	avatar().forceMove(get_turf(S))			// Put the mob on the landmark, instead of inside it

	occupant.enter_vr(avatar())
	if(spawn_with_clothing)
		SSjob.equip_rank(avatar(),"Visitor", 1, FALSE)
	grant(avatar(), granted_verb(/mob/living/carbon/human/proc/perform_exit_vr), avatar())
	grant(avatar(), granted_verb(/mob/living/carbon/human/proc/vr_transform_into_mob), avatar())
	grant(avatar(), granted_verb(/mob/living/proc/set_size), avatar())
	avatar().set_virtual_reality_mob(TRUE)

	//This handles all the 'We make it look like ourself' code.
	//We do this BEFORE any mob tf so prefs  carry over properly!
	if(perfect_replica)
		avatar().species.create_organs(avatar()) // Reset our organs/limbs.
		avatar().restore_all_organs()
		avatar().client.prefs.copy_to(avatar())
		avatar().dna.ResetUIFrom(avatar())
		avatar().sync_dna_traits(TRUE) // Traitgenes Sync traits to genetics if needed
		avatar().sync_organ_dna()
		avatar().initialize_vessel()

	OM_EMIT(avatar(), /datum/om/event/human_dna_finalized)

	if(tf)
		var/mob/living/new_form = avatar().transform_into_mob(tf, TRUE) // No need to check prefs when the occupant already chose to transform.
		if(isliving(new_form)) // Make sure the mob spawned properly.
			grant(new_form, granted_verb(/mob/living/proc/vr_revert_mob_tf), new_form)
			new_form.set_virtual_reality_mob(TRUE)

	grant(avatar(), granted_verb(/mob/living/carbon/human/proc/perform_exit_vr), avatar()) //ahealing removes the prommie verbs and the VR verbs, giving it back
	avatar().status_at_least(STAT_SLEEPING, 1)

	// Prompt for username after they've enterred the body.
	open_request(src, /datum/prompt/text, PROC_REF(vr_avatar_named), valid = PROC_REF(asked_is_avatar), answerer = avatar(), title = "Name change", question = "You are entering virtual reality. Your username is currently [src.name]. Would you like to change it to something else?", max_len = MAX_NAME_LEN, timeout = 0)

/obj/machinery/vr_sleeper/proc/vr_avatar_named(datum/act/request/A)
	if(A.answer && A.answer.value)
		avatar().real_name = A.answer.value
		avatar().name = A.answer.value

/obj/machinery/vr_sleeper/proc/vr_reenter(mob/living/carbon/human/occupant)
	// If TFed, revert TF. Easier than coding mind transfer stuff for edge cases.
	if(avatar().tfed_into_mob_check())
		var/mob/living/M = avatar()
		if(istype(M)) // Sanity check, though shouldn't be needed since this is already checked by the proc.
			M.revert_mob_tf()
	occupant.enter_vr(avatar())


/// avatar (a relation view: it reads null once the target is deleted).
/obj/machinery/vr_sleeper/proc/avatar() as /mob/living/carbon/human
	return avatar

/// vr mind (a relation view: it reads null once the target is deleted).
/obj/machinery/vr_sleeper/proc/vr_mind() as /datum/mind
	return vr_mind
