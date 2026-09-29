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
	var/avatar_handle
	var/vr_mind_handle
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

/obj/machinery/vr_sleeper/perfect
	perfect_replica = TRUE

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3).
/datum/om/relation/slot/occupant/vr_pod
	holder = /obj/machinery/vr_sleeper
	slot_id = OCCUPANT_SLOT_VR_POD
	name = "VR pod"

/obj/machinery/vr_sleeper/Initialize(mapload)
	. = ..()
	default_apply_parts()
	smoke = new
	update_icon()

// its occupant exits VR (phase 2, while the slot still holds them; phase 3 spills them).
/obj/machinery/vr_sleeper/lifecycle_dematerialize()
	var/mob/living/carbon/human/occupant = slot_item(OCCUPANT_SLOT_VR_POD)
	if(occupant && occupant.vr_link)
		occupant.vr_link.exit_vr()
	..()

/// Watches its occupant (death, power loss) while it has one; empty, it sleeps until someone
/// gets in.
/obj/machinery/vr_sleeper/machine_step()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!occupant)
		return PROCESS_KILL
	if(stat & (NOPOWER|BROKEN))
		if(occupant)
			occupant.exit_vr(FALSE)
			visible_message(span_infoplain(span_bold("\The [src]") + " emits a low droning sound, before the pod door clicks open."))
		return
	else if(eject_dead && occupant && occupant.stat == DEAD) // If someone dies somehow while inside, spit them out.
		visible_message(span_warning("\The [src] sounds an alarm, swinging its hatch open."))
		occupant.exit_vr(FALSE)

/obj/machinery/vr_sleeper/update_icon()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	icon_state = "[base_state][occupant ? "1" : "0"]"

/obj/machinery/vr_sleeper/examine(mob/user)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
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
		avatar_handle = null
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

/obj/machinery/vr_sleeper/emp_act(severity, recursive)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	. = ..()
	if (. & EMP_PROTECT_SELF || stat & (BROKEN|NOPOWER))
		return

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

/datum/interaction/machine_verb/vr_sleeper_eject
	id = "vr_sleeper_eject"
	name = "Eject VR Capsule"
	category = INTERACTION_CAT_EJECT
	requires = list(REQ_INTERACTION_REACH, REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now"))
	effect = /obj/machinery/vr_sleeper/proc/interaction_eject

/obj/machinery/vr_sleeper/proc/interaction_eject(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(stat & (BROKEN|NOPOWER) || occupant && occupant.stat == DEAD)
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
	if(stat & (BROKEN|NOPOWER))
		return
	if(!ishuman(M))
		to_chat(user, span_warning("\The [src] rejects [M] with a sharp beep."))
		return
	if(occupant)
		to_chat(user, span_warning("\The [src] is already occupied."))
		return

	if(M == user)
		visible_message("\The [user] starts climbing into \the [src].")
	else
		visible_message("\The [user] starts putting [M] into \the [src].")

	om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(go_in_timed_done), done_args = list(M, user))
	return

/obj/machinery/vr_sleeper/proc/go_in_timed_done(mob/M, mob/user)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(occupant)
		to_chat(user, span_warning("\The [src] is already occupied."))
		return
	M.stop_pulling()
	if(!M.move_into(src, OCCUPANT_SLOT_VR_POD))
		return

	update_icon()

	if(M.has_brain_worms())
		to_chat(user, span_warning("\The [src] rejects [M] with a sharp beep."))
		return

	update_use_power(USE_POWER_ACTIVE)
	enter_vr()

/obj/machinery/vr_sleeper/proc/go_out()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!occupant)
		return

	if(avatar())
		om_ask(avatar(), /datum/om/prompt/confirm/leave_vr, PROC_REF(perform_exit))
		return

	perform_exit()

/// The avatar is asked to leave. Re-checked on the answer: they are still this pod's avatar.
/datum/om/prompt/confirm/leave_vr
	title = "Leave VR?"
	message = "Someone wants to remove you from virtual reality. Do you want to leave?"

/datum/om/prompt/confirm/leave_vr/valid()
	var/obj/machinery/vr_sleeper/pod = subject
	return pod.avatar() == answerer ? null : "not the avatar"

//The actual bulk of the exit code.
/obj/machinery/vr_sleeper/proc/perform_exit()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!occupant)
		return

	avatar_handle = null

	if(occupant.vr_link)
		occupant.vr_link.exit_vr(FALSE)

	occupant.reset_perspective() // Needed for returning from VR
	// The occupant slot is the only thing in this machine that should ever
	// leave here: everything else (circuit, parts) lives in its own default
	// slot (machine_internals) now, so the old "eject everything except a
	// hand-kept exclude list" loop is gone.
	slot_remove(occupant, get_turf(src))
	update_use_power(USE_POWER_IDLE)
	update_icon()

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
		occupant.vr_link = null

	avatar_handle = om_handle(occupant.vr_link)
	// If they've already enterred VR, and are reconnecting, prompt if they want a new body
	if(avatar())
		om_ask(occupant, /datum/om/prompt/confirm, PROC_REF(vr_reuse_answered), message = "You already have a [avatar().stat == DEAD ? "" : "deceased "]Virtual Reality avatar. Would you like to use it?", title = "New avatar", answer_on_no = TRUE, requires = list(/datum/om/check/inside_target))
		return
	vr_choose_avatar(occupant)

/obj/machinery/vr_sleeper/proc/vr_reuse_answered(datum/om/prompt/confirm/ask)
	var/mob/living/carbon/human/occupant = ask.answerer
	if(ask.yes && avatar())
		vr_reenter(occupant)
		return
	// Delink the mob
	occupant.vr_link = null
	avatar_handle = null
	vr_choose_avatar(occupant)

/// Asks where the new avatar spawns and whether it is a creature; vr_avatar_chosen() makes it.
/obj/machinery/vr_sleeper/proc/vr_choose_avatar(mob/living/carbon/human/occupant)
	var/list/vr_landmarks = list()
	for(var/obj/effect/landmark/virtual_reality/sloc in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		vr_landmarks += sloc.name
	om_flow_start(/datum/om/flow/vr_choose_avatar, occupant, src, landmarks = vr_landmarks)

/// Spawn location, then "as a creature?", then which creature. The occupant stays in the pod throughout.
/datum/om/flow/vr_choose_avatar
	requires = list(/datum/om/check/inside_target)
	var/list/landmarks
	var/location

/datum/om/flow/vr_choose_avatar/start()
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(location_chosen), choices = landmarks, title = "Spawn location", message = "Please select a location to spawn your avatar at:")

/datum/om/flow/vr_choose_avatar/proc/location_chosen(datum/om/prompt/choice/ask)
	location = ask.choice
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(as_mob_answered), title = "Join as a mob?", message = "Would you like to play as a different creature?", answer_on_no = TRUE)

/datum/om/flow/vr_choose_avatar/proc/as_mob_answered(datum/om/prompt/confirm/ask)
	if(ask.yes)
		om_ask(actor, /datum/om/prompt/choice, PROC_REF(creature_chosen), choices = GLOB.vr_mob_tf_options, title = "Mob list", message = "Please select a creature:")
		return
	var/obj/machinery/vr_sleeper/pod = target
	pod.vr_avatar_chosen(actor, location, null)

/datum/om/flow/vr_choose_avatar/proc/creature_chosen(datum/om/prompt/choice/ask)
	var/obj/machinery/vr_sleeper/pod = target
	pod.vr_avatar_chosen(actor, location, GLOB.vr_mob_tf_options[ask.choice])

/obj/machinery/vr_sleeper/proc/vr_avatar_chosen(mob/living/carbon/human/occupant, S, tf)
	if(avatar())
		return
	for(var/obj/effect/landmark/virtual_reality/i in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		if(i.name == S)
			S = i
			break

	if(!perfect_replica)
		avatar_handle = om_handle(new /mob/living/carbon/human(S, "Virtual Reality Avatar"))
	else
		avatar_handle = om_handle(new /mob/living/carbon/human(src, occupant.species.name))

	// If the user has a non-default (Human) bodyshape, make it match theirs.
	if(occupant.species.name != "Promethean" && occupant.species.name != "Human" && mirror_first_occupant)
		avatar().shapeshifter_change_shape(occupant.species.name)
	avatar().forceMove(get_turf(S))			// Put the mob on the landmark, instead of inside it

	occupant.enter_vr(avatar())
	if(spawn_with_clothing)
		SSjob.equip_rank(avatar(),"Visitor", 1, FALSE)
	add_verb(avatar(),/mob/living/carbon/human/proc/perform_exit_vr)
	add_verb(avatar(),/mob/living/carbon/human/proc/vr_transform_into_mob)
	add_verb(avatar(),/mob/living/proc/set_size)
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
			add_verb(new_form,/mob/living/proc/vr_revert_mob_tf)
			new_form.set_virtual_reality_mob(TRUE)

	add_verb(avatar(), /mob/living/carbon/human/proc/perform_exit_vr) //ahealing removes the prommie verbs and the VR verbs, giving it back
	avatar().status_at_least(EFFECT_SLEEPING, 1)

	// Prompt for username after they've enterred the body.
	om_ask(avatar(), /datum/om/prompt/text/vr_avatar_name, PROC_REF(vr_avatar_named), message = "You are entering virtual reality. Your username is currently [src.name]. Would you like to change it to something else?")

/// Naming a pod's avatar. Re-checked on the answer: the answerer is still the pod's avatar.
/datum/om/prompt/text/vr_avatar_name
	title = "Name change"
	max_length = MAX_NAME_LEN

/datum/om/prompt/text/vr_avatar_name/valid()
	var/obj/machinery/vr_sleeper/pod = subject
	return (istype(pod) && pod.avatar() == answerer) ? null : "not the avatar"

/obj/machinery/vr_sleeper/proc/vr_avatar_named(datum/om/prompt/text/vr_avatar_name/ask)
	if(ask.text)
		avatar().real_name = ask.text
		avatar().name = ask.text

/obj/machinery/vr_sleeper/proc/vr_reenter(mob/living/carbon/human/occupant)
	// If TFed, revert TF. Easier than coding mind transfer stuff for edge cases.
	if(avatar().tfed_into_mob_check())
		var/mob/living/M = avatar()
		if(istype(M)) // Sanity check, though shouldn't be needed since this is already checked by the proc.
			M.revert_mob_tf()
	occupant.enter_vr(avatar())

DECLARE_REF(/obj/machinery/vr_sleeper, "smoke", OWNED, null)

/// LC-refs: avatar -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/vr_sleeper/proc/avatar() as /mob/living/carbon/human
	return om_resolve(avatar_handle)

/// LC-refs: vr mind -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/vr_sleeper/proc/vr_mind() as /datum/mind
	return om_resolve(vr_mind_handle)
