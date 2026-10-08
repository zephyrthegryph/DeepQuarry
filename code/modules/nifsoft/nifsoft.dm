//Please see the comment above the main NIF definition before
//trying to call any of these procs directly.

//A single piece of NIF software
/datum/nifsoft
	var/name = "Prototype"
	var/desc = "Contact a dev!"

	var/tmp/obj/item/nif/nif	//The NIF that the software is stored in

	var/list_pos				// List position in the nifsoft list

	var/cost = 1000				// Cost in cash of buying this software from a terminal

	var/vended = TRUE			// This is available in NIFSoft Shops at the start of the game
	var/wear = 1				// The wear (+/- 10% when applied) that this causes to the NIF
	var/access					// What access they need to buy it, can only set one for ~reasons~
	var/illegal = FALSE			// If this is a black-market nifsoft (emag option)

	var/active = FALSE			// Whether the active mode of this implant is on
	var/p_drain = 0				// Passive power drain, can be used in various ways from the software
	var/a_drain = 0				// Active power drain, same purpose as above, software can treat however
	var/activates = TRUE		// Whether or not this has an active power consumption mode
	var/tick_flags = 0			// Flags to tell when we'd like to be ticked

	var/empable = TRUE			// If the implant can be destroyed via EMP attack

	var/expiring = FALSE		// Trial software! Or self-deleting illegal ones!
	var/expires_at				// World.time for when they expire

	var/applies_to = (NIF_ORGANIC|NIF_SYNTHETIC) // Who this software is useful for

	var/vision_flags = 0	// Various flags for fast lookups that are settable on the NIF
	var/health_flags = 0	// These are added as soon as the implant is activated
	var/combat_flags = 0	// Otherwise use set_flag/clear_flag in one of your own procs for tricks
	var/other_flags = 0

	var/vision_flags_mob = 0
	var/darkness_view = 0

	var/can_uninstall = TRUE

	var/list/planes_enabled = null	// List of vision planes this nifsoft enables when active

	var/vision_exclusive = FALSE	//Whether or not this NIFSoft provides exclusive vision modifier

	var/list/incompatible_with = null // List of NIFSofts that are disabled when this one is enabled

//Constructor accepts the NIF it's being loaded into
/datum/nifsoft/New(obj/item/nif/nif_load)
	ASSERT(nif_load)

	rel_set(src, nameof(nif), nif_load)
	if(!install(nif()))
		spent(src)

//Destructor cleans up the software and nif reference
// installed software uninstalls.
/datum/nifsoft/on_destroy(force)
	if(nif())
		uninstall()
	..()

//Called when the software is installed in the NIF
/datum/nifsoft/proc/install()
	if(!nif())
		return
	return nif().install(src)

//Called when the software is removed from the NIF
/datum/nifsoft/proc/uninstall()
	if(!can_uninstall)
		return nif().uninstall(src)
	if(nif())
		if(active)
			deactivate()
		. = nif().uninstall(src)
		rel_clear(src, nameof(nif))
	if(!QDESTROYING(src))
		spent(src)

//Called every life() tick on a mob on active implants
/datum/nifsoft/proc/life(mob/living/carbon/human/human)
	return TRUE

//Called when attempting to activate an implant (could be a 'pulse' activation or toggling it on)
/datum/nifsoft/proc/activate(force = FALSE)
	if(active && !force)
		return
	var/nif_result = nif().activate(src)

	//If the NIF was fine with it, or we're forcing it
	if(nif_result || force)
		active = TRUE

		//If we enable vision planes
		if(planes_enabled)
			nif().add_plane(planes_enabled)
			nif().vis_update()

		//If we have other NIFsoft we need to turn off
		if(incompatible_with)
			nif().deactivate_these(incompatible_with)

		//Set all our activation flags
		nif().set_flag(vision_flags,NIF_FLAGS_VISION)
		nif().set_flag(health_flags,NIF_FLAGS_HEALTH)
		nif().set_flag(combat_flags,NIF_FLAGS_COMBAT)
		nif().set_flag(other_flags,NIF_FLAGS_OTHER)

		if(vision_exclusive)
			var/mob/living/carbon/human/H = nif().human
			if(H && istype(H))
				H.recalculate_vis()
				PUBLISH_CHANGE(H, MOB_KEY_VIEW) // the soft's sight flags and darkness view are read by life_vision()

	return nif_result

//Called when attempting to deactivate an implant
/datum/nifsoft/proc/deactivate(force = FALSE)
	if(!active && !force)
		return
	var/nif_result = nif().deactivate(src)

	//If the NIF was fine with it or we're forcing it
	if(nif_result || force)
		active = FALSE

		//If we enable vision planes, disable them
		if(planes_enabled)
			nif().del_plane(planes_enabled)
			nif().vis_update()

		//Clear all our activation flags
		nif().clear_flag(vision_flags,NIF_FLAGS_VISION)
		nif().clear_flag(health_flags,NIF_FLAGS_HEALTH)
		nif().clear_flag(combat_flags,NIF_FLAGS_COMBAT)
		nif().clear_flag(other_flags,NIF_FLAGS_OTHER)

		if(vision_exclusive)
			var/mob/living/carbon/human/H = nif().human
			if(H && istype(H))
				H.recalculate_vis()
				PUBLISH_CHANGE(H, MOB_KEY_VIEW)

	return nif_result

//Called when installed from a disk
/datum/nifsoft/proc/disk_install(mob/living/carbon/human/target,mob/living/carbon/human/user)
	return TRUE

//Status text for menu
/datum/nifsoft/proc/stat_text()
	if(activates)
		return "[active ? "Active" : "Disabled"]"

	return "Always On"

//////////////////////
//A package of NIF software
/datum/nifsoft/package
	var/list/software
	wear = 0 //Packages don't cause wear themselves, the software does

//Constructor accepts a NIF and loads all the software
/datum/nifsoft/package/New(obj/item/nif/nif_load)
	ASSERT(nif_load)

	for(var/P in software)
		new P(nif_load)

	spent(src)

//Clean self up

/////////////////
// A NIFSoft Uploader
/obj/item/disk/nifsoft
	name = "NIFSoft Uploader"
	desc = "It has a small label: \n\
	\"Portable NIFSoft Installation Media. \n\
	Align ocular port with eye socket and depress red plunger.\""
	icon = 'icons/obj/nanomods.dmi'
	icon_state = "medical"
	item_state = "nanomod"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_vr.dmi',
		)
	w_class = ITEMSIZE_SMALL
	var/datum/nifsoft/stored_organic = null
	var/datum/nifsoft/stored_synthetic = null

MSG_DEF(nifsoft/uploading_other, span_notice("You begin uploading %I% into %T%."), span_warning("%U% begins uploading %I% into %T%!"))
MSG_DEF_SELF(nifsoft/uploading_self, span_notice("You upload %I% into your NIF."))

CAPABILITIES(/obj/item/disk/nifsoft)
	op("upload", at_target(/mob/living/carbon/human), when(req_actor_kind(/mob/living/carbon/human)), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Upload"),
		needs(req_adjacent(), req(PROC_REF(upload_ready), because = PROC_REF(upload_refusal))),
		begins(PROC_REF(upload_begins)), starts(PROC_REF(upload_started)), wait(PROC_REF(upload_time)), on_interrupt(PROC_REF(upload_failed)), then(PROC_REF(upload_done)))

/// Requirement: the target has a NIF that is up and running (what a click decides on).
/obj/item/disk/nifsoft/proc/upload_ready(datum/act/op/A)
	var/mob/living/carbon/human/Ht = A.target
	return read_once(Ht.nif?.stat) == NIF_WORKING

/obj/item/disk/nifsoft/proc/upload_refusal(datum/act/op/A)
	return span_warning("Either they don't have a NIF, or the uploader can't connect.")

/obj/item/disk/nifsoft/proc/upload_begins(datum/act/op/A)
	return A.actor == A.target ? MSG(nifsoft/uploading_self) : MSG(nifsoft/uploading_other)

/// A second into your own NIF, ten into someone else's.
/obj/item/disk/nifsoft/proc/upload_time(datum/act/op/A)
	return A.actor == A.target ? 1 SECONDS : 10 SECONDS

/// Plays the item animation upon using on a valid target.
/obj/item/disk/nifsoft/proc/upload_started(datum/act/op/A)
	icon_state = "[initial(icon_state)]-animate"

/obj/item/disk/nifsoft/proc/upload_failed(datum/act/op/A)
	icon_state = "[initial(icon_state)]"	//If it fails to apply to a valid target and doesn't get deleted, reset its icon state

/obj/item/disk/nifsoft/proc/upload_done(datum/act/op/A)
	var/mob/living/carbon/human/Ht = A.target
	var/extra = extra_params()
	if(HAS_SYNTHETIC_BIOLOGY(Ht))
		new stored_synthetic(Ht.nif,extra)
	else
		new stored_organic(Ht.nif,extra)
	spent(src)
	return OP_OK

//So disks can pass fancier stuff.
/obj/item/disk/nifsoft/proc/extra_params()
	return null

// Compliance Disk //
/obj/item/disk/nifsoft/compliance
	name = "NIFSoft Uploader (Compliance)"
	desc = "Wow, adding laws to people? That seems illegal. It probably is. Okay, it really is."
	icon_state = "compliance"
	item_state = "healthanalyzer"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand.dmi',
		)
	stored_organic = /datum/nifsoft/compliance
	stored_synthetic = /datum/nifsoft/compliance
	var/laws

TRACKED(/obj/item/disk/nifsoft/compliance, laws)

/// A compliance disk with no laws set uploads nothing.
/obj/item/disk/nifsoft/compliance/upload_ready(datum/act/op/A)
	return !!laws && ..()

/obj/item/disk/nifsoft/compliance/upload_refusal(datum/act/op/A)
	if(!laws)
		return span_warning("You haven't set any laws yet. Use the disk in-hand first.")
	return ..()

CAPABILITIES(/obj/item/disk/nifsoft/compliance)
	op("self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), asks(/datum/prompt/text, fields = list("question" = "Please Input Laws", "title" = "Compliance Laws", "default" = computed(PROC_REF(laws_default)), "max_len" = 2048, "multiline" = TRUE), step = "laws"), then(PROC_REF(interaction_self)))

/obj/item/disk/nifsoft/compliance/proc/laws_default(datum/act/op/A)
	return laws

/// Old attack_self.
/obj/item/disk/nifsoft/compliance/proc/interaction_self(datum/act/op/A)
	var/newlaws = A.step_value("laws")
	if(newlaws)
		to_chat(A.actor,span_filter_notice("You set the laws to: <br>" + span_notice("[newlaws]")))
		set_laws(newlaws)
	return OP_OK

/obj/item/disk/nifsoft/compliance/extra_params()
	return laws

// Security Disk //
/obj/item/disk/nifsoft/security
	name = "NIFSoft Uploader - Security"
	desc = "Contains free NIFSofts useful for security members.\n\
	It has a small label: \n\
	\"Portable NIFSoft Installation Media. \n\
	Align ocular port with eye socket and depress red plunger.\""

	icon_state = "security"
	stored_organic = /datum/nifsoft/package/security
	stored_synthetic = /datum/nifsoft/package/security

/datum/nifsoft/package/security
	software = list(/datum/nifsoft/ar_sec,/datum/nifsoft/flashprot)

/obj/item/storage/box/nifsofts_security
	name = "security nifsoft uploaders"
	desc = "A box of free nifsofts for security employees."
	icon = 'icons/obj/boxes.dmi'
	icon_state = "nifsoft_kit_sec"

/obj/item/storage/box/nifsofts_security
	starts_with = list(
		/obj/item/disk/nifsoft/security = 8,
	)

// Engineering Disk //
/obj/item/disk/nifsoft/engineering
	name = "NIFSoft Uploader - Engineering"
	desc = "Contains free NIFSofts useful for engineering members.\n\
	It has a small label: \n\
	\"Portable NIFSoft Installation Media. \n\
	Align ocular port with eye socket and depress red plunger.\""

	icon_state = "engineering"
	stored_organic = /datum/nifsoft/package/engineering
	stored_synthetic = /datum/nifsoft/package/engineering

/datum/nifsoft/package/engineering
	software = list(/datum/nifsoft/ar_eng,/datum/nifsoft/alarmmonitor,/datum/nifsoft/uvblocker)

/obj/item/storage/box/nifsofts_engineering
	name = "engineering nifsoft uploaders"
	desc = "A box of free nifsofts for engineering employees."
	icon = 'icons/obj/boxes.dmi'
	icon_state = "nifsoft_kit_eng"

/obj/item/storage/box/nifsofts_engineering
	starts_with = list(
		/obj/item/disk/nifsoft/engineering = 8,
	)

// Medical Disk //
/obj/item/disk/nifsoft/medical
	name = "NIFSoft Uploader - Medical"
	desc = "Contains free NIFSofts useful for medical members.\n\
	It has a small label: \n\
	\"Portable NIFSoft Installation Media. \n\
	Align ocular port with eye socket and depress red plunger.\""

	stored_organic = /datum/nifsoft/package/medical
	stored_synthetic = /datum/nifsoft/package/medical

/datum/nifsoft/package/medical
	software = list(/datum/nifsoft/ar_med,/datum/nifsoft/crewmonitor)

/obj/item/storage/box/nifsofts_medical
	name = "medical nifsoft uploaders"
	desc = "A box of free nifsofts for medical employees."
	icon = 'icons/obj/boxes.dmi'
	icon_state = "nifsoft_kit_med"

/obj/item/storage/box/nifsofts_medical
	starts_with = list(
		/obj/item/disk/nifsoft/medical = 8,
	)

// Mining Disk //
/obj/item/disk/nifsoft/mining
	name = "NIFSoft Uploader - Mining"
	desc = "Contains free NIFSofts useful for mining members.\n\
	It has a small label: \n\
	\"Portable NIFSoft Installation Media. \n\
	Align ocular port with eye socket and depress red plunger.\""

	icon_state = "mining"
	stored_organic = /datum/nifsoft/package/mining
	stored_synthetic = /datum/nifsoft/package/mining_synth

/datum/nifsoft/package/mining
	software = list(/datum/nifsoft/material,/datum/nifsoft/spare_breath)

/datum/nifsoft/package/mining_synth
	software = list(/datum/nifsoft/material,/datum/nifsoft/pressure,/datum/nifsoft/heatsinks)

/obj/item/storage/box/nifsofts_mining
	name = "mining nifsoft uploaders"
	desc = "A box of free nifsofts for mining employees."
	icon = 'icons/obj/boxes.dmi'
	icon_state = "nifsoft_kit_mining"

/obj/item/storage/box/nifsofts_mining
	starts_with = list(
		/obj/item/disk/nifsoft/mining = 8,
	)

// Pilot Disk //
/obj/item/disk/nifsoft/pilot
	name = "NIFSoft Uploader - Pilot"
	desc = "Contains free NIFSofts useful for pilot members.\n\
	It has a small label: \n\
	\"Portable NIFSoft Installation Media. \n\
	Align ocular port with eye socket and depress red plunger.\""
	icon = 'icons/obj/nanomods_vr.dmi'
	icon_state = "pilot"
	stored_organic = /datum/nifsoft/package/pilot
	stored_synthetic = /datum/nifsoft/package/pilot_synth

/datum/nifsoft/package/pilot
	software = list(/datum/nifsoft/spare_breath)

/datum/nifsoft/package/pilot_synth
	software = list(/datum/nifsoft/pressure,/datum/nifsoft/heatsinks)

/obj/item/storage/box/nifsofts_pilot
	name = "pilot nifsoft uploaders"
	desc = "A box of free nifsofts for pilot employees."
	icon = 'icons/obj/boxes_vr.dmi'
	icon_state = "nifsoft_kit_pilot"

/obj/item/storage/box/nifsofts_pilot
	starts_with = list(
		/obj/item/disk/nifsoft/pilot = 8,
	)

// Mass Alteration Disk //
/obj/item/disk/nifsoft/sizechange
	name = "NIFSoft Uploader - Mass Alteration"
	desc = "Contains free NIFSofts for special purposes.\n\
	It has a small label: \n\
	\"Portable NIFSoft Installation Media. \n\
	Align ocular port with eye socket and depress red plunger.\""

	icon_state = "mining"
	stored_organic = /datum/nifsoft/sizechange
	stored_synthetic = /datum/nifsoft/sizechange

/obj/item/storage/box/nifsofts_sizechange
	name = "mass alteration nifsoft uploaders"
	desc = "A box of free nifsofts for special purposes."
	icon = 'icons/obj/boxes.dmi'
	icon_state = "nifsoft_kit_mining"

/obj/item/storage/box/nifsofts_sizechange
	starts_with = list(
		/obj/item/disk/nifsoft/sizechange = 8,
	)

/// LC-refs: The NIF that the software is stored in -- a relation view: null once it is deleted.
/datum/nifsoft/proc/nif() as /obj/item/nif
	return nif
