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

/obj/machinery/vr_sleeper/alien/Initialize(mapload)
	. = ..()
	if(possible_species && possible_species.len)
		produce_species = pick(possible_species)

/obj/machinery/vr_sleeper/alien/machine_step()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(!occupant)
		return PROCESS_KILL
	if(stat & (BROKEN))
		if(occupant)
			perform_exit()
			visible_message(span_infoplain(span_bold("\The [src]") + " emits a low droning sound, before the pod door clicks open."))
		return
	else if(eject_dead && occupant && occupant.stat == DEAD)
		visible_message(span_warning("\The [src] sounds an alarm, swinging its hatch open."))
		perform_exit()

/obj/machinery/vr_sleeper/alien/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/vr_sleeper_alien_scan,
		/datum/interaction/machine_verb/vr_sleeper_alien_eject,
	)
	..()

/// Old attackby: always fingerprints, then lets a medical scanner analyze the occupant.
/datum/interaction/machine_item/vr_sleeper_alien_scan
	id = "vr_sleeper_alien_scan"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/vr_sleeper/alien/proc/interaction_scan_impl

/obj/machinery/vr_sleeper/alien/proc/interaction_scan_impl(mob/user, obj/item/I, datum/interaction/interaction)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	add_fingerprint(user)

	if(occupant && (istype(I, /obj/item/healthanalyzer) || istype(I, /obj/item/robotanalyzer)))
		I.attack(occupant, user)
	return TRUE

/datum/interaction/machine_verb/vr_sleeper_alien_eject
	id = "vr_sleeper_alien_eject"
	name = "Eject"
	category = INTERACTION_CAT_EJECT
	effect = /obj/machinery/vr_sleeper/alien/proc/interaction_eject_impl

/obj/machinery/vr_sleeper/alien/proc/interaction_eject_impl(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_VR_POD)
	if(stat & (BROKEN) || (eject_dead && occupant && occupant.stat == DEAD))
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
		om_prompt(src, avatar(), list("message" = "Someone wants to remove you from virtual reality. Do you want to leave?", "title" = "Leave VR?", "choices" = list("Yes", "No")), PROC_REF(alien_leave_answered))
		return
	alien_exit()

/obj/machinery/vr_sleeper/alien/proc/alien_leave_answered(mob/user, answer, datum/om/prompt/ask)
	if(answer == "Yes" && user == avatar())
		alien_exit()

/obj/machinery/vr_sleeper/alien/proc/alien_exit()
	var/mob/living/carbon/human/occupant = slot_item(OCCUPANT_SLOT_VR_POD)
	avatar()?.exit_vr() //We don't poof! We're a actual, living entity that isn't restrained by VR zones!
	if(!occupant) //This whole thing needs cleaned up later, but this works for now.
		return
	occupant.forceMove(get_turf(src))
	occupant.vr_link = null //The machine remembers the avatar. 1 avatar per machine. So the vr_link isn't needed anymore.
	occupant = null
	latent_materialize_all() // a walk needs real things (C5)
	for(var/atom/movable/A in src) // In case an object was dropped inside or something // ALLOW(latent): materialized above
		if(A == circuit)
			continue
		if(component_parts && (A in component_parts))
			continue
		A.forceMove(src.loc)
	update_use_power(USE_POWER_IDLE)
	update_icon()

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
		avatar_handle = null

	if(avatar() && !occupant.stat)
		to_chat(occupant,span_alien("\The [src] begins to [pick("whir","hum","pulse")] as a screen appears in front of you."))
		om_prompt(src, occupant, list("message" = "This pod is already linked. Are you certain you wish to engage?", "title" = "Commmit?", "choices" = list("Yes", "No"), "requires" = list(/datum/om/check/inside_target)), PROC_REF(alien_engage_answered))
		return
	alien_engage(occupant)

/obj/machinery/vr_sleeper/alien/proc/alien_engage_answered(mob/living/carbon/human/occupant, answer, datum/om/prompt/ask)
	if(answer != "Yes")
		visible_message(span_alien("\The [src] pulses!"))
		perform_exit()
		return
	alien_engage(occupant)

/obj/machinery/vr_sleeper/alien/proc/alien_engage(mob/living/carbon/human/occupant)
	to_chat(occupant,span_alien("Your mind blurs as information bombards you."))

	if(!avatar())
		var/turf/T = get_turf(src)
		if(!perfect_replica)
			avatar_handle = om_handle(new /mob/living/carbon/human(src, produce_species))
		else
			avatar_handle = om_handle(new /mob/living/carbon/human(src, occupant.species.name))

		// If the user has a non-default (Human) bodyshape, make it match theirs.
		if(occupant.species.name != "Promethean" && occupant.species.name != "Human" && mirror_first_occupant)
			avatar().shapeshifter_change_shape(occupant.species.name)
		avatar().status_at_least(EFFECT_SLEEPING, 6)

		occupant.enter_vr(avatar())
		if(spawn_with_clothing)
			SSjob.equip_rank(avatar(),"Visitor", 1, FALSE)
		add_verb(avatar(),/mob/living/carbon/human/proc/perform_exit_vr)
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

		SEND_SIGNAL(avatar(), COMSIG_HUMAN_DNA_FINALIZED)

		om_prompt(src, avatar(), list("kind" = "text", "message" = "Your mind feels foggy. You're certain your name is [occupant.real_name], but it could also be [avatar().name]. Would you like to change it to something else?", "title" = "Name change", "max_length" = MAX_NAME_LEN), PROC_REF(alien_avatar_renamed))

		avatar().forceMove(T)
		visible_message(span_alium("\The [src] [pick("gurgles", "churns", "sloshes")] before spitting out \the [avatar()]!"))

	else

		// There's only one body per one of these pods, so let's be kind.
		om_prompt(src, avatar(), list("kind" = "text", "message" = "Your mind feels foggy. You're certain your name is [occupant.real_name], but it feels like it is [avatar().name]. Would you like to change it to something else?", "title" = "Name change", "max_length" = MAX_NAME_LEN), PROC_REF(alien_avatar_renamed))
		occupant.enter_vr(avatar())

/obj/machinery/vr_sleeper/alien/proc/alien_avatar_renamed(mob/living/carbon/human/user, newname, datum/om/prompt/ask)
	if(newname && user == avatar())
		avatar().real_name = newname
		avatar().name = newname


/*
 * Subtypes
 */

/obj/machinery/vr_sleeper/alien/random_replicant
	possible_species = list(SPECIES_REPLICANT, SPECIES_REPLICANT_ALPHA, SPECIES_REPLICANT_BETA)

/obj/machinery/vr_sleeper/alien/alpha_replicant
	produce_species = SPECIES_REPLICANT_ALPHA

/obj/machinery/vr_sleeper/alien/beta_replicant
	produce_species = SPECIES_REPLICANT_BETA
