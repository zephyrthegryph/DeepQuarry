/obj/machinery/mecha_part_fabricator_tg/prosthetics
	icon = 'icons/obj/robotics_vr.dmi'
	icon_state = "prosfab"
	name = "Prosthetics Fabricator"
	desc = "A machine used for the construction of prosthetics."

	fab_type = PROSFAB
	circuit = /obj/item/circuitboard/prosthetics

	// Prosfab specific stuff
	var/manufacturer = null
	var/species_types = list("Human")
	var/species = "Human"

/obj/machinery/mecha_part_fabricator_tg/prosthetics/AfterMaterialInsert()
	return // no call parent

APPEARANCE_TEMPLATE(/obj/machinery/mecha_part_fabricator_tg/prosthetics, "prosfab{appearance_active_suffix}")
DECLARE_APPEARANCE(/obj/machinery/mecha_part_fabricator_tg/prosthetics, "panel_open", list("1" = list(APPEARANCE_ICON_STATE = "prosfab-o")))

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/appearance_active_suffix()
	return use_power == USE_POWER_ACTIVE ? "-active" : ""

/obj/machinery/mecha_part_fabricator_tg/prosthetics/on_start_printing()
	// Don't call parent
	update_icon()
	set_use_power(USE_POWER_ACTIVE)
	print_sound.start()

/obj/machinery/mecha_part_fabricator_tg/prosthetics/on_finish_printing()
	// Don't call parent
	set_use_power(USE_POWER_IDLE)
	desc = initial(desc)
	set_process_queue(FALSE)
	print_sound.stop()
	update_icon()

UI_DATA(/obj/machinery/mecha_part_fabricator_tg/prosthetics, "species_types:list", "species:text", "manufacturer", "merge:ui_data_obj_machinery_mecha_part_fabricator_tg_prosthetics{all_manufacturers:list}")

/// The computed part of /obj/machinery/mecha_part_fabricator_tg/prosthetics's window data (declared on its UI_DATA row).
/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/ui_data_obj_machinery_mecha_part_fabricator_tg_prosthetics(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()


	if(GLOB.all_robolimbs)
		var/list/T = list()
		for(var/A in GLOB.all_robolimbs)
			var/datum/robolimb/R = GLOB.all_robolimbs[A]
			if(R.unavailable_to_build)
				continue
			if(species in R.species_cannot_use)
				continue
			T += list(list("id" = A, "company" = R.company))
		data["all_manufacturers"] = T

	return data

UI_ACT(/obj/machinery/mecha_part_fabricator_tg/prosthetics, "species", ui_act_species)
UI_ACT_PROC(/obj/machinery/mecha_part_fabricator_tg/prosthetics, ui_act_species)
	if(!istype(ui) || QDELETED(ui) || !ismob(ui.user) || QDELETED(ui.user))
		return
	open_request(ui, /datum/prompt/choice/prosfab_setting, TYPE_PROC_REF(/datum/tgui, prosfab_setting_answered), answerer = ui.user, question = "Select a new species", title = "Prosfab Species Selection", choices = species_types, setting_action = "species")

UI_ACT(/obj/machinery/mecha_part_fabricator_tg/prosthetics, "manufacturer", ui_act_manufacturer)
UI_ACT_PROC(/obj/machinery/mecha_part_fabricator_tg/prosthetics, ui_act_manufacturer)
	var/list/new_manufacturers = list()
	for(var/A in GLOB.all_robolimbs)
		var/datum/robolimb/R = GLOB.all_robolimbs[A]
		if(R.unavailable_to_build)
			continue
		if(species in R.species_cannot_use)
			continue
		new_manufacturers += A

	if(!istype(ui) || QDELETED(ui) || !ismob(ui.user) || QDELETED(ui.user))
		return
	open_request(ui, /datum/prompt/choice/prosfab_setting, TYPE_PROC_REF(/datum/tgui, prosfab_setting_answered), answerer = ui.user, question = "Select a new manufacturer", title = "Prosfab Species Selection", choices = new_manufacturers, setting_action = "manufacturer")

/obj/machinery/mecha_part_fabricator_tg/prosthetics/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/prosfab_fingerprint_marker,
		/datum/interaction/machine_item/prosfab_limb_disk,
		/datum/interaction/machine_item/prosfab_species_disk,
	)
	..()

/// Old attackby's unconditional first line. Always runs first and declines.
/datum/interaction/machine_item/prosfab_fingerprint_marker
	id = "prosfab_fingerprint_marker"
	name = "Use"
	held_type = /obj/item
	consumes_input = FALSE
	effect = /atom/proc/interaction_fingerprint

/// Old attackby: install limb blueprint files from a disk.
/datum/interaction/machine_item/prosfab_limb_disk
	id = "prosfab_limb_disk"
	name = "Install blueprints"
	held_type = /obj/item/disk/limb
	effect = /obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/interaction_limb_disk

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/interaction_limb_disk(mob/user, obj/item/I, datum/interaction/interaction)
	var/obj/item/disk/limb/D = I
	if(!D.company || !(D.company in GLOB.all_robolimbs))
		to_chat(user, span_warning("This disk seems to be corrupted!"))
	else
		to_chat(user, span_notice("Installing blueprint files for [D.company]..."))
		om_task_timed(user, 5 SECONDS, src, src, PROC_REF(limb_disk_done), list(user, D))
	return TRUE

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/limb_disk_done(mob/user, obj/item/disk/limb/D)
	var/datum/robolimb/R = GLOB.all_robolimbs[D.company]
	R.unavailable_to_build = 0
	to_chat(user, span_notice("Installed [D.company] blueprints!"))
	consume(D, user)

/// Old attackby: upload species modification files from a disk.
/datum/interaction/machine_item/prosfab_species_disk
	id = "prosfab_species_disk"
	name = "Upload species files"
	held_type = /obj/item/disk/species
	effect = /obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/interaction_species_disk

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/interaction_species_disk(mob/user, obj/item/I, datum/interaction/interaction)
	var/obj/item/disk/species/D = I
	if(!D.species || !(D.species in GLOB.all_species))
		to_chat(user, span_warning("This disk seems to be corrupted!"))
	else
		to_chat(user, span_notice("Uploading modification files for [D.species]..."))
		om_task_timed(user, 5 SECONDS, src, src, PROC_REF(species_disk_done), list(user, D))
	return TRUE

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/species_disk_done(mob/user, obj/item/disk/species/D)
	var/upload_species = D.species
	if(!consume(D, user))
		return
	species_types |= upload_species
	to_chat(user, span_notice("Uploaded [upload_species] files!"))

/obj/machinery/mecha_part_fabricator_tg/prosthetics/create_new_part(datum/design_techweb/dispensed_design)
	if(istype(dispensed_design, /datum/design_techweb/prosfab/pros/torso))
		var/newspecies = "Human"

		var/datum/robolimb/manf = GLOB.all_robolimbs[manufacturer]

		if(!manf)
			manf = GLOB.all_robolimbs["Unbranded"]

		if(species in manf.species_alternates)	// If the prosthetics fab is set to say, Unbranded, and species set to 'Tajaran', it will make the Taj variant of Unbranded, if it exists.
			manf = manf.species_alternates[species]
		if(!species || (species in manf.species_cannot_use))
			newspecies = manf.suggested_species
		else
			newspecies = species

		var/mob/living/carbon/human/H = new(src, newspecies)
		H.set_stat(DEAD)
		H.gender = gender
		for(var/obj/item/organ/external/EO in H.organs)
			if(EO.organ_tag == BP_TORSO || EO.organ_tag == BP_GROIN)
				continue //Roboticizing a torso does all the children and wastes time, do it later
			else
				EO.remove_rejuv()

		for(var/obj/item/organ/external/O in H.organs)
			O.data.setup_from_species(GLOB.all_species[newspecies])

			var/datum/robolimb/manufacturer_for_this_part = manf
			if(!(O.organ_tag in manufacturer_for_this_part.parts))	// Make sure we're using an actually present icon.
				manufacturer_for_this_part = GLOB.all_robolimbs["Unbranded"]

			O.robotize(manufacturer_for_this_part.company)
			O.data.setup_from_dna()

			// Skincolor weirdness.
			O.s_col[1] = 0
			O.s_col[2] = 0
			O.s_col[3] = 0

		// Resetting the UI does strange things for the skin of a non-human robot, which should be controlled by a whole different thing.
		H.r_skin = 0
		H.g_skin = 0
		H.b_skin = 0
		H.dna.ResetUIFrom(H)

		H.allow_spontaneous_tf = TRUE // Allows vore customization of synthmorphs
		H.real_name = "Synthmorph #[rand(100,999)]"
		H.name = H.real_name
		H.dir = 2
		H.add_language(LANGUAGE_EAL)
		return H
	else if(istype(dispensed_design, /datum/design_techweb/prosfab/pros))
		var/obj/item/organ/O = new dispensed_design.build_path(src)
		if(manufacturer)
			var/datum/robolimb/manf = GLOB.all_robolimbs[manufacturer]

			if(!(O.organ_tag in manf.parts))	// Make sure we're using an actually present icon.
				manf = GLOB.all_robolimbs["Unbranded"]

			if(species in manf.species_alternates)	// If the prosthetics fab is set to say, Unbranded, and species set to 'Tajaran', it will make the Taj variant of Unbranded, if it exists.
				manf = manf.species_alternates[species]

			if(!species || (species in manf.species_cannot_use))	// Fabricator ensures the manufacturer can make parts for the species we're set to.
				O.data.setup_from_species(GLOB.all_species["[manf.suggested_species]"])
			else
				O.data.setup_from_species(GLOB.all_species[species])
		else
			O.data.setup_from_species(GLOB.all_species["Human"])
		O.robotize(manufacturer)
		return O
	else
		return new dispensed_design.build_path(src)

/datum/tgui/proc/prosfab_setting_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/prosfab_setting/ask = context.answer
	var/obj/machinery/mecha_part_fabricator_tg/prosthetics/fabricator = src_object()
	fabricator.apply_prosfab_setting(user, state(), ask.setting_action, ask.answer_value)
	SStgui.update_uis(fabricator)

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/apply_prosfab_setting(mob/user, datum/tgui_state/state, setting_action, value)
	if(value && tgui_status(user, state) == STATUS_INTERACTIVE)
		switch(setting_action)
			if("species")
				species = value
			if("manufacturer")
				manufacturer = value

/datum/prompt/choice/prosfab_setting
	timeout = 0
	recheck_on_open = TRUE
	var/setting_action

/datum/prompt/choice/prosfab_setting/recheck_extra()
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui) || QDELETED(answerer))
		return "gone"
	var/obj/machinery/mecha_part_fabricator_tg/prosthetics/fabricator = original_ui.src_object()
	if(!istype(fabricator) || QDELETED(fabricator))
		return "gone"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "the original window is not interactive"
	if(!fabricator.ui_act_allowed(original_ui.user, setting_action, original_ui, original_ui.state()))
		return "the fabricator setting is unavailable"
	return null
