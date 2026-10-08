// The prosthetics fabricator: an exosuit fabricator (mech_fabricator.dm) that builds prosthetic limbs and synthmorph bodies. ONE CAPABILITIES
// list adds what it has of its own: the disks that teach it a manufacturer's blueprints and a species' files (five seconds each), and the
// window's two questions, which species and which manufacturer it builds for.

MSG_DEF_SELF(prosfab/corrupted, "This disk seems to be corrupted!")
MSG_DEF(prosfab/installing, "You begin installing the blueprint files from %I%...", "%U% begins installing the blueprint files from %I% into %T%.")
MSG_DEF(prosfab/uploading, "You begin uploading the modification files from %I%...", "%U% begins uploading the modification files from %I% into %T%.")

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

CAPABILITIES(/obj/machinery/mecha_part_fabricator_tg/prosthetics)
	op("limb_disk", item(/obj/item/disk/limb), label("Install blueprints"), needs(req(PROC_REF(limb_disk_valid), because = MSG(prosfab/corrupted))),
		wait(5 SECONDS), begins(MSG(prosfab/installing)), then(PROC_REF(limb_disk_done)))
	op("species_disk", item(/obj/item/disk/species), label("Upload species files"), needs(req(PROC_REF(species_disk_valid), because = MSG(prosfab/corrupted))),
		wait(5 SECONDS), begins(MSG(prosfab/uploading)), then(PROC_REF(species_disk_done)))
	op("species", ui_act(), asks(/datum/prompt/choice, fields = list("question" = "Select a new species", "title" = "Prosfab Species Selection",
		"choices" = computed(PROC_REF(species_choices)), "timeout" = 0)), then(PROC_REF(species_chosen)))
	op("manufacturer", ui_act(), asks(/datum/prompt/choice, fields = list("question" = "Select a new manufacturer", "title" = "Prosfab Species Selection",
		"choices" = computed(PROC_REF(manufacturer_choices)), "timeout" = 0)), then(PROC_REF(manufacturer_chosen)))

/obj/machinery/mecha_part_fabricator_tg/prosthetics/AfterMaterialInsert()
	return // its sprite has no loading animation

/// Its open panel and its work have their own states.
/obj/machinery/mecha_part_fabricator_tg/prosthetics/draw(datum/look/look)
	..()
	look.hide("fab-active")
	if(panel_open(src))
		look.state("prosfab-o")
	else
		look.state(being_built ? "prosfab-active" : "prosfab")

/obj/machinery/mecha_part_fabricator_tg/prosthetics/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["species_types"] = species_types
	data["species"] = species
	data["manufacturer"] = manufacturer
	var/list/T = list()
	for(var/company in GLOB.all_robolimbs)
		var/datum/robolimb/R = GLOB.all_robolimbs[company]
		if(R.unavailable_to_build || (species in R.species_cannot_use))
			continue
		T += list(list("id" = company, "company" = R.company))
	data["all_manufacturers"] = T
	return data

// ---- the window's questions ----

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/species_choices(datum/act/op/A)
	return species_types

/// The manufacturers that can build for the species it is set to.
/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/manufacturer_choices(datum/act/op/A)
	. = list()
	for(var/company in GLOB.all_robolimbs)
		var/datum/robolimb/R = GLOB.all_robolimbs[company]
		if(R.unavailable_to_build || (species in R.species_cannot_use))
			continue
		. += company

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/species_chosen(datum/act/op/A)
	var/datum/prompt/P = A.answer
	if(P?.value)
		species = P.value
	return OP_OK

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/manufacturer_chosen(datum/act/op/A)
	var/datum/prompt/P = A.answer
	if(P?.value)
		manufacturer = P.value
	return OP_OK

// ---- the disks ----

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/limb_disk_valid(datum/act/op/A)
	var/obj/item/disk/limb/D = A.held
	return istype(D) && D.company && (D.company in GLOB.all_robolimbs)

/// The manufacturer's blueprints are installed: its limbs can be built.
/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/limb_disk_done(datum/act/op/A)
	var/obj/item/disk/limb/D = A.held
	add_fingerprint(A.actor)
	var/datum/robolimb/R = GLOB.all_robolimbs[D.company]
	R.unavailable_to_build = 0
	to_chat(A.actor, span_notice("Installed [D.company] blueprints!"))
	consume(D, A.actor)
	return OP_OK

/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/species_disk_valid(datum/act/op/A)
	var/obj/item/disk/species/D = A.held
	return istype(D) && D.species && (D.species in GLOB.all_species)

/// The species' files are uploaded: it can build for that species.
/obj/machinery/mecha_part_fabricator_tg/prosthetics/proc/species_disk_done(datum/act/op/A)
	var/obj/item/disk/species/D = A.held
	add_fingerprint(A.actor)
	var/upload_species = D.species
	if(!consume(D, A.actor))
		return OP_REFUSED
	species_types |= upload_species
	to_chat(A.actor, span_notice("Uploaded [upload_species] files!"))
	return OP_OK

// ---- the parts ----

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
		H.set_dir(2)
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
