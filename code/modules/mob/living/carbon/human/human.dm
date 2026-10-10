/mob/living/carbon/human
	name = "unknown"
	real_name = "unknown"
	voice_name = "unknown"
	icon = 'icons/effects/effects.dmi'	//We have an ultra-complex update icons that overlays everything, don't load some stupid random male human
	icon_state = "nothing"

	has_huds = TRUE 					//We do have HUDs (like health, wanted, status, not inventory slots)

	vore_capacity = 3
	vore_capacity_ex = list("stomach" = 3, "taur belly" = 3)
	vore_fullness_ex = list("stomach" = 0, "taur belly" = 0)
	vore_icon_bellies = list("stomach", "taur belly")
	var/struggle_anim_stomach = FALSE
	var/struggle_anim_taur = FALSE

	var/embedded_flag					//To check if we've need to roll for damage on movement while an item is imbedded in us.
	var/obj/item/rig/wearing_rig // This is very not good, but it's much much better than calling get_rig() every update_canmove() call.
	COOLDOWN_DECLARE(push_lying_cooldown) //For human_attackhand.dm: lying-struggle antispam
	COOLDOWN_DECLARE(disarm_cooldown) //For human_attackhand.dm: repeat-disarm window

	var/spitting = 0 					//Spitting and spitting related things. Any human based ranged attacks, be it innate or added abilities.
	var/spit_projectile = null			//Projectile type.
	var/spit_name = null 				//String
	COOLDOWN_DECLARE(spit_cooldown) 					//Timestamp.

	var/can_defib = 1					//Horrible damage (like beheadings) will prevent defibbing organics.
	var/active_regen = FALSE //Used for the regenerate proc in human_powers.dm
	var/active_regen_delay = 300
	COOLDOWN_DECLARE(breath_sound_cooldown)				//Allows us to store the value across proc calls per-mob.
	// ALLOW(instance_list): d: per-mob teleporters, filled at runtime; mobs are few
	var/list/teleporters = list() //Used for lleill abilities

	var/rest_dir = 0					//To lay down in a specific direction
	// ALLOW(instance_list): d: per-mob genetic_side_effects, filled at runtime; mobs are few
	var/list/datum/genetics/side_effect/genetic_side_effects = list()	//For any genetic side effects we currently have.
	COOLDOWN_DECLARE(chew_cooldown)

TYPE_TABLE_DECLARE(/mob/living/carbon/human, forced_initial_species, null)
TYPE_TABLE_DECLARE(/mob/living/carbon/human, forced_initial_hair, null)
TYPE_TABLE_DECLARE(/mob/living/carbon/human, forced_initial_faction, null)
TYPE_TABLE_DECLARE(/mob/living/carbon/human, initial_species_copy, FALSE)

/// The species a human is made as (its constructor param), or null for the default.
/mob/living/carbon/human/var/species_at_make // ALLOW(base_vars): param() carries the constructor's species into init through a var of the type it declares

// ALLOW(init/INSTANCE_STATE): a human sets up its species, DNA, blood, underwear and look around its parents' init
/mob/living/carbon/human/Initialize(mapload)
	var/forced_species = TYPE_TABLE_GET(src, forced_initial_species)
	if(forced_species)
		species_at_make = forced_species
	var/forced_hair = TYPE_TABLE_GET(src, forced_initial_hair)
	if(forced_hair)
		h_style = forced_hair
	var/forced_faction = TYPE_TABLE_GET(src, forced_initial_faction)
	if(forced_faction)
		faction = forced_faction
	if(!dna)
		rel_set(src, nameof(dna), new /datum/dna(null)) // ALLOW(decl): needed before parent init by set_species(); ctor takes an arg
		// Species name is handled by set_species()

	if(!species)
		if(species_at_make)
			set_species(species_at_make)
		else
			set_species()

	if(species)
		real_name = species.get_random_name(gender)
		name = real_name
		if(mind)
			mind.name = real_name

	set_nutrition(rand(200,400))
	if(forced_species)
		. = ..(mapload, forced_species)
	else
		. = ..()

	hide_underwear.Cut()
	for(var/category in GLOB.global_underwear.categories_by_name)
		hide_underwear[category] = FALSE

	if(dna)
		dna.ready_dna(src)
		dna.real_name = real_name
		sync_dna_traits(FALSE) // Traitgenes Sync traits to genetics if needed
		sync_organ_dna()
	initialize_vessel()
	regenerate_icons()

	add_hose_connector(/datum/hose_connector/inflation) // Comment out to disable all human mob inflation mechanics

	// Chicken Stuff
	var/animal = pick("cow","chicken_brown", "chicken_black", "chicken_white", "chick", "mouse_brown", "mouse_gray", "mouse_white", "lizard", "cat2", "goose", "penguin")
	var/image/img = image('icons/mob/animal.dmi', src, animal)
	img.override = TRUE
	add_alt_appearance("animals", img, displayTo = REGISTRY_MEMBERS(REGISTRY_ALT_FARMANIMALS))
	if(TYPE_TABLE_GET(src, initial_species_copy))
		species.produceCopy(species.traits.Copy(),src,null,FALSE)

REGISTRY_MEMBERSHIP(/mob/living/carbon/human, REGISTRY_HUMANS)

REGISTRY_MEMBERSHIP(/mob/living/carbon/human, REGISTRY_ALT_FARMANIMALS)

REGISTRY_MEMBERSHIP(/mob/living/carbon/human, REGISTRY_PRISONWARPED)

/mob/living/carbon/human/get_status_tab_items()
	. = ..()
	. += ""
	. += "Combat mode: [combat_mode ? "on" : "off"]"
	. += "Move Mode: [m_intent]"
	if(SSemergency_shuttle)
		var/eta_status = SSemergency_shuttle.get_status_panel_eta()
		if(eta_status)
			. += "[eta_status]"

	if (internal)
		if (!internal.air_contents)
			spent(internal)
		else
			. += "Internal Atmosphere Info: [internal.name]"
			. += "Tank Pressure: [internal.air_contents.return_pressure()]"
			. += "Distribution Pressure: [internal.distribute_pressure]"

	var/obj/item/organ/internal/xenos/plasmavessel/P = organ_in(O_PLASMA) //Xenomorphs. Mech.
	if(P)
		. += "Phoron Stored: [P.stored_plasma]/[P.max_plasma]"

	if(get_equipped_item(SLOT_ID_BACK) && istype(get_equipped_item(SLOT_ID_BACK),/obj/item/rig))
		var/obj/item/rig/suit = get_equipped_item(SLOT_ID_BACK)
		var/cell_status = "ERROR"
		if(suit.cell) cell_status = "[suit.cell.charge]/[suit.cell.maxcharge]"
		. += "Suit charge: [cell_status]"

	var/datum/changeling/comp = is_changeling(src)
	if(comp)
		. += "Chemical Storage: [comp.chem_charges]"
		. += "Genetic Damage Time: [comp.geneticdamage]"
		. += "Re-Adaptations: [comp.readapts]/[comp.max_readapts]"
	if(species)
		species.get_status_tab_items(src)

/mob/proc/RigPanel(obj/item/rig/R)
	if(R && !R.canremove && length(R.installed_modules))
		var/list/L = list()
		var/cell_status = R.cell ? "[R.cell.charge]/[R.cell.maxcharge]" : "ERROR"
		L[++L.len] = list("Suit charge: [cell_status]", null, null, null, null)
		for(var/obj/item/rig_module/module in R.installed_modules)
		{
			for(var/atom/movable/stat_rig_module/SRM in module.stat_modules)
				if(SRM.CanUse())
					L[++L.len] = list(SRM.module.interface_name,null,null,SRM.name,REF(SRM))
		}
		misc_tabs["Hardsuit Modules"] = L

/mob/living/update_misc_tabs()
	..()
	if(get_rig_stats)
		var/obj/item/rig/rig = get_rig()
		if(rig)
			RigPanel(rig)

/mob/living/carbon/human/update_misc_tabs()
	..()
	if(species)
		species.update_misc_tabs(src)

	if(istype(get_equipped_item(SLOT_ID_BACK),/obj/item/rig))
		var/obj/item/rig/R = get_equipped_item(SLOT_ID_BACK)
		RigPanel(R)

	else if(istype(get_equipped_item(SLOT_ID_BELT),/obj/item/rig))
		var/obj/item/rig/R = get_equipped_item(SLOT_ID_BELT)
		RigPanel(R)

/mob/living/carbon/human/ex_act(severity)
	if(..())
		return
	if(is_incorporeal()) // Can't explode shadekin in phase
		return

	if(!blinded)
		flash_eyes()

	var/explosion_shift = factor(BF_EXPLOSION_SHIFT)
	if(explosion_shift)
		severity = CLAMP(severity + explosion_shift, 1, 4)

	severity = round(severity)

	if(severity > 3)
		return

	var/shielded = 0
	var/b_loss = null
	var/f_loss = null
	switch (severity)
		if (1.0)
			b_loss += 500
			if (!prob(injury_armor(ARMOR_BLAST, null)))
				gib()
				return
			else
				var/atom/target = get_edge_target_turf(src, get_dir(src, get_step_away(src, src)))
				throw_at(target, 200, 4)

		if (2.0)
			if (!shielded)
				b_loss += 60

			f_loss += 60

			if (prob(injury_armor(ARMOR_BLAST, null)))
				b_loss = b_loss/1.5
				f_loss = f_loss/1.5

			if (get_ear_protection() < 2)
				set_ear_damage(ear_damage + (30))
				status_adjust(STAT_DEAFENED, 120)
				deaf_loop.start() // Ear Ringing/Deafness
			if (prob(70) && !shielded)
				status_at_least(STAT_PARALYZED, 10)
				status_at_least(STAT_SLEEPING, 10)

		if(3.0)
			b_loss += 30
			if (prob(injury_armor(ARMOR_BLAST, null)))
				b_loss = b_loss/2
			if (get_ear_protection() < 2)
				set_ear_damage(ear_damage + (15))
				status_adjust(STAT_DEAFENED, 60)
				deaf_loop.start() // Ear Ringing/Deafness
			if (prob(50) && !shielded)
				status_at_least(STAT_PARALYZED, 10)
				status_at_least(STAT_SLEEPING, 10)

	// focus most of the blast on one organ
	var/obj/item/organ/external/take_blast = pick(organs)
	blast_injury(take_blast.organ_tag, b_loss * 0.9, f_loss * 0.9)

	// distribute the remaining 10% on all limbs equally
	b_loss *= 0.1
	f_loss *= 0.1

	for(var/obj/item/organ/external/temp in organs)
		switch(temp.organ_tag)
			if(BP_HEAD)
				blast_injury(temp.organ_tag, b_loss * 0.2, f_loss * 0.2)
			if(BP_TORSO)
				blast_injury(temp.organ_tag, b_loss * 0.4, f_loss * 0.4)
			else
				blast_injury(temp.organ_tag, b_loss * 0.05, f_loss * 0.05)

/// Explosive blast: concussive (blunt) and thermal (burn) injury to one part.
/mob/living/carbon/human/proc/blast_injury(zone, blunt, burn)
	injure(INJURY_BLUNT, blunt, zone)
	injure(INJURY_BURN, burn, zone)

/mob/living/carbon/human/proc/implant_loyalty(override = FALSE) // Won't override by default.
	if(!CONFIG_GET(flag/use_loyalty_implants) && !override) return // Nuh-uh.

	var/obj/item/implant/loyalty/L = new/obj/item/implant/loyalty(src)
	if(L.handle_implant(src, BP_HEAD))
		L.post_implant(src)

/mob/living/carbon/human/proc/is_loyalty_implanted()
	for(var/L in contents_of(src))
		if(istype(L, /obj/item/implant/loyalty))
			for(var/obj/item/organ/external/O in src.organs)
				if(L in O.implants)
					return 1
	return 0

/mob/living/carbon/human/restrained()
	if (get_equipped_item(SLOT_ID_HANDCUFFED))
		return 1
	if (istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/straight_jacket))
		return 1
	if (istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/shibari))
		var/obj/item/clothing/suit/shibari/s = get_equipped_item(SLOT_ID_SUIT)
		if(s.rope_mode == "Arms" || s.rope_mode == "Arms and Legs")
			return 1
	return 0


// called when something steps onto a human
// this handles mobs on fire - mulebot and vehicle code has been relocated to /mob/living/Crossed()
/mob/living/carbon/human/Crossed(atom/movable/AM)
	if(AM.is_incorporeal())
		return

	spreadFire(AM)

	..() // call parent because we moved behavior to parent

// Get rank from ID, ID inside PDA, PDA, ID in wallet, etc.
/mob/living/carbon/human/proc/get_authentification_rank(if_no_id = "No id", if_no_job = "No job")
	var/obj/item/pda/pda = get_equipped_item(SLOT_ID_ID)
	if (istype(pda))
		if (pda.id)
			return pda.id.rank ? pda.id.rank : if_no_job
		else
			return pda.ownrank ? pda.ownrank : if_no_job
	else
		var/obj/item/card/id/id = get_idcard()
		if(id)
			return id.rank ? id.rank : if_no_job
		else
			return if_no_id

//gets assignment from ID or ID inside PDA or PDA itself
//Useful when player do something with computers
/mob/living/carbon/human/proc/get_assignment(if_no_id = "No id", if_no_job = "No job")
	var/obj/item/pda/pda = get_equipped_item(SLOT_ID_ID)
	if (istype(pda))
		if (pda.id)
			return pda.id.assignment
		else
			return pda.ownjob ? pda.ownjob : if_no_job
	else
		var/obj/item/card/id/id = get_idcard()
		if(id)
			return id.assignment ? id.assignment : if_no_job
		else
			return if_no_id

//gets name from ID or ID inside PDA or PDA itself
//Useful when player do something with computers
/mob/living/carbon/human/proc/get_authentification_name(if_no_id = "Unknown")
	var/obj/item/pda/pda = get_equipped_item(SLOT_ID_ID)
	if (istype(pda))
		if (pda.id)
			return pda.id.registered_name
		else
			return pda.owner ? pda.owner : if_no_id
	else
		var/obj/item/card/id/id = get_idcard()
		if(id)
			return id.registered_name
		else
			return if_no_id

//repurposed proc. Now it combines get_id_name() and get_face_name() to determine a mob's name variable. Made into a seperate proc as it'll be useful elsewhere
/mob/living/carbon/human/get_visible_name()
	var/datum/act/name_visible/shown = ACT_TRY(src, name_visible)
	if(!shown)
		return ACT_REPLY
	act_cancel(shown)

	if(get_equipped_item(SLOT_ID_MASK) && (get_equipped_item(SLOT_ID_MASK).flags_inv&HIDEFACE))	//Wearing a mask which hides our face, use id-name if possible
		return get_id_name("Unknown")
	if(get_equipped_item(SLOT_ID_HEAD) && (get_equipped_item(SLOT_ID_HEAD).flags_inv&HIDEFACE))
		return get_id_name("Unknown")		//Likewise for hats
	var/face_name = get_face_name()
	var/id_name = get_id_name("")
	if((face_name == "Unknown") && id_name && (id_name != face_name))
		return "[face_name] (as [id_name])"
	return face_name

//Returns "Unknown" if facially disfigured and real_name if not. Useful for setting name when polyacided or when updating a human's name variable
/mob/living/carbon/human/proc/get_face_name()
	var/obj/item/organ/external/head = get_organ(BP_HEAD)
	if(!head || head.disfigured || head.is_stump() || !real_name || (has_mutation(HUSK)) )	//disfigured. use id-name if possible
		return "Unknown"
	return real_name

//gets name from ID or PDA itself, ID inside PDA doesn't matter
//Useful when player is being seen by other mobs
/mob/living/carbon/human/proc/get_id_name(if_no_id = "Unknown")
	. = if_no_id
	if(istype(get_equipped_item(SLOT_ID_ID),/obj/item/pda))
		var/obj/item/pda/P = get_equipped_item(SLOT_ID_ID)
		return P.owner ? P.owner : if_no_id
	if(get_equipped_item(SLOT_ID_ID))
		var/obj/item/card/id/I = get_equipped_item(SLOT_ID_ID).GetID()
		if(I)
			return I.registered_name
	return

//gets ID card object from special clothes slot or null.
/mob/living/carbon/human/proc/get_idcard()
	if(get_equipped_item(SLOT_ID_ID))
		return get_equipped_item(SLOT_ID_ID).GetID()

//Removed the horrible safety parameter. It was only being used by ninja code anyways.
//Now checks siemens_coefficient of the affected area by default
/mob/living/carbon/human/electrocute_act(shock_damage, obj/source, siemens_coeff = 1.0, def_zone = null, stun)

	if(in_godmode(src))
		return 0

	if (!def_zone)
		def_zone = pick(BP_L_HAND, BP_R_HAND)

	if(species.siemens_coefficient == -1)
		if(GLOB.stored_shock_by_ref["\ref[src]"])
			GLOB.stored_shock_by_ref["\ref[src]"] += shock_damage
		else
			GLOB.stored_shock_by_ref["\ref[src]"] = shock_damage
		return

	var/obj/item/organ/external/affected_organ = get_organ(check_zone(def_zone))
	siemens_coeff = siemens_coeff * get_siemens_coefficient_organ(affected_organ)
	if(fire_stacks < 0) // Water makes you more conductive.
		siemens_coeff *= 1.5

	. = ..(shock_damage, source, siemens_coeff, def_zone)
	// A strong current across the chest can throw the heart into VF.
	if(. > 30 && prob(. - 20))
		induce_arrhythmia(CARDIAC_RHYTHM_VF)

// HUD record links (examine): see TYPE_TABLE_GET(src, hud_record_kinds).

/// TOPIC_REF source: everything this human wears or carries (accessories included).
/mob/living/carbon/human/proc/topic_worn_items()
	return get_all_contents()

/mob/living/carbon/human/proc/topic_lookitem(datum/act/op/A, href_lookitem)
	var/obj/item/I = href_lookitem
	src.examinate(I)
	return TRUE

/mob/living/carbon/human/proc/topic_lookitem_desc_only(datum/act/op/A, href_lookitem_desc_only)
	var/mob/user = A.actor
	var/obj/item/I = href_lookitem_desc_only
	if(istype(I,/obj/item/hand))
		to_chat(user,span_warning("You can't see the card faces from here."))
		return
	user.examinate(I, 1)
	return TRUE

/mob/living/carbon/human/topic_flavor_change(datum/act/op/A, href_flavor_change)
	var/mob/user = A.actor
	flavor_change_topic(user, href_flavor_change)
	return TRUE

/mob/living/carbon/human/proc/topic_hud_criminal(datum/act/op/A)
	var/mob/user = A.actor
	if(hasHUD(user, "security"))
		hud_topic_status(user, "security")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_medical(datum/act/op/A)
	var/mob/user = A.actor
	if(hasHUD(user, "medical"))
		hud_topic_status(user, "medical")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_secrecord(datum/act/op/A)
	var/mob/user = A.actor
	hud_record_link(user, "security", "show")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_medrecord(datum/act/op/A)
	var/mob/user = A.actor
	hud_record_link(user, "medical", "show")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_emprecord(datum/act/op/A)
	var/mob/user = A.actor
	hud_record_link(user, "best", "show")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_seccomments(datum/act/op/A)
	var/mob/user = A.actor
	hud_record_link(user, "security", "comments")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_medcomments(datum/act/op/A)
	var/mob/user = A.actor
	hud_record_link(user, "medical", "comments")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_empcomments(datum/act/op/A)
	var/mob/user = A.actor
	hud_record_link(user, "best", "comments")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_secadd(datum/act/op/A)
	var/mob/user = A.actor
	hud_record_link(user, "security", "add")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_medadd(datum/act/op/A)
	var/mob/user = A.actor
	hud_record_link(user, "medical", "add")
	return TRUE

/mob/living/carbon/human/proc/topic_hud_empadd(datum/act/op/A)
	var/mob/user = A.actor
	hud_record_link(user, "best", "add")
	return TRUE

/// The flavor text editor's links: close it, or edit one part.
/mob/living/carbon/human/proc/flavor_change_topic(mob/user, part)
	switch(part)
		if("done")
			// flavor_changes is TGUI now; close via SStgui
			SStgui.close_uis(src)
		if("general")
			open_request(src, /datum/prompt/text/flavor_part, PROC_REF(flavor_part_entered), answerer = user, question = "Update the general description of your character. This will be shown regardless of clothing.", default = html_decode(LAZYACCESS(flavor_texts, part)), part = part)	//Separating out OOC notes
		else
			open_request(src, /datum/prompt/text/flavor_part, PROC_REF(flavor_part_entered), answerer = user, question = "Update the flavor text for your [part].", default = html_decode(LAZYACCESS(flavor_texts, part)), part = part)

// --- HUD record links (examine) --------------------------------------------------
// Each HUD reads and writes one record set. The status link edits the "status" set (the
// medical status lives on the general record), the rest the "records" set.

/// HUD type -> list(href prefix, records set, status set, title, comment length).
TYPE_TABLE_DECLARE(/mob/living/carbon/human, hud_record_kinds, list( \
		"security" = list("sec", "security", "security", "Sec. records", MAX_MESSAGE_LEN), \
		"medical" = list("med", "medical", "general", "Med. records", MAX_MESSAGE_LEN), \
		"best" = list("emp", "general", "general", "Emp. records", MAX_RECORD_LENGTH), \
	))


/// Handle a HUD record link for `hud_type`: "show" the record, its "comments", or "add" one.
/mob/living/carbon/human/proc/hud_record_link(mob/user, hud_type, what)
	if(!hasHUD(user, hud_type))
		return
	var/list/kind = TYPE_TABLE_GET(src, hud_record_kinds)[hud_type]
	switch(what)
		if("show")
			hud_topic_show_record(user, hud_type)
		if("comments")
			hud_topic_show_comments(user, hud_type)
		if("add")
			var/datum/data/record/R = hud_find_record(kind[2])
			if(R)
				hud_ask_comment(user, R, hud_type, kind[4], kind[5])
	return TRUE

/// Our record in data core set `set_name` ("general", "security" or "medical"), matched through
/// the general record of our ID's name (else our name).
/mob/living/carbon/human/proc/hud_find_record(set_name)
	var/obj/item/card/id/I = GetIdCard()
	var/perpname = I ? I.registered_name : name
	if(!perpname)
		return null
	var/list/records
	switch(set_name)
		if("security")
			records = GLOB.data_core.security
		if("medical")
			records = GLOB.data_core.medical
		else
			records = GLOB.data_core.general
	for(var/datum/data/record/E in GLOB.data_core.general)
		if(E.fields["name"] != perpname)
			continue
		for(var/datum/data/record/R in records)
			if(R.fields["id"] == E.fields["id"])
				return R
	return null

/mob/living/carbon/human/proc/hud_no_record(mob/user)
	to_chat(user, span_filter_notice("[span_red("Unable to locate a data core entry for this person.")]"))

/// The criminal (security) or physical (medical) status picker.
/mob/living/carbon/human/proc/hud_topic_status(mob/user, hud_type)
	var/datum/data/record/R = hud_find_record(TYPE_TABLE_GET(src, hud_record_kinds)[hud_type][3])
	if(!R)
		hud_no_record(user)
		return
	if(hud_type == "security")
		open_request(src, /datum/prompt/choice/hud_status, PROC_REF(hud_criminal_status_chosen), answerer = user, question = "Specify a new criminal status for this person.", title = "Security HUD", choices = list("None", "*Arrest*", "Incarcerated", "Parolled", "Released", "Cancel"), record = R, hud_type = "security")
	else
		open_request(src, /datum/prompt/choice/hud_status, PROC_REF(hud_medical_status_chosen), answerer = user, question = "Specify a new medical status for this person.", title = "Medical HUD", choices = list("*SSD*", "*Deceased*", "Physically Unfit", "Active", "Disabled", "Cancel"), record = R, hud_type = "medical")

/// Print the record `hud_type` reads.
/mob/living/carbon/human/proc/hud_topic_show_record(mob/user, hud_type)
	var/list/kind = TYPE_TABLE_GET(src, hud_record_kinds)[hud_type]
	var/datum/data/record/R = hud_find_record(kind[2])
	if(!R)
		hud_no_record(user)
		return
	var/list/text = list()
	switch(hud_type)
		if("security")
			text += span_bold("Name:") + " [R.fields["name"]]	" + span_bold("Criminal Status:") + " [R.fields["criminal"]]"
			text += span_bold("Species:") + " [R.fields["species"]]"
			text += span_bold("Minor Crimes:") + " [R.fields["mi_crim"]]"
			text += span_bold("Details:") + " [R.fields["mi_crim_d"]]"
			text += span_bold("Major Crimes:") + " [R.fields["ma_crim"]]"
			text += span_bold("Details:") + " [R.fields["ma_crim_d"]]"
		if("medical")
			text += span_bold("Name:") + " [R.fields["name"]]	" + span_bold("Blood Type:") + " [R.fields["b_type"]]	" + span_bold("Blood Basis:") + " [R.fields["blood_reagent"]]"
			text += span_bold("Species:") + " [R.fields["species"]]"
			text += span_bold("DNA:") + " [R.fields["b_dna"]]"
			text += span_bold("Minor Disabilities:") + " [R.fields["mi_dis"]]"
			text += span_bold("Details:") + " [R.fields["mi_dis_d"]]"
			text += span_bold("Major Disabilities:") + " [R.fields["ma_dis"]]"
			text += span_bold("Details:") + " [R.fields["ma_dis_d"]]"
		else
			text += span_bold("Name:") + " [R.fields["name"]]"
			text += span_bold("Species:") + " [R.fields["species"]]"
			text += span_bold("Assignment:") + " [R.fields["real_rank"]] ([R.fields["rank"]])"
			text += span_bold("Home System:") + " [R.fields["home_system"]]"
			text += span_bold("Birthplace:") + " [R.fields["birthplace"]]"
			text += span_bold("Citizenship:") + " [R.fields["citizenship"]]"
			text += span_bold("Primary Employer:") + " [R.fields["faction"]]"
			text += span_bold("Religious Beliefs:") + " [R.fields["religion"]]"
			text += span_bold("Known Languages:") + " [R.fields["languages"]]"
	text += span_bold("Notes:") + " [R.fields["notes"]]"
	text += "<a href='byond://?src=\ref[src];[kind[1]]recordComment=`'>\[View Comment Log\]</a>"
	to_chat(user, span_filter_notice("[jointext(text, "<br>")]"))

/// Print the comment log of the record `hud_type` reads.
/mob/living/carbon/human/proc/hud_topic_show_comments(mob/user, hud_type)
	var/list/kind = TYPE_TABLE_GET(src, hud_record_kinds)[hud_type]
	var/datum/data/record/R = hud_find_record(kind[2])
	if(!R)
		hud_no_record(user)
		return
	var/counter = 1
	while(R.fields["com_[counter]"])
		to_chat(user, "[R.fields["com_[counter]"]]")
		counter++
	if(counter == 1)
		to_chat(user, span_filter_notice("No comment found."))
	to_chat(user, span_filter_notice("<a href='byond://?src=\ref[src];[kind[1]]recordadd=`'>\[Add comment\]</a>"))

/// Editing one flavor text part. Re-checked on the answer: it's your own.
/datum/prompt/text/flavor_part
	title = "Flavor Text"
	multiline = TRUE
	timeout = 0
	var/part

/datum/prompt/text/flavor_part/recheck_extra()
	if(!isnull(value) && answerer != owner)
		return "not yours"

/mob/living/carbon/human/proc/flavor_part_entered(datum/act/request/A)
	if(!A.answer)
		return
	return flavor_part_entered_apply(A)

/mob/living/carbon/human/proc/flavor_part_entered_apply(datum/act/request/A)
	var/datum/prompt/text/flavor_part/ask = A.answer
	var/msg = strip_html_simple(ask.value)
	if(msg)
		LAZYSET(flavor_texts, ask.part, msg)
		set_flavor()

/// The user's HUD of `hud_type` still works and they can act.
/mob/living/carbon/human/proc/hud_still_usable(mob/user, hud_type)
	return !user.stat && !user.restrained() && hasHUD(user, hud_type)

/// Whoever changed a record through their HUD sees it change: their HUD re-reads what it shows (MOB_KEY_VIEW).
/mob/living/carbon/human/proc/hud_record_changed(mob/user)
	PUBLISH_CHANGE(user, MOB_KEY_VIEW)

/// A record status picked through a HUD on the subject. Re-checked on the answer: the HUD still works.
/datum/prompt/choice/hud_status
	timeout = 0
	var/datum/data/record/record
	var/hud_type
	var/record_expected = FALSE

CAPABILITIES(/datum/prompt/choice/hud_status)
	ref_one(nameof(record), /datum/data/record)

/datum/prompt/choice/hud_status/prepare(datum/act/A)
	. = ..()
	var/datum/data/record/captured_record = record
	record_expected = !isnull(captured_record)
	rel_clear(src, nameof(record))
	if(captured_record && !QDELETED(captured_record))
		rel_set(src, nameof(record), captured_record)

/datum/prompt/choice/hud_status/recheck_extra()
	if(record_expected && QDELETED(record))
		return "gone"
	if(isnull(value))
		return
	var/mob/living/carbon/human/H = owner
	return H.hud_still_usable(answerer, hud_type) ? null : "HUD unusable"

/// A record comment added through a HUD on the subject. Re-checked on the answer: the HUD still works.
/datum/prompt/text/hud_comment
	question = "Add Comment:"
	multiline = TRUE
	timeout = 0
	var/datum/data/record/record
	var/hud_type
	var/record_expected = FALSE

CAPABILITIES(/datum/prompt/text/hud_comment)
	ref_one(nameof(record), /datum/data/record)

/datum/prompt/text/hud_comment/prepare(datum/act/A)
	. = ..()
	var/datum/data/record/captured_record = record
	record_expected = !isnull(captured_record)
	rel_clear(src, nameof(record))
	if(captured_record && !QDELETED(captured_record))
		rel_set(src, nameof(record), captured_record)

/datum/prompt/text/hud_comment/recheck_extra()
	if(record_expected && QDELETED(record))
		return "gone"
	if(isnull(value))
		return
	var/mob/living/carbon/human/H = owner
	return H.hud_still_usable(answerer, hud_type) ? null : "HUD unusable"

/mob/living/carbon/human/proc/hud_criminal_status_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return hud_criminal_status_chosen_apply(A)

/mob/living/carbon/human/proc/hud_criminal_status_chosen_apply(datum/act/request/A)
	var/datum/prompt/choice/hud_status/ask = A.answer
	var/setcriminal = ask.value
	var/mob/user = ask.answerer
	if(setcriminal == "Cancel")
		return
	var/datum/data/record/R = ask.record
	R.fields["criminal"] = setcriminal
	flag_hud_update(WANTED_HUD)
	hud_record_changed(user)

/mob/living/carbon/human/proc/hud_medical_status_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return hud_medical_status_chosen_apply(A)

/mob/living/carbon/human/proc/hud_medical_status_chosen_apply(datum/act/request/A)
	var/datum/prompt/choice/hud_status/ask = A.answer
	var/setmedical = ask.value
	var/mob/user = ask.answerer
	if(setmedical == "Cancel")
		return
	var/datum/data/record/R = ask.record
	R.fields["p_stat"] = setmedical
	if(GLOB.PDA_Manifest.len)
		GLOB.PDA_Manifest.Cut()
	hud_record_changed(user)

/// Asks for a comment to add to record R through a HUD of `hud_type`.
/mob/living/carbon/human/proc/hud_ask_comment(mob/user, datum/data/record/R, hud_type, title, max_length)
	open_request(src, /datum/prompt/text/hud_comment, PROC_REF(hud_comment_entered), answerer = user, title = title, max_len = max_length, name_text = max_length && max_length <= MAX_NAME_LEN, record = R, hud_type = hud_type)

/mob/living/carbon/human/proc/hud_comment_entered(datum/act/request/A)
	if(!A.answer)
		return
	return hud_comment_entered_apply(A)

/mob/living/carbon/human/proc/hud_comment_entered_apply(datum/act/request/A)
	var/datum/prompt/text/hud_comment/ask = A.answer
	var/t1 = ask.value
	var/mob/user = ask.answerer
	if(!t1)
		return
	var/datum/data/record/R = ask.record
	var/counter = 1
	while(R.fields[text("com_[]", counter)])
		counter++
	if(ishuman(user))
		var/mob/living/carbon/human/U = user
		R.fields[text("com_[counter]")] = text("Made by [U.get_authentification_name()] ([U.get_assignment()]) on [time2text(world.realtime, "DDD MMM DD hh:mm:ss")], [GLOB.game_year]<BR>[t1]")
	if(istype(user,/mob/living/silicon/robot))
		var/mob/living/silicon/robot/U = user
		R.fields[text("com_[counter]")] = text("Made by [U.name] ([U.modtype] [U.braintype]) on [time2text(world.realtime, "DDD MMM DD hh:mm:ss")], [GLOB.game_year]<BR>[t1]")

///eyecheck()
///Returns a number between -1 to 2
/mob/living/carbon/human/eyecheck()

	var/obj/item/organ/internal/eyes/I

	if(organ_in(O_EYES)) // Eyes are fucked, not a 'weak point'.
		I = organ_in(O_EYES)
		if(I.is_broken())
			return FLASH_PROTECTION_MAJOR
	else if(!species.dispersed_eyes) // They can't be flashed if they don't have eyes, or widespread sensing surfaces.
		return FLASH_PROTECTION_MAJOR

	var/number = get_equipment_flash_protection()
	if(I)
		number = I.get_total_protection(number)
		I.additional_flash_effects(number)
	return number

/mob/living/carbon/human/flash_eyes(intensity = FLASH_PROTECTION_MODERATE, override_blindness_check = FALSE, affect_silicon = FALSE, visual = FALSE, type = /atom/movable/screen/fullscreen/flash)
	if(organ_in(O_EYES)) // Eyes are fucked, not a 'weak point'.
		var/obj/item/organ/internal/eyes/I = organ_in(O_EYES)
		I.additional_flash_effects(intensity)
	return ..()

#define add_clothing_protection(A)	\
	var/obj/item/clothing/C = A; \
	flash_protection += C.flash_protection; \

/mob/living/carbon/human/proc/get_equipment_flash_protection()
	var/flash_protection = 0

	if(istype(get_equipped_item(SLOT_ID_HEAD), /obj/item/clothing/head))
		add_clothing_protection(get_equipped_item(SLOT_ID_HEAD))
	if(istype(get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses))
		add_clothing_protection(get_equipped_item(SLOT_ID_EYES))
	if(istype(get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask))
		add_clothing_protection(get_equipped_item(SLOT_ID_MASK))

	return flash_protection

#undef add_clothing_protection

//Used by various things that knock people out by applying blunt trauma to the head.
//Checks that the species has a "head" (brain containing organ) and that hit_zone refers to it.
/mob/living/carbon/human/proc/headcheck(target_zone, brain_tag = O_BRAIN)

	var/obj/item/organ/affecting = organ_in(brain_tag)

	target_zone = check_zone(target_zone)
	if(!affecting || affecting.parent_organ != target_zone)
		return 0

	//if the parent organ is significantly larger than the brain organ, then hitting it is not guaranteed
	var/obj/item/organ/parent = get_organ(target_zone)
	if(!parent)
		return 0

	if(parent.w_class > affecting.w_class + 1)
		return prob(100 / 2**(parent.w_class - affecting.w_class - 1))

	return 1

/mob/living/carbon/human/IsAdvancedToolUser(silent)
	if(get_feralness())
		to_chat(src, span_warning("Your primitive mind can't grasp the concept of that thing."))
		return 0
	if(species.has_fine_manipulation)
		return 1
	if(!silent)
		to_chat(src, span_warning("You don't have the dexterity to use that!"))
	return 0

/mob/living/carbon/human/abiotic(full_body = 0)
	if(full_body && ((get_equipped_item(SLOT_ID_HAND_L) && !( get_equipped_item(SLOT_ID_HAND_L).abstract )) || (get_equipped_item(SLOT_ID_HAND_R) && !( get_equipped_item(SLOT_ID_HAND_R).abstract )) || (get_equipped_item(SLOT_ID_BACK) || get_equipped_item(SLOT_ID_MASK) || get_equipped_item(SLOT_ID_HEAD) || get_equipped_item(SLOT_ID_SHOES) || get_equipped_item(SLOT_ID_UNIFORM) || get_equipped_item(SLOT_ID_SUIT) || get_equipped_item(SLOT_ID_EYES) || get_equipped_item(SLOT_ID_EAR_L) || get_equipped_item(SLOT_ID_EAR_R) || get_equipped_item(SLOT_ID_GLOVES))))
		return 1

	if( (get_equipped_item(SLOT_ID_HAND_L) && !get_equipped_item(SLOT_ID_HAND_L).abstract) || (get_equipped_item(SLOT_ID_HAND_R) && !get_equipped_item(SLOT_ID_HAND_R).abstract) )
		return 1

	return 0

/mob/living/carbon/human/proc/check_dna()
	dna.check_integrity(src)
	return

/mob/living/carbon/human/get_species()
	if(!species)
		set_species()
	return species.name

/mob/living/carbon/human/proc/play_xylophone()
	if(COOLDOWN_FINISHED(src, xylophone))
		act_message(src, null, MSG_SELF(span_notice("You begin to play a spooky refrain on your ribcage.")), \
			MSG_OTHERS(span_filter_notice("[span_red("%U% begins playing %THEIR% ribcage like a xylophone. It's quite spooky.")]")), \
			MSG_BLIND(span_filter_notice("[span_red("You hear a spooky xylophone melody.")]")))
		var/song = SFX_EFFECTS_XYLOPHONE_MIX
		playsound(src, song, 50, 1, -1)
		COOLDOWN_START(src, xylophone, 2 MINUTES)
	return

/mob/living/proc/check_has_mouth()
	return 1

/mob/living/carbon/human/check_has_mouth()
	// Todo, check stomach organ when implemented.
	var/obj/item/organ/external/head/H = get_organ(BP_HEAD)
	if(!H || !H.can_intake_reagents)
		return 0
	return 1

/mob/living/carbon/human/proc/morph()
	set name = "Morph"
	set category = VERB_CAT_SUPERPOWER

	if(stat!=CONSCIOUS)
		return

	if(!(has_mutation(mMorph)))
		revoke(src, granted_verb(/mob/living/carbon/human/proc/morph), verb_source(VERB_SOURCE_ADMIN)) // only an admin hand grants it
		return

	// hair
	var/list/all_hairs = subtypesof(/datum/sprite_accessory/hair)
	var/list/hairs = list()

	// loop through potential hairs
	for(var/x in all_hairs)
		var/datum/sprite_accessory/hair/H = new x // create new hair datum based on type x
		hairs.Add(H.name) // add hair name to hairs
		spent(H) // delete the hair after it's all done

	// facial hair
	var/list/all_fhairs = subtypesof(/datum/sprite_accessory/facial_hair)
	var/list/fhairs = list()

	for(var/x in all_fhairs)
		var/datum/sprite_accessory/facial_hair/H = new x
		fhairs.Add(H.name)
		spent(H)

	// Every question can be skipped (cancel keeps what you have).
	var/datum/morph_review/review = new
	rel_set(review, nameof(review.actor), src)
	review.hairs = hairs
	review.fhairs = fhairs
	review.start()

/// The morph questions, one after another; each can be skipped (a cancel answers "").
/// Re-checked before every step: still conscious and still a morph.
/datum/morph_review
	parent_type = /datum/prompt_workflow
	var/mob/living/carbon/human/actor
	var/list/hairs
	var/list/fhairs
	var/facial_color
	var/hair_color
	var/eye_color
	var/hair
	var/facial

CAPABILITIES(/datum/morph_review)
	ref_one(nameof(actor), /mob/living/carbon/human)

/datum/prompt/color/morph
	title = "Character Generation"
	timeout = 0

/datum/prompt/color/morph/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/morph_review/review = owner
	return review.why_not()

/datum/prompt/choice/morph
	title = "Character Generation"
	timeout = 0

/datum/prompt/choice/morph/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/morph_review/review = owner
	return review.why_not()

/datum/morph_review/proc/why_not()
	if(QDELETED(actor))
		return "gone"
	if(actor.stat != CONSCIOUS)
		return "not conscious"
	return actor.has_mutation(mMorph) ? null : "not a morph"

/datum/morph_review/proc/start()
	if(why_not())
		retire()
		return
	run_step(PROC_REF(start_step))

/datum/morph_review/proc/run_step(step, datum/act/request/A)
	var/datum/result/result = safe_call(step, A)
	if(!result.ok)
		stack_trace("morph step [step]: [result.error]")
		retire()

/datum/morph_review/proc/accept_or_skip(datum/act/request/A)
	// Even an old cancel_answer empty string resumed and rechecked the flow.
	return !why_not() && (A.answer || (A.request.outcome == REQ_CANCELLED && isnull(A.request.value)))

/datum/morph_review/proc/start_step()
	open_request(src, /datum/prompt/color/morph, PROC_REF(facial_color_picked), answerer = actor, question = "Please select facial hair color.", default = rgb(actor.r_facial, actor.g_facial, actor.b_facial))

/datum/morph_review/proc/facial_color_picked(datum/act/request/A)
	run_step(PROC_REF(facial_color_picked_step), A)

/datum/morph_review/proc/facial_color_picked_step(datum/act/request/A)
	if(!accept_or_skip(A))
		retire()
		return
	facial_color = A.answer ? A.request.value : ""
	open_request(src, /datum/prompt/color/morph, PROC_REF(hair_color_picked), answerer = actor, question = "Please select hair color.", default = rgb(actor.r_hair, actor.g_hair, actor.b_hair))

/datum/morph_review/proc/hair_color_picked(datum/act/request/A)
	run_step(PROC_REF(hair_color_picked_step), A)

/datum/morph_review/proc/hair_color_picked_step(datum/act/request/A)
	if(!accept_or_skip(A))
		retire()
		return
	hair_color = A.answer ? A.request.value : ""
	open_request(src, /datum/prompt/color/morph, PROC_REF(eye_color_picked), answerer = actor, question = "Please select eye color.", default = rgb(actor.r_eyes, actor.g_eyes, actor.b_eyes))

/datum/morph_review/proc/eye_color_picked(datum/act/request/A)
	run_step(PROC_REF(eye_color_picked_step), A)

/datum/morph_review/proc/eye_color_picked_step(datum/act/request/A)
	if(!accept_or_skip(A))
		retire()
		return
	eye_color = A.answer ? A.request.value : ""
	open_request(src, /datum/prompt/choice/morph, PROC_REF(hair_picked), answerer = actor, question = "Please select hair style", choices = hairs)

/datum/morph_review/proc/hair_picked(datum/act/request/A)
	run_step(PROC_REF(hair_picked_step), A)

/datum/morph_review/proc/hair_picked_step(datum/act/request/A)
	if(!accept_or_skip(A))
		retire()
		return
	hair = A.answer ? A.request.value : ""
	open_request(src, /datum/prompt/choice/morph, PROC_REF(facial_picked), answerer = actor, question = "Please select facial style", choices = fhairs)

/datum/morph_review/proc/facial_picked(datum/act/request/A)
	run_step(PROC_REF(facial_picked_step), A)

/datum/morph_review/proc/facial_picked_step(datum/act/request/A)
	if(!accept_or_skip(A))
		retire()
		return
	facial = A.answer ? A.request.value : ""
	open_request(src, /datum/prompt/choice/morph, PROC_REF(gender_picked), answerer = actor, question = "Please select gender.", choices = list("Male", "Female", "Neutral"), buttons = TRUE)

/datum/morph_review/proc/gender_picked(datum/act/request/A)
	run_step(PROC_REF(gender_picked_step), A)

/datum/morph_review/proc/gender_picked_step(datum/act/request/A)
	if(accept_or_skip(A))
		actor.morph_answered(facial_color, hair_color, eye_color, hair, facial, A.answer ? A.request.value : "")
	retire()

/mob/living/carbon/human/proc/morph_answered(new_facial, new_hair, new_eyes, new_h_style, new_f_style, new_gender)
	if(new_facial)
		r_facial = hex2num(copytext(new_facial, 2, 4))
		g_facial = hex2num(copytext(new_facial, 4, 6))
		b_facial = hex2num(copytext(new_facial, 6, 8))
	if(new_hair)
		r_hair = hex2num(copytext(new_hair, 2, 4))
		g_hair = hex2num(copytext(new_hair, 4, 6))
		b_hair = hex2num(copytext(new_hair, 6, 8))
	if(new_eyes)
		r_eyes = hex2num(copytext(new_eyes, 2, 4))
		g_eyes = hex2num(copytext(new_eyes, 4, 6))
		b_eyes = hex2num(copytext(new_eyes, 6, 8))
		update_eyes()
	if(new_h_style)
		h_style = new_h_style
	if(new_f_style)
		f_style = new_f_style
	switch(new_gender)
		if("Male")
			gender = MALE
		if("Female")
			gender = FEMALE
		if("Neutral")
			gender = NEUTER
	regenerate_icons()
	check_dna()
	act_message(src, null, MSG_SELF(span_notice("You change your appearance!")), \
		MSG_OTHERS(span_notice("%U% morphs and changes %THEIR% appearance!")), \
		MSG_BLIND(span_filter_notice("[span_red("Oh, god!  What the hell was that?  It sounded like flesh getting squished and bone ground into a different shape!")]")))

/mob/living/carbon/human/proc/remotesay()
	set name = "Project mind"
	set category = VERB_CAT_ABILITIES_SUPERPOWER

	if(stat != CONSCIOUS)
		return

	if(!(src.has_mutation(mRemotetalk)))
		return // the gene's unapply revokes its grant; any other source keeps the verb
	var/list/creatures = list()
	for(var/mob/living/carbon/h in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(h == src) // Don't target self
			continue
		creatures += h
	open_request(src, /datum/prompt/choice/remotesay_target, PROC_REF(remotesay_target_chosen), answerer = src, choices = creatures)

/// Re-checked on the answer: conscious and still telepathic.
/datum/prompt/choice/remotesay_target
	title = "Project Mind"
	question = "Who do you want to project your mind to?"
	timeout = 0
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/remotesay_target/recheck_extra()
	if(!answerer.has_mutation(mRemotetalk))
		return "not telepathic"
	if(!isnull(value))
		var/mob/selected = value
		if(!istype(selected) || QDELETED(selected))
			return "gone"

/// Captures the original recipient weakly while the speaker writes the message.
/datum/prompt/text/remotesay
	question = "What do you wish to say?"
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/mob/recipient
	var/recipient_expected = FALSE

CAPABILITIES(/datum/prompt/text/remotesay)
	ref_one(nameof(recipient), /mob)

/datum/prompt/text/remotesay/prepare(datum/act/A)
	. = ..()
	var/mob/captured_recipient = recipient
	recipient_expected = !isnull(captured_recipient)
	rel_clear(src, nameof(recipient))
	if(captured_recipient && !QDELETED(captured_recipient))
		rel_set(src, nameof(recipient), captured_recipient)

/datum/prompt/text/remotesay/recheck_extra()
	if(!answerer.has_mutation(mRemotetalk))
		return "not telepathic"
	if(recipient_expected && QDELETED(recipient))
		return "gone"

/mob/living/carbon/human/proc/remotesay_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return remotesay_target_apply(A)

/mob/living/carbon/human/proc/remotesay_target_apply(datum/act/request/A)
	var/mob/recipient = A.answer.value
	open_request(src, /datum/prompt/text/remotesay, PROC_REF(remotesay_answered), answerer = src, recipient = recipient)

/mob/living/carbon/human/proc/remotesay_answered(datum/act/request/A)
	if(!A.answer)
		return
	return remotesay_apply(A)

/mob/living/carbon/human/proc/remotesay_apply(datum/act/request/A)
	var/datum/prompt/text/remotesay/ask = A.answer
	var/mob/target = ask.recipient
	var/say = ask.value
	if(target.has_mutation(mRemotetalk))
		target.show_message(span_filter_say("[span_blue("You hear [src.real_name]'s voice: [say]")]"))
	else
		target.show_message(span_filter_say("[span_blue("You hear a voice that seems to echo around the room: [say]")]"))
	src.show_message(span_filter_say("[span_blue("You project your mind into [target.real_name]: [say]")]"))
	log_talk("(TPATH to [key_name(target)]) [say]", LOG_SAY)
	for(var/mob/observer/dead/G in REGISTRY_MEMBERS(REGISTRY_MOBS))
		G.show_message(span_filter_say(span_italics("Telepathic message from " + span_bold("[src]") + " to " + span_bold("[target]") + ": [say]")))

/mob/living/carbon/human/proc/remoteobserve()
	set name = "Remote View"
	set category = VERB_CAT_ABILITIES_SUPERPOWER

	if(stat != CONSCIOUS)
		return

	if(is_remote_viewing())
		reset_perspective()
		return

	var/list/mob/creatures = list()

	var/turf/current = get_turf(src) // Needs to be on station or same z to perform telepathy
	for(var/mob/living/carbon/h in REGISTRY_MEMBERS(REGISTRY_MOBS))
		var/turf/temp_turf = get_turf(h)
		if(!istype(temp_turf,/turf/)) // Nullcheck fix
			continue
		if(h == src) // Traitgenes edit - Don't target self
			continue
		if(!((temp_turf.z in using_map.station_levels) || current.z == temp_turf.z) || h.stat!=CONSCIOUS) // Needs to be on station or same z to perform telepathy
			continue
		creatures += h

	open_request(src, /datum/prompt/choice/remoteobserve, PROC_REF(remoteobserve_chosen), answerer = src, choices = creatures)

/// Re-checked on the answer: both conscious, and not already viewing.
/datum/prompt/choice/remoteobserve
	question = "Who do you want to project your mind to?"
	timeout = 0
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/remoteobserve/recheck_extra()
	if(isnull(value))
		return
	var/mob/target = value
	if(!istype(target) || QDELETED(target))
		return "gone"
	if(target.stat != CONSCIOUS || answerer.is_remote_viewing())
		return "can't view"

/mob/living/carbon/human/proc/remoteobserve_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return remoteobserve_apply(A)

/mob/living/carbon/human/proc/remoteobserve_apply(datum/act/request/A)
	var/mob/target = A.answer.value
	begin_remote_view(/datum/remote_view/mremote_mutation, target)

/mob/living/carbon/human/get_visible_gender(mob/user, force)
	switch(force)
		if(VISIBLE_GENDER_FORCE_PLURAL)
			return PLURAL
		if(VISIBLE_GENDER_FORCE_IDENTIFYING)
			return get_gender()
		if(VISIBLE_GENDER_FORCE_BIOLOGICAL)
			return gender
		else
			if(((get_equipped_item(SLOT_ID_MASK)?.flags_inv & HIDEFACE) || (get_equipped_item(SLOT_ID_HEAD)?.flags_inv & HIDEMASK) || (get_equipped_item(SLOT_ID_HEAD)?.flags_inv & HIDEFACE)) && (get_equipped_item(SLOT_ID_SUIT)?.flags_inv & HIDEJUMPSUIT))
				return PLURAL
			if(species?.ambiguous_genders && user)
				if(ishuman(user))
					var/mob/living/carbon/human/human = user
					if(!istype(human.species, species))
						return PLURAL
				else if(!isobserver(user) && !issilicon(user))
					return PLURAL
			return get_gender()

/mob/living/carbon/human/proc/increase_germ_level(n)
	if(get_equipped_item(SLOT_ID_GLOVES))
		get_equipped_item(SLOT_ID_GLOVES).germ_level += n
	else
		germ_level += n

/mob/living/carbon/human/revive()

	if(should_have_organ(O_HEART))
		vessel.add_reagent(REAGENT_ID_BLOOD,species.blood_volume-vessel.total_volume)
		fixblood()

	species.create_organs(src) // Reset our organs/limbs.
	restore_all_organs()       // Reapply robotics/amputated status from preferences.

	if(!client || !key) //Don't boot out anyone already in the mob.
		// A loose brain that hosts this body's character goes home.
		for (var/obj/item/organ/internal/brain/H in REGISTRY_MEMBERS(REGISTRY_BRAIN_ORGANS))
			var/datum/mind_host/host = get_mind_host(H)
			var/datum/mind/brain_mind = host?.hosted_mind()
			if(brain_mind && brain_mind.get_identity() == identity())
				host.release_mind(src, "revived body reclaimed its brain")
				ended_with(H, src)
				break

	// Traitgenes Disable all traits currently active, before prefs.copy_to() is applied, as it refreshes the traits list!
	for(var/datum/gene/trait/gene in GLOB.dna_genes)
		if(gene.name in active_genes)
			gene.deactivate(src)
			LAZYREMOVE(active_genes, gene.name)

	// Reapply markings/appearance from prefs for player mobs
	if(client) //just to be sure
		client.prefs.copy_to(src)
		if(dna)
			dna.ResetUIFrom(src)
			sync_dna_traits(TRUE) // Traitgenes Sync traits to genetics if needed
			sync_organ_dna()
	initialize_vessel()

	losebreath = 0

	..()

/mob/living/carbon/human/proc/is_lung_ruptured()
	var/obj/item/organ/internal/lungs/L = organ_in(O_LUNGS)
	return L && L.is_bruised()

/mob/living/carbon/human/proc/rupture_lung(gradual)
	var/obj/item/organ/internal/lungs/L = organ_in(O_LUNGS)

	if(L)
		if(gradual && (L.damage < (L.min_bruised_damage-1))) //We do slow ticking damage up to 9. After 9, we rupture completely.
			injure(INJURY_PIERCE, 1, L, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
		else
			L.rupture()

/*
/mob/living/carbon/human/verb/simulate()
	set name = "sim"
	set background = 1

	var/damage = tgui_input_number(src, "Wound damage","Wound damage")

	var/germs = 0
	var/tdamage = 0
	var/ticks = 0
	while (germs < 2501 && ticks < 100000 && round(damage/10)*20)
		log_misc("VIRUS TESTING: [ticks] : germs [germs] tdamage [tdamage] prob [round(damage/10)*20]")
		ticks++
		if (prob(round(damage/10)*20))
			germs++
		if (germs == 100)
			to_world("Reached stage 1 in [ticks] ticks")
		if (germs > 100)
			if (prob(10))
				damage++
				germs++
		if (germs == 1000)
			to_world("Reached stage 2 in [ticks] ticks")
		if (germs > 1000)
			damage++
			germs++
		if (germs == 2500)
			to_world("Reached stage 3 in [ticks] ticks")
	to_world("Mob took [tdamage] tox damage")
*/
//returns 1 if made bloody, returns 0 otherwise

/mob/living/carbon/human/add_blood(mob/living/carbon/human/M as mob)
	if (!..())
		return 0
	//if this blood isn't already in the list, add it
	if(istype(M))
		add_blooddna(M.dna,M)
	hand_blood_color = dq_get_blood_color(src)
	update_bloodied()
	grant(src, granted_verb(/mob/living/carbon/human/proc/bloody_doodle), src)
	return 1 //we applied blood to the item

/mob/living/carbon/human/proc/get_full_print()
	if(!dna || !dna.dna_ready)
		return
	return md5(dna.GetUniIdentity())

/mob/living/carbon/human/wash(clean_types)
	. = ..()

	LAZYCLEARLIST(body_writing)

	//Always do hands (or whatever's on our hands)
	if(get_equipped_item(SLOT_ID_GLOVES))
		get_equipped_item(SLOT_ID_GLOVES).wash(clean_types)
		update_inv_gloves()
		get_equipped_item(SLOT_ID_GLOVES).germ_level = 0
	else
		bloody_hands = 0
		germ_level = 0

	if(get_equipped_item(SLOT_ID_SHOES))
		get_equipped_item(SLOT_ID_SHOES).wash(clean_types)
		update_inv_shoes()
		get_equipped_item(SLOT_ID_SHOES).germ_level = 0
	else if(feet_blood_color || LAZYLEN(feet_blood_DNA))
		LAZYCLEARLIST(feet_blood_DNA)
		feet_blood_DNA = null
		feet_blood_color = null

	update_bloodied()

/mob/living/carbon/human/get_visible_implants(class = 0)

	var/list/visible_implants = list()
	for(var/obj/item/organ/external/organ in src.organs)
		for(var/obj/item/O in organ.implants)
			if(!istype(O,/obj/item/implant) && (O.w_class > class) && !istype(O,/obj/item/material/shard/shrapnel) && !istype(O,/obj/item/nif))
				visible_implants += O

	return(visible_implants)

/mob/living/carbon/human/embedded_needs_process()
	for(var/obj/item/organ/external/organ in src.organs)
		for(var/obj/item/O in organ.implants)
			if(!istype(O, /obj/item/implant)) //implant type items do not cause embedding effects, see handle_embedded_objects()
				return 1
	return 0

/mob/living/carbon/human/proc/handle_embedded_objects()

	for(var/obj/item/organ/external/organ in src.organs)
		if(organ.splinted) //Splints prevent movement.
			continue
		for(var/obj/item/O in organ.implants)
			if(!istype(O,/obj/item/implant) && prob(5)) //Moving with things stuck in you could be bad.
				// All kinds of embedded objects cause bleeding.
				if(!can_feel_pain(organ.organ_tag))
					to_chat(src, span_warning("You feel [O] moving inside your [organ.name]."))
				else
					var/msg = pick( \
						span_warning("A spike of pain jolts your [organ.name] as you bump [O] inside."), \
						span_warning("Your movement jostles [O] in your [organ.name] painfully."), \
						span_warning("Your movement jostles [O] in your [organ.name] painfully."))
					custom_pain(msg, 40)

				injure(INJURY_CUT, rand(1,3), organ.organ_tag, O)
				if(!(organ.is_robotic()) && (should_have_organ(O_HEART))) //There is no blood in protheses.
					organ.set_status(organ.status | ORGAN_BLEEDING)

MSG_DEF_SELF(human/no_pulse, span_danger("%T% has no pulse!"))

/// Counting a pulse: the target has one to count, and who counts is told that both must stay still.
/mob/living/carbon/human/proc/check_pulse_started(datum/act/op/A)
	var/mob/user = A.actor
	var/self = (user == src)
	if(!pulse)
		return MSG(human/no_pulse)
	to_chat(user, span_notice("[self ? "You have a" : "[src] has a"] pulse! Counting..."))
	to_chat(user, span_filter_notice("You must[self ? "" : " both"] remain still until counting is finished."))

/mob/living/carbon/human/proc/check_pulse_begins(datum/act/op/A)
	if(A.actor == src)
		return msg_text(span_filter_notice("You begin counting your pulse."), span_notice("%U% begins counting %THEIR% pulse."))
	return msg_text(span_filter_notice("You begin counting %T%'s pulse."), span_notice("%U% kneels down, puts %THEIR% hand on %T%'s wrist and begins counting %THEIR% pulse."))

/mob/living/carbon/human/proc/check_pulse_human_done(datum/act/op/A)
	var/mob/usr_mob = A.actor
	var/self = (usr_mob == src)
	var/message = span_notice("[self ? "Your" : "[src]'s"] pulse is [src.get_pulse(GETPULSE_HAND)].")
	to_chat(usr_mob,message)

/mob/living/carbon/human/proc/check_pulse_human_failed(datum/act/op/A)
	var/mob/usr_mob = A.actor
	to_chat(usr_mob, span_warning("You failed to check the pulse. Try again."))

/// `keep_organs`: change the species' facts (languages, verbs, components, factors, HUD) but
/// keep the body and organs it has, e.g. a nymph taking over a synthetic body (D21).
/mob/living/carbon/human/proc/set_species(new_species, keep_organs = FALSE)

	if(!dna)
		if(!new_species)
			new_species = SPECIES_HUMAN
	else
		if(!new_species)
			new_species = dna.species
		else
			dna.species = new_species

	// No more invisible screaming wheelchairs because of set_species() typos.
	if(!GLOB.all_species[new_species])
		new_species = SPECIES_HUMAN

	var/datum/species/old_species = species
	if(species)

		if(species.name && species.name == new_species && species.name != "Custom Species")
			return
		// A protean folded into its control cluster unfolds before its swarm goes away.
		var/datum/forms/protean/protean_forms = get_protean_forms()
		if(protean_forms?.in_rig())
			protean_forms.leave_rig()
			log_game("SPECIES: [key_name(src)] unfolded from their control cluster for a species change to [new_species].")
		if(species.language)
			remove_language(species.language)
		if(species.default_language)
			remove_language(species.default_language)
		for(var/datum/language/L in species.assisted_langs)
			remove_language(L)
		// Clear out their species abilities.
		species.remove_inherent_verbs(src)
		holder_type = null
		hunger_rate = initial(hunger_rate)

	var/datum/species/replaced = proto_replace(src, nameof(species), GLOB.all_species[new_species])
	changed(src, CHANGE_MOB_CONDITIONS) // species vision and senses
	PUBLISH_CHANGE(src, MOB_KEY_CONDITIONS)
	old_species?.remove_components(src, species)
	if(replaced)
		replaced_by(replaced) // the private copy proto_replace() handed back, done with now
	invalidate_factors()

	if(species.language)
		add_language(species.language)

	if(species.default_language)
		add_language(species.default_language)

	if(species.icon_scale_x != DEFAULT_ICON_SCALE_X || species.icon_scale_y != DEFAULT_ICON_SCALE_Y)
		update_transform()

	if(species.base_color)
		//Apply color.
		r_skin = hex2num(copytext(species.base_color,2,4))
		g_skin = hex2num(copytext(species.base_color,4,6))
		b_skin = hex2num(copytext(species.base_color,6,8))
	else
		r_skin = 0
		g_skin = 0
		b_skin = 0

	if(species.holder_type)
		holder_type = species.holder_type

	if(!(gender in species.genders))
		gender = species.genders[1]

	// Swap the body plan before the organs are built so they attach to the new body.
	// On the first set_species() (before /mob/living/Initialize()) the body is
	// built here: organs attach into the plan's part slots as they are made.
	if(!keep_organs)
		body_type = species.body_plan
	if(!body)
		rel_set(src, nameof(body), new body_type(src))
	else if(!keep_organs && body.type != body_type)
		log_game("BODY: [key_name(src)] body plan [body.type] -> [body_type] on species change to [species.name].")
		rel_clear(src, nameof(body))
		rel_set(src, nameof(body), new body_type(src))
		// The slot set is keyed by body plan.
		rebuild_slot_ledger()
		// So is the Life plan (physiology applies by body plan).
		recompose_life()

	species.handle_post_spawn(src)

	if(!keep_organs)
		species.create_organs(src)

	species.apply_components(src)

	endurance = species.total_health
	hunger_rate = species.hunger_factor

	default_pixel_x = initial(pixel_x) + species.pixel_offset_x //For giving datum/species ways to change 64x64 sprite offsets
	default_pixel_y = initial(pixel_y) + species.pixel_offset_y
	pixel_x = default_pixel_x
	pixel_y = default_pixel_y
	center_offset = species.center_offset

	if(vessel && !keep_organs)
		initialize_vessel()
	if(keep_organs)
		body?.invalidate(BODY_DIRTY_ALL) // the same organs now answer to a new species

	// Rebuild the HUD. If they aren't logged in then login() should reinstantiate it for them.
	update_hud()

	//A slew of bits that may be affected by our species change
	regenerate_icons()

	if(species)
		return 1
	else
		return 0

/mob/living/carbon/human/proc/initialize_vessel() //This needs fixing. For some reason mob species is not immediately set in set_species.
	SHOULD_NOT_OVERRIDE(TRUE)
	make_blood()
	if(vessel.total_volume < species.blood_volume)
		vessel.maximum_volume = species.blood_volume
		vessel.add_reagent(REAGENT_ID_BLOOD, species.blood_volume - vessel.total_volume)
	else if(vessel.total_volume > species.blood_volume)
		vessel.remove_reagent(REAGENT_ID_BLOOD,vessel.total_volume - species.blood_volume) //This one should stay remove_reagent to work even lack of a O_heart
		vessel.maximum_volume = species.blood_volume
	fixblood()
	// Traits (only ever on the mob's private copy) may change unarmed_types; a registered species
	// built its attacks in New() and is never written here.
	if(rel_is_private(src, nameof(species)))
		species.update_attack_types()
	species.update_vore_belly_def_variant()

/mob/living/carbon/human/proc/bloody_doodle()
	set category = VERB_CAT_IC_GAME
	set name = "Write in blood"
	set desc = "Use blood on your hands to write a short message on the floor or a wall, murder mystery style."

	if (src.stat)
		return

	if (usr != src)
		return 0 //something is terribly wrong

	if (!bloody_hands)
		revoke(src, granted_verb(/mob/living/carbon/human/proc/bloody_doodle), src)

	if (get_equipped_item(SLOT_ID_GLOVES))
		to_chat(src, span_warning("Your [get_equipped_item(SLOT_ID_GLOVES)] are getting in the way."))
		return

	var/turf/simulated/T = src.loc
	if (!istype(T)) //to prevent doodling out of mechs and lockers
		to_chat(src, span_warning("You cannot reach the floor."))
		return

	open_request(src, /datum/prompt/choice, PROC_REF(bloody_doodle_direction_chosen), answerer = src, title = "Tile selection", question = "Which way?", choices = list("Here","North","South","East","West"), ask_flags = ASK_CONSCIOUS, timeout = 0)

/// The blood writing's message; carries the direction picked.
/datum/prompt/text/bloody_doodle
	title = "Blood writing"
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/direction

/// The tile `direction` of us to write on, or null (with a message) if we can't.
/mob/living/carbon/human/proc/bloody_doodle_turf(direction)
	var/turf/simulated/T = loc
	if (!istype(T) || get_equipped_item(SLOT_ID_GLOVES) || !bloody_hands)
		to_chat(src, span_warning("You cannot reach the floor."))
		return null
	if (direction != "Here")
		T = get_step(T,text2dir(direction))
	if (!istype(T))
		to_chat(src, span_warning("You cannot doodle there."))
		return null
	var/num_doodles = 0
	for (var/obj/effect/decal/cleanable/blood/writing/W in turf_contents_of_type(T, /obj/effect/decal/cleanable/blood/writing))
		num_doodles++
	if (num_doodles > 4)
		to_chat(src, span_warning("There is no space to write on!"))
		return null
	return T

/mob/living/carbon/human/proc/bloody_doodle_direction_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/direction = A.answer.value
	if(!bloody_doodle_turf(direction))
		return
	var/max_length = bloody_hands * 30 //tweeter style
	open_request(src, /datum/prompt/text/bloody_doodle, PROC_REF(bloody_doodle_written), answerer = src, question = "Write a message. It cannot be longer than [max_length] characters.", direction = direction)

/mob/living/carbon/human/proc/bloody_doodle_written(datum/act/request/A)
	if(!A.answer)
		return
	return bloody_doodle_apply(A)

/mob/living/carbon/human/proc/bloody_doodle_apply(datum/act/request/A)
	var/datum/prompt/text/bloody_doodle/ask = A.answer
	var/message = ask.value
	var/turf/simulated/T = bloody_doodle_turf(ask.direction)
	if(!T)
		return
	var/max_length = bloody_hands * 30
	if (message)
		var/used_blood_amount = round(length(message) / 30, 1)
		bloody_hands = max(0, bloody_hands - used_blood_amount) //use up some blood

		if (length(message) > max_length)
			message += "-"
			to_chat(src, span_warning("You ran out of blood to write with!"))

		var/obj/effect/decal/cleanable/blood/writing/W = new(T)
		W.set_basecolor((hand_blood_color) ? hand_blood_color : "#A10808")
		W.message = message
		W.add_fingerprint(src)

/// A species with a thick hide turns a needle away at times (a roll, by how hurt the limb is): TRUE when it does this time.
/mob/living/carbon/human/proc/thick_skin_holds(obj/item/organ/external/affecting)
	return (species.flags & THICK_SKIN) && prob(70 - round(affecting.get_trauma() + affecting.get_burn() / 2))

/// `roll` = FALSE leaves out the thick-hide roll of some species (the one who asks makes it later, with thick_skin_holds()).
/mob/living/carbon/human/can_inject(mob/user, error_msg, target_zone, ignore_thickness = FALSE, method = INJECT_METHOD_NEEDLE, roll = TRUE)
	. = 1

	if(!target_zone)
		if(!user)
			target_zone = pick(BP_TORSO,BP_TORSO,BP_TORSO,BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_HEAD)
		else
			target_zone = user.zone_sel.selecting

	var/obj/item/organ/external/affecting = get_organ(target_zone)
	var/fail_msg
	if(!affecting)
		. = 0
		fail_msg = "They are missing that limb."
	else if (affecting.robotic == ORGAN_ROBOT && method == INJECT_METHOD_NEEDLE)
		. = 0
		fail_msg = "That limb is robotic."
	else if (affecting.robotic >= ORGAN_LIFELIKE && method == INJECT_METHOD_NEEDLE)
		. = 0
		fail_msg = "Your needle refuses to penetrate more than a short distance..."
	else if(roll && thick_skin_holds(affecting))	// Allows transplanted limbs with thick skin to maintain their resistance.
		. = 0
		fail_msg = "Your needle fails to penetrate \the [affecting]'s thick hide..."
	else
		switch(target_zone)
			if(BP_HEAD)
				if(get_equipped_item(SLOT_ID_HEAD) && (get_equipped_item(SLOT_ID_HEAD).item_flags & THICKMATERIAL) && !ignore_thickness)
					. = 0
			else
				if(get_equipped_item(SLOT_ID_SUIT) && (get_equipped_item(SLOT_ID_SUIT).item_flags & THICKMATERIAL) && !ignore_thickness)
					. = 0
	if(!. && error_msg && user)
		if(!fail_msg)
			fail_msg = "There is no exposed flesh or thin material [target_zone == BP_HEAD ? "on their head" : "on their body"] to inject into."
		to_chat(user, span_warning("[fail_msg]"))

/mob/living/carbon/human/print_flavor_text(shrink = 1)
	var/list/equipment = list(get_equipped_item(SLOT_ID_HEAD),get_equipped_item(SLOT_ID_MASK),get_equipped_item(SLOT_ID_EYES),get_equipped_item(SLOT_ID_UNIFORM),get_equipped_item(SLOT_ID_SUIT),get_equipped_item(SLOT_ID_GLOVES),get_equipped_item(SLOT_ID_SHOES))
	var/head_exposed = 1
	var/face_exposed = 1
	var/eyes_exposed = 1
	var/torso_exposed = 1
	var/arms_exposed = 1
	var/legs_exposed = 1
	var/hands_exposed = 1
	var/feet_exposed = 1

	for(var/obj/item/clothing/C in equipment)
		if(C.body_parts_covered & HEAD)
			head_exposed = 0
		if(C.body_parts_covered & FACE)
			face_exposed = 0
		if(C.body_parts_covered & EYES)
			eyes_exposed = 0
		if(C.body_parts_covered & UPPER_TORSO)
			torso_exposed = 0
		if(C.body_parts_covered & ARMS)
			arms_exposed = 0
		if(C.body_parts_covered & HANDS)
			hands_exposed = 0
		if(C.body_parts_covered & LEGS)
			legs_exposed = 0
		if(C.body_parts_covered & FEET)
			feet_exposed = 0

	flavor_text = ""
	for (var/T in flavor_texts)
		if(flavor_texts[T] && flavor_texts[T] != "")
			if((T == "general") || (T == "head" && head_exposed) || (T == "face" && face_exposed) || (T == "eyes" && eyes_exposed) || (T == "torso" && torso_exposed) || (T == "arms" && arms_exposed) || (T == "hands" && hands_exposed) || (T == "legs" && legs_exposed) || (T == "feet" && feet_exposed))
				flavor_text += flavor_texts[T]
				flavor_text += "\n\n"
	if(!shrink)
		return flavor_text
	else
		return ..()

/mob/living/carbon/human/has_brain()
	if(organ_in(O_BRAIN))
		var/obj/item/organ/brain = organ_in(O_BRAIN)
		if(brain && istype(brain))
			return 1
	return 0

/// Brain death, decided by the brain organ (is_brain_dead()): a resleeve is
/// required. A missing brain is not brain death (the brain may be put back).
/mob/living/carbon/human/is_brain_dead()
	if(!should_have_organ(O_BRAIN))
		return FALSE
	var/obj/item/organ/internal/brain/B = organ_in(O_BRAIN)
	return istype(B) && B.is_brain_dead()

/mob/living/carbon/human/has_eyes()
	if(organ_in(O_EYES))
		var/obj/item/organ/eyes = organ_in(O_EYES)
		if(eyes && istype(eyes) && !(eyes.status & ORGAN_CUT_AWAY))
			return 1
	return 0

/mob/living/carbon/human/has_lungs()
	if(organ_in(O_LUNGS))
		var/obj/item/organ/lungs = organ_in(O_LUNGS)
		if(lungs && istype(lungs) && !(lungs.status & ORGAN_CUT_AWAY))
			return TRUE
	return FALSE

/mob/living/carbon/human/slip(slipped_on, stun_duration=8)
	var/list/equipment = list(get_equipped_item(SLOT_ID_UNIFORM),get_equipped_item(SLOT_ID_SUIT),get_equipped_item(SLOT_ID_SHOES))
	var/footcoverage_check = FALSE
	for(var/obj/item/clothing/C in equipment)
		if(C.body_parts_covered & FEET)
			footcoverage_check = TRUE
			break
	if(lying)
		play_sfx(src, SFX_MISC_SLIP)
		drop_both_hands()
		return FALSE
	if((species.flags & NO_SLIP && !footcoverage_check) || (get_equipped_item(SLOT_ID_SHOES) && (get_equipped_item(SLOT_ID_SHOES).item_flags & NOSLIP))) //Footwear negates a species' natural traction.
		return FALSE
	if(..(slipped_on,stun_duration))
		drop_both_hands()
		return TRUE

/mob/living/carbon/human/proc/relocate()
	set category = VERB_CAT_OBJECT
	set name = "Relocate Joint"
	set desc = "Pop a joint back into place. Extremely painful."
	set src in view(1)

	if(!isliving(usr) || !usr.checkClickCooldown())
		return

	usr.setClickCooldown(20)

	if(usr.stat > 0)
		to_chat(usr, span_filter_notice("You are unconcious and cannot do that!"))
		return

	if(usr.restrained())
		to_chat(usr, span_filter_notice("You are restrained and cannot do that!"))
		return

	var/list/limbs = list()
	for(var/limb in organs_by_name)
		var/obj/item/organ/external/current_limb = organs_by_name[limb]
		if(current_limb && current_limb.dislocated > 0 && !current_limb.is_parent_dislocated()) //if the parent is also dislocated you will have to relocate that first
			limbs |= current_limb
	open_request(src, /datum/prompt/choice/relocate_joint, PROC_REF(relocate_joint_chosen), answerer = usr, choices = limbs)
	return TRUE

/// Picking a joint on the subject. Re-checked on the answer: next to them, unrestrained, awake,
/// and the limb is still theirs and still dislocated.
/datum/prompt/choice/relocate_joint
	title = "Joint Choice"
	question = "Which joint do you wish to relocate?"
	timeout = 0
	ask_flags = ASK_ADJACENT | ASK_RESTRAINED | ASK_CONSCIOUS

/datum/prompt/choice/relocate_joint/recheck_extra()
	if(isnull(value))
		return
	var/obj/item/organ/external/limb = value
	if(!istype(limb) || QDELETED(limb))
		return "gone"
	if(limb.owner != owner || limb.dislocated <= 0)
		return "not dislocated"
	return null

/mob/living/carbon/human/proc/relocate_joint_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return relocate_joint_apply(A)

/mob/living/carbon/human/proc/relocate_joint_apply(datum/act/request/A)
	var/datum/prompt/choice/relocate_joint/ask = A.answer
	var/mob/U = ask.answerer
	var/obj/item/organ/external/current_limb = ask.value
	var/mob/S = src
	var/self = (U == src)
	if(self)
		to_chat(src, span_warning("You brace yourself to relocate your [current_limb.joint]..."))
	else
		to_chat(U, span_warning("You begin to relocate [S]'s [current_limb.joint]..."))

	perform_op(U, src, "relocate_joint", null, ORIGIN_SYSTEM, AUTH_PHYSICAL, with = list("limb" = current_limb))
	return TRUE

/mob/living/carbon/human/proc/relocate_human_done(datum/act/op/A)
	var/mob/S = src
	var/mob/U = A.actor
	var/self = (U == src)
	var/obj/item/organ/external/current_limb = A.arg("limb")
	if(!current_limb || !S || !U)
		return OP_OK

	if(self)
		to_chat(src, span_danger("You pop your [current_limb.joint] back in!"))
	else
		to_chat(U, span_danger("You pop [S]'s [current_limb.joint] back in!"))
		to_chat(S, span_danger("[U] pops your [current_limb.joint] back in!"))
	current_limb.relocate()
	return OP_OK

/mob/living/carbon/human/drop_from_inventory(obj/item/W, atom/target = null)
	if(W in organs)
		return FALSE
	if(isnull(target) && isdisposalpacket(src.loc))
		return remove_from_mob(W, src.loc)
	return ..()

/mob/living/carbon/human/Check_Shoegrip()
	if(get_equipped_item(SLOT_ID_SHOES) && (get_equipped_item(SLOT_ID_SHOES).item_flags & NOSLIP) && istype(get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes/magboots))  //magboots + dense_object = no floating
		return 1
	if(flying) // Checks to see if they have wings and are flying.
		return 1
	return 0

//Puts the item into our active hand if possible. returns 1 on success.
/mob/living/carbon/human/put_in_active_hand(obj/item/W)
	return (hand ? put_in_l_hand(W) : put_in_r_hand(W))

//Puts the item into our inactive hand if possible. returns 1 on success.
/mob/living/carbon/human/put_in_inactive_hand(obj/item/W)
	return (hand ? put_in_r_hand(W) : put_in_l_hand(W))

/mob/living/carbon/human/put_in_hands(obj/item/W)
	if(!W)
		return 0
	if(is_in_hands(W))
		return 1
	if(put_in_active_hand(W))
		update_inv_l_hand()
		update_inv_r_hand()
		return 1
	else if(put_in_inactive_hand(W))
		update_inv_l_hand()
		update_inv_r_hand()
		return 1
	else
		return ..()

/mob/living/carbon/human/can_stand_overridden()
	if(wearing_rig && wearing_rig.ai_can_move_suit(check_for_ai = 1))
		// Actually missing a leg will screw you up. Everything else can be compensated for.
		for(var/limbcheck in list(BP_L_LEG,BP_R_LEG))
			var/obj/item/organ/affecting = get_organ(limbcheck)
			if(!affecting)
				return 0
		return 1
	return 0

/mob/living/carbon/human/verb/toggle_underwear()
	set name = "Toggle Underwear"
	set desc = "Shows/hides selected parts of your underwear."
	set category = VERB_CAT_OBJECT

	if(stat) return
	open_request(src, /datum/prompt/choice, PROC_REF(toggle_underwear_chosen), answerer = src, title = "Show/hide underwear", question = "Choose underwear:", choices = GLOB.global_underwear.categories, ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/toggle_underwear_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/category_group/underwear/UWC = A.answer.value
	var/datum/category_item/underwear/UWI = LAZYACCESS(all_underwear, UWC.name)
	if(!UWI || UWI.name == "None")
		to_chat(src, span_notice("You do not have [UWC.gender==PLURAL ? "[UWC.display_name]" : "a [UWC.display_name]"]."))
		return
	hide_underwear[UWC.name] = !hide_underwear[UWC.name]
	update_underwear(1)
	to_chat(src, span_notice("You [hide_underwear[UWC.name] ? "take off" : "put on"] your [UWC.display_name]."))

/mob/living/carbon/human/verb/pull_punches()
	set name = "Pull Punches"
	set desc = "Try not to hurt them."
	set category = VERB_CAT_IC_GAME

	if(stat) return
	var/pulling = FALSE
	if(has_trait_from(src, TRAIT_NONLETHAL_BLOWS, ACTION_TRAIT))
		remove_trait(src, TRAIT_NONLETHAL_BLOWS, ACTION_TRAIT)
	else
		add_trait(src, TRAIT_NONLETHAL_BLOWS, ACTION_TRAIT)
		pulling = TRUE
	to_chat(src, span_notice("You are now [pulling ? "pulling your punches" : "not pulling your punches"]."))
	return

/mob/living/carbon/human/should_have_organ(organ_check)

	var/obj/item/organ/external/affecting
	if(organ_check in list(O_HEART, O_LUNGS))
		affecting = organs_by_name[BP_TORSO]
	else if(organ_check in list(O_LIVER, O_KIDNEYS))
		affecting = organs_by_name[BP_GROIN]

	if(affecting && (affecting.is_robotic()))
		return 0
	return (species && species.has_organ[organ_check])

/// Checks our organs and sees if we are missing anything vital, or if it is too heavily damaged
/// Returns two values:
/// FALSE if all our vital organs are intact
/// Or the name of the organ if we are missing a vital organ / it is damaged beyond repair.
/mob/living/carbon/human/proc/check_vital_organs()
	for(var/organ_tag in species.has_organ)
		var/obj/item/organ/O = species.has_organ[organ_tag]
		var/name = initial(O.name)
		var/vital = initial(O.vital) //check for vital organs
		if(vital)
			O = organ_in(organ_tag)
			if(!O)
				return name
			if(istype(O, /obj/item/organ/internal/brain))
				var/obj/item/organ/internal/brain/B = O
				if(B.is_brain_dead())
					return name
			else if(O.damage >= O.max_damage)
				return name
	return FALSE

/mob/living/carbon/human/can_feel_pain(obj/item/organ/check_organ)
	if(HAS_SYNTHETIC_BIOLOGY(src))
		return 0
	if(loc?.numbs_pain_of(src))
		return FALSE
	if(factor(BF_PAIN_IMMUNITY))
		return 0
	if(check_organ)
		if(!istype(check_organ))
			return 0
		return check_organ.organ_can_feel_pain()
	// NO_PAIN reaches here as BF_PAIN_IMMUNITY (species grant, humanoid factors).
	return !(species?.flags & NO_PAIN)

/mob/living/carbon/human/is_sentient()
	if(get_FBP_type() == FBP_DRONE)
		return FALSE
	return ..()

/mob/living/carbon/human/is_muzzled()
	return (get_equipped_item(SLOT_ID_MASK) && (istype(get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/muzzle) || istype(get_equipped_item(SLOT_ID_MASK), /obj/item/grenade)))

/mob/living/carbon/human/get_fire_icon_state()
	return species.fire_icon_state

// Called by job_controller.  Makes drones start with a permit, might be useful for other people later too.
/mob/living/carbon/human/equip_post_job()
	var/braintype = get_FBP_type()
	if(braintype == FBP_DRONE)
		var/turf/T = get_turf(src)
		var/obj/item/clothing/accessory/permit/drone/permit = new(T)
		permit.set_name(real_name)
		equip_to_appropriate_slot(permit) // If for some reason it can't find room, it'll still be on the floor.

/mob/living/carbon/human/proc/update_icon_special() //For things such as teshari hiding and whatnot.
	if(status_flags & HIDING) // Hiding? Carry on.
		if(stat == DEAD || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || restrained() || src?.buckled_to() || LAZYLEN(src?.grabbed_by_list()) || has_buckled_mobs()) //stunned/knocked down by something that isn't the rest verb? Note: This was tried with INCAPACITATION_STUNNED, but that refused to work. //VORE EDIT: Check for has_buckled_mobs() (taur riding)
			reveal(null)
		else
			layer = HIDING_LAYER

/mob/living/carbon/human/examine_icon()
	var/icon/I = get_cached_examine_icon(src)
	if(!I)
		I = getFlatIcon(src, defdir = SOUTH, no_anim = TRUE, force_south = TRUE)
		set_cached_examine_icon(src, I, 50 SECONDS)
	return I

/mob/living/carbon/human/proc/get_display_species()
	//Shows species in tooltip
	if(src.custom_species)
		return custom_species
	//Beepboops get special text if obviously beepboop
	if(looksSynthetic())
		if(gender == MALE)
			return "Android"
		else if(gender == FEMALE)
			return "Gynoid"
		else
			return "Synthetic"
	//Else species name
	if(species)
		return species.get_examine_name()
	//Else CRITICAL FAILURE!
	return ""

/mob/living/carbon/human/get_nametag_name(mob/user)
	return name //Could do fancy stuff here?

/mob/living/carbon/human/get_nametag_desc(mob/user)
	var/msg = ""
	if(hasHUD(user,"security"))
		//Try to find their name
		var/perpname
		var/obj/item/card/id/I = GetIdCard()
		if(I)
			perpname = I.registered_name
		else
			perpname = name
		//Try to find their record
		var/criminal = "None"
		if(perpname)
			var/datum/data/record/G = find_general_record("name", perpname)
			if(G)
				var/datum/data/record/S = find_security_record("id", G.fields["id"])
				if(S)
					criminal = S.fields["criminal"]
		//If it's interesting, append
		if(criminal != "None")
			msg += "([criminal]) "

	if(hasHUD(user,"medical"))
		msg += "(Health: [round(vitality() * 100)]%) "

	msg += get_display_species()
	return msg

/mob/living/carbon/human/reduce_cuff_time()
	if(istype(get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/gloves/gauntlets/rig))
		return 2
	return ..()

/// Badly hurt: past the old soft-crit line (health <= 0), which is half
/// the body's vitality scale.
/mob/living/carbon/human/proc/is_badly_hurt()
	return vitality() <= 0.5

/mob/living/carbon/human/pull_damage()
	if(is_badly_hurt())
		for(var/name in organs_by_name)
			var/obj/item/organ/external/limb = organs_by_name[name]
			if(!limb)
				continue
			if((limb.is_fractured() && (!limb.splinted || ((is_in_holder(limb.splinted, limb)) && prob(30))) || limb.status & ORGAN_BLEEDING) && (injury_load(INJURY_CATEGORY_PHYSICAL) + injury_load(INJURY_CATEGORY_THERMAL) >= 100))
				return TRUE
	else
		return ..()

/mob/living/carbon/human/pull_can_damage()
	if(is_badly_hurt())
		for(var/name in organs_by_name)
			var/obj/item/organ/external/limb = organs_by_name[name]
			if(!limb)
				continue
			if((limb.is_fractured() || (limb.status & ORGAN_BLEEDING)) && (injury_load(INJURY_CATEGORY_PHYSICAL) + injury_load(INJURY_CATEGORY_THERMAL) >= 100))
				return TRUE
	else
		return ..()

// Drag damage is handled in a parent
/mob/living/carbon/human/dragged(mob/living/dragger, oldloc, trigged_bleeding)
	if(..())
		if(species?.flags & NO_BLOOD)
			return
		var/blood_volume = vessel.get_reagent_amount(REAGENT_ID_BLOOD)
		if(blood_volume < species?.blood_volume*species?.blood_level_fatal)
			return

		remove_blood(1)
		if(istype(loc, /turf/simulated))
			var/turf/simulated/T = loc
			T.add_blood(src)

// Tries to turn off item-based things that let you see through walls, like mesons.
// Certain stuff like genetic xray vision is allowed to be kept on.
/mob/living/carbon/human/disable_spoiler_vision()
	// Glasses.
	if(istype(get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses))
		var/obj/item/clothing/glasses/goggles = get_equipped_item(SLOT_ID_EYES)
		if(goggles.active && (goggles.vision_flags & (SEE_TURFS|SEE_OBJS)))
			goggles.toggle_active(src)
			to_chat(src, span_warning("Your [goggles.name] have suddenly turned off!"))

	// RIGs.
	var/obj/item/rig/rig = get_rig()
	if(istype(rig) && rig.visor?.active && rig.visor.vision?.glasses)
		var/obj/item/clothing/glasses/rig_goggles = rig.visor.vision.glasses
		if(rig_goggles.vision_flags & (SEE_TURFS|SEE_OBJS))
			rig.visor.deactivate()
			to_chat(src, span_warning("\The [rig]'s visor has shuddenly deactivated!"))

/mob/living/carbon/human/get_mob_riding_slots()
	return list(get_equipped_item(SLOT_ID_BACK), get_equipped_item(SLOT_ID_HEAD), get_equipped_item(SLOT_ID_SUIT))

/mob/living/carbon/human/verb/flip_lying()
	set name = "Flip Resting Direction"
	set category = VERB_CAT_ABILITIES_GENERAL
	set desc = "Switch your horizontal direction while prone."

	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || !COOLDOWN_FINISHED(src, last_special))
		to_chat(src, span_warning("You can't do that in your current state."))
		return

	if(isnull(rest_dir))
		rest_dir = FALSE
	rest_dir = !rest_dir
	update_transform(TRUE)

/mob/living/carbon/human/get_digestion_nutrition_modifier()
	return species.digestion_nutrition_modifier

/mob/living/carbon/human/get_digestion_efficiency_modifier()
	return species.digestion_efficiency

/mob/living/carbon/human/verb/hide_headset()
	set name = "Show/Hide Headset"
	set category = VERB_CAT_IC_SETTINGS
	set desc = "Toggle headset worn icon visibility."
	hide_headset = !hide_headset
	update_inv_ears()

/mob/living/carbon/human/verb/hide_glasses()
	set name = "Show/Hide Glasses"
	set category = VERB_CAT_IC_SETTINGS
	set desc = "Toggle glasses worn icon visibility."
	hide_glasses = !hide_glasses
	update_inv_glasses()

/mob/living/carbon/human/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---------")
	VV_DROPDOWN_OPTION(VV_HK_SET_SPECIES, "Set Species")
	VV_DROPDOWN_OPTION(VV_HK_TURN_MONKEY, "Make Monkey")
	VV_DROPDOWN_OPTION(VV_HK_TURN_ALIEN, "Make Alien")
	VV_DROPDOWN_OPTION(VK_HK_TURN_SKELETON, "Make Skeleton")
	VV_DROPDOWN_OPTION(VK_HK_TURN_AI, "Make AI")
	VV_DROPDOWN_OPTION(VK_HK_TURN_ROBOT, "Make Robot")


/mob/living/carbon/human/proc/vv_species_choices(datum/act/op/A)
	return sortTim(GLOB.all_species, GLOBAL_PROC_REF(cmp_text_asc))

/mob/living/carbon/human/proc/vv_topic_set_species(datum/act/op/A)
	var/mob/user = A.actor
	var/result = A.step_value("species")
	var/newtype = GLOB.all_species[result]
	admin_ticket_log("[key_name_admin(user)] has modified the bodyparts of [src] to [result]")
	set_species(newtype)

/mob/living/carbon/human/proc/vv_topic_turn_skeleton(datum/act/op/A)
	var/mob/user = A.actor
	ChangeToSkeleton()
	user.client?.debug_variables(src)
	return TRUE

/mob/living/carbon/human/proc/vv_topic_turn_monkey(datum/act/op/A)
	var/mob/user = A.actor
	vv_confirm_transform(user, "monkey")
	return TRUE

/mob/living/carbon/human/proc/vv_topic_turn_alien(datum/act/op/A)
	var/mob/user = A.actor
	vv_confirm_transform(user, "alien")
	return TRUE

/mob/living/carbon/human/proc/vv_topic_turn_ai(datum/act/op/A)
	var/mob/user = A.actor
	vv_confirm_transform(user, "ai")
	return TRUE

/mob/living/carbon/human/proc/vv_topic_turn_robot(datum/act/op/A)
	var/mob/user = A.actor
	vv_confirm_transform(user, "robot")
	return TRUE

/// Asks the admin to confirm turning us into `into` ("monkey", "alien", "ai" or "robot").
/mob/living/carbon/human/proc/vv_confirm_transform(mob/user, into)
	open_request(src, /datum/prompt/choice/vv_transform, PROC_REF(vv_transform_confirmed), answerer = user, into = into)

/// An admin confirming a mob type change into `into`. Re-checked on the answer: still has R_SPAWN.
/datum/prompt/choice/vv_transform
	title = "Confirm"
	question = "Confirm mob type change?"
	choices = list("Transform", "Cancel")
	buttons = TRUE
	timeout = 0
	rights = R_SPAWN
	var/into

/mob/living/carbon/human/proc/vv_transform_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Transform")
		return
	return vv_transform_mob_apply(A)

/mob/living/carbon/human/proc/vv_transform_mob_apply(datum/act/request/A)
	var/datum/prompt/choice/vv_transform/ask = A.answer
	var/mob/user = ask.answerer
	switch(ask.into)
		if("monkey")
			log_admin("[key_name(user)] attempting to monkeyize [key_name(src)]")
			message_admins(span_blue("[key_name_admin(user)] attempting to monkeyize [key_name_admin(src)]"), 1)
			monkeyize()
		if("alien")
			SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_alienize, src)
		if("ai")
			message_admins(span_red("Admin [key_name_admin(user)] AIized [key_name_admin(src)]!"), 1)
			log_admin("[key_name(user)] AIized [key_name(src)]")
			AIize()
		if("robot")
			SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_robotize, src)

/mob/living/carbon/human/proc/synth_reag_toggle()
	set name = "Toggle Reagent Processing"
	set category = VERB_CAT_ABILITIES_VORE
	set desc = "Toggle reagent processing as synth."
	synth_reag_processing = !synth_reag_processing

//Formally used from a paper, gave this to everyone.
/mob/living/carbon/human/verb/create_area()
	set name = "Create Area"
	set desc = "Create an area in a enclosed space, making it able to be powered by an APC."
	set category = VERB_CAT_IC_GAME

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		to_chat(usr, span_warning("You recently tried to create an area. Wait a while before using it again."))
		return

	COOLDOWN_START(src, last_special, 2 SECONDS) // Antispam.
	create_new_area(usr)
	return

/mob/living/carbon/human/ownership()
	. = ..()
	. += owns(nameof(wearing_rig), policy = OWN_CONTAINED)
// Each side effect is created for this human and kept only here and by its finish() timer.
