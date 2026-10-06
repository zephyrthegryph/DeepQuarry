/*
 * This file contains the alien mind-transfer pod, or 'Alien Reality' pod.
 */


/obj/machinery/vr_sleeper/alien
	name = "strange pod"
	desc = "A strange machine with what appears to be a comfortable, if quite vertical, bed. Numerous mechanical cylinders dot the ceiling, their purpose uncertain."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "alienpod_0"
	base_state = "alienpod_"

	eject_dead = FALSE

	var/produce_species = SPECIES_REPLICANT	// The default species produced. Will be overridden if randomize_species is true.
	var/randomize_species = FALSE
	var/list/possible_species	// Do we make the newly produced body a random species?
	perfect_replica = TRUE //All alien VR sleepers make perfect replicas.
	spawn_with_clothing = FALSE //alien VR sleepers do not spawn with clothing.

// ALLOW(init/INSTANCE_STATE): rolls which species this pod produces
/obj/machinery/vr_sleeper/alien/Initialize(mapload)
	. = ..()
	if(possible_species && possible_species.len)
		produce_species = pick(possible_species)

/obj/machinery/vr_sleeper/alien/work_step(datum/act/timer/A)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(broken_now())
		if(occupant)
			perform_exit()
			visible_message(span_infoplain(span_bold("\The [src]") + " emits a low droning sound, before the pod door clicks open."))
		return
	else if(eject_dead && occupant && occupant.stat == DEAD)
		visible_message(span_warning("\The [src] sounds an alarm, swinging its hatch open."))
		perform_exit()

CAPABILITIES(/obj/machinery/vr_sleeper/alien)
	op("scan_impl", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_scan_impl)))
	op("eject_impl", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Eject"), needs(req_adjacent(), req_capable(), req(PROC_REF(dq_actor_can_act_holds), because = PROC_REF(dq_actor_can_act_refusal))), then(PROC_REF(interaction_eject_impl)))

/obj/machinery/vr_sleeper/alien/proc/interaction_scan_impl(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	add_fingerprint(user)

	if(occupant && (istype(I, /obj/item/healthanalyzer) || istype(I, /obj/item/robotanalyzer)))
		I.attack(occupant, user)
	return TRUE

/// Requirement (was REQ_* dq_actor_can_act): the legacy check answers TRUE to pass.
/obj/machinery/vr_sleeper/alien/proc/dq_actor_can_act_holds(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why dq_actor_can_act_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/vr_sleeper/alien/proc/dq_actor_can_act_refusal(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return istext(answer) ? answer : "you can't do that right now"

/obj/machinery/vr_sleeper/alien/proc/interaction_eject_impl(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(broken_now() || (eject_dead && occupant && occupant.stat == DEAD))
		perform_exit()
	else
		go_out()
	add_fingerprint(user)
	return TRUE

/obj/machinery/vr_sleeper/alien/go_out()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!occupant)
		return

	if(avatar())
		ask_leave_vr(PROC_REF(alien_exit_confirmed))
		return
	alien_exit()

/obj/machinery/vr_sleeper/alien/proc/alien_exit_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	alien_exit()

/obj/machinery/vr_sleeper/alien/proc/alien_exit()
	var/mob/living/carbon/human/occupant = slot_item(OCCUPANT_SLOT_VR_POD)
	avatar()?.exit_vr() //We don't poof! We're a actual, living entity that isn't restrained by VR zones!
	if(!occupant) //This whole thing needs cleaned up later, but this works for now.
		return
	occupant.forceMove(get_turf(src))
	rel_clear(occupant, nameof(occupant.vr_link)) //The machine remembers the avatar. 1 avatar per machine. So the vr_link isn't needed anymore.
	occupant = null
	latent_materialize_all() // a walk needs real things (C5)
	for(var/atom/movable/A in contents_of(src)) // In case an object was dropped inside or something // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		if(A == circuit)
			continue
		if(component_parts && (A in component_parts))
			continue
		A.forceMove(src.loc)
	set_use_power(USE_POWER_IDLE)

/obj/machinery/vr_sleeper/alien/enter_vr()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)

	// No mob to transfer a mind from
	if(!occupant)
		return

	// No mind to transfer
	if(!occupant.mind)
		return

	// Mob doesn't have an active consciousness to send/receive from
	if(occupant.stat == DEAD && !occupant.client)
		return

	if(QDELETED(avatar())) //This REALLY needs to be changed to an OM handle
		rel_clear(src, nameof(avatar))

	if(avatar() && !occupant.stat)
		to_chat(occupant,span_alien("\The [src] begins to [pick("whir","hum","pulse")] as a screen appears in front of you."))
		open_request(src, /datum/prompt/yes_no, PROC_REF(alien_engage_answered), answerer = occupant, title = "Commmit?", question = "This pod is already linked. Are you certain you wish to engage?", ask_flags = ASK_INSIDE, timeout = 0)
		return
	alien_engage(occupant)

/obj/machinery/vr_sleeper/alien/proc/alien_engage_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/carbon/human/occupant = A.request.answerer
	if(!A.answer.value)
		visible_message(span_alien("\The [src] pulses!"))
		perform_exit()
		return
	alien_engage(occupant)

/obj/machinery/vr_sleeper/alien/proc/alien_engage(mob/living/carbon/human/occupant)
	to_chat(occupant,span_alien("Your mind blurs as information bombards you."))

	if(!avatar())
		var/turf/T = get_turf(src)
		if(!perfect_replica)
			rel_set(src, nameof(avatar), new /mob/living/carbon/human(src, produce_species))
		else
			rel_set(src, nameof(avatar), new /mob/living/carbon/human(src, occupant.species.name))

		// If the user has a non-default (Human) bodyshape, make it match theirs.
		if(occupant.species.name != "Promethean" && occupant.species.name != "Human" && mirror_first_occupant)
			avatar().shapeshifter_change_shape(occupant.species.name)
		avatar().status_at_least(STAT_SLEEPING, 6)

		occupant.enter_vr(avatar())
		if(spawn_with_clothing)
			SSjob.equip_rank(avatar(),"Visitor", 1, FALSE)
		grant(avatar(), granted_verb(/mob/living/carbon/human/proc/perform_exit_vr), avatar())
		avatar().set_virtual_reality_mob(FALSE) //THIS IS THE BIG DIFFERENCE WITH ALIEN VR PODS. THEY ARE NOT VR, THEY ARE REAL.

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

		PUBLISH_LEGACY(avatar(), /datum/notice/human_dna_finalized)

		open_request(src, /datum/prompt/text, PROC_REF(alien_avatar_renamed), valid = PROC_REF(asked_is_avatar), answerer = avatar(), title = "Name change", question = "Your mind feels foggy. You're certain your name is [occupant.real_name], but it could also be [avatar().name]. Would you like to change it to something else?", max_len = MAX_NAME_LEN, timeout = 0)

		avatar().forceMove(T)
		visible_message(span_alium("\The [src] [pick("gurgles", "churns", "sloshes")] before spitting out \the [avatar()]!"))

	else

		// There's only one body per one of these pods, so let's be kind.
		open_request(src, /datum/prompt/text, PROC_REF(alien_avatar_renamed), valid = PROC_REF(asked_is_avatar), answerer = avatar(), title = "Name change", question = "Your mind feels foggy. You're certain your name is [occupant.real_name], but it feels like it is [avatar().name]. Would you like to change it to something else?", max_len = MAX_NAME_LEN, timeout = 0)
		occupant.enter_vr(avatar())

/obj/machinery/vr_sleeper/alien/proc/alien_avatar_renamed(datum/act/request/A)
	if(A.answer && A.answer.value)
		avatar().real_name = A.answer.value
		avatar().name = A.answer.value


/*
 * Subtypes
 */

/obj/machinery/vr_sleeper/alien/random_replicant
	possible_species = list(SPECIES_REPLICANT, SPECIES_REPLICANT_ALPHA, SPECIES_REPLICANT_BETA)

/obj/machinery/vr_sleeper/alien/alpha_replicant
	produce_species = SPECIES_REPLICANT_ALPHA

/obj/machinery/vr_sleeper/alien/beta_replicant
	produce_species = SPECIES_REPLICANT_BETA
