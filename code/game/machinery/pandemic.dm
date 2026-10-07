/obj/machinery/computer/pandemic
	maintenance_flags = MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 4 SECONDS
	name = "PanD.E.M.I.C 2200"
	desc = "Used to work with viruses."
	circuit = /obj/item/circuitboard/pandemic
	density = TRUE
	anchored = TRUE
	icon = 'icons/obj/pandemic.dmi'
	icon_state = "pandemic0"
	idle_power_usage = 20
	use_power = TRUE

	var/temp_html = ""
	var/printing = FALSE
	var/wait = FALSE
	var/obj/item/reagent_containers/beaker = null

// PanDEMIC Vial
/obj/item/reagent_containers/glass/beaker/vial/vaccine
	max_transfer_amount = 15
	volume = 15

/obj/item/reagent_containers/glass/beaker/vial/vaccine/Initialize(mapload)
	. = ..()
	make_sellable(/datum/sellable/vaccine)

/obj/machinery/computer/pandemic/draw(datum/look/look)
	..()
	if(broken_now())
		look.state((beaker ? "pandemic1_b" : "pandemic0_b"))
		return
	look.state("pandemic[(beaker)?"1":"0"][!(power_lost()) ? "" : "_nopower"]")


/obj/machinery/computer/pandemic/proc/ui_act_create_culture_bottle(datum/act/op/A, index)
	var/mob/user = A.actor
	if(wait)
		return FALSE
	create_culture_bottle(index, user)
	return TRUE

/obj/machinery/computer/pandemic/proc/ui_act_create_vaccine_bottle(datum/act/op/A, index)
	if(wait)
		atom_say("The replicator is not ready yet.")
		return FALSE
	create_vaccine_bottle(index)
	return TRUE

/obj/machinery/computer/pandemic/proc/ui_act_eject_beaker(datum/act/op/A)
	var/mob/user = A.actor
	eject_beaker()
	update_tgui_static_data(user)
	return TRUE

/obj/machinery/computer/pandemic/proc/ui_act_destroy_eject_beaker(datum/act/op/A)
	var/mob/user = A.actor
	beaker.reagents.clear_reagents()
	eject_beaker()
	update_tgui_static_data(user)
	return TRUE

/obj/machinery/computer/pandemic/proc/ui_act_empty_beaker(datum/act/op/A)
	beaker.reagents.clear_reagents()
	return TRUE

/obj/machinery/computer/pandemic/proc/ui_act_rename_disease(datum/act/op/A, index, raw_name)
	rename_disease(index, raw_name)
	return TRUE

/obj/machinery/computer/pandemic/proc/ui_act_print_release_form(datum/act/op/A, index)
	var/mob/user = A.actor
	var/strain_index = index
	if(isnull(strain_index))
		atom_say("Unable to respond to command.")
		return FALSE
	var/type = get_virus_id_by_index(strain_index)
	if(!type)
		atom_say("Unable to find requested strain.")
		return FALSE
	var/datum/affliction/contagion/engineered/strain = GLOB.archive_diseases[type]
	if(!strain)
		atom_say("Unable to find requested strain.")
		return FALSE
	print_form(strain, user)
	return TRUE

CAPABILITIES(/obj/machinery/computer/pandemic)
	op("insert_beaker", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Insert beaker"), when(PROC_REF(beaker_item_holds)), needs(req(PROC_REF(empty_slot_holds), because = "a beaker is already loaded")), then(PROC_REF(interaction_insert_beaker)))
	interface("Pandemic", state = nameof(GLOB.tgui_default_state))
	op("create_culture_bottle", ui_act("create_culture_bottle", arg("index", num())), then(PROC_REF(ui_act_create_culture_bottle)))
	op("create_vaccine_bottle", ui_act("create_vaccine_bottle", arg("index", schema_text(4096))), then(PROC_REF(ui_act_create_vaccine_bottle)))
	op("eject_beaker", ui_act("eject_beaker"), then(PROC_REF(ui_act_eject_beaker)))
	op("destroy_eject_beaker", ui_act("destroy_eject_beaker"), then(PROC_REF(ui_act_destroy_eject_beaker)))
	op("empty_beaker", ui_act("empty_beaker"), then(PROC_REF(ui_act_empty_beaker)))
	op("rename_disease", ui_act("rename_disease", arg("index"), arg("name", schema_text(4096))), then(PROC_REF(ui_act_rename_disease)))
	op("print_release_form", ui_act("print_release_form", arg("index", num())), then(PROC_REF(ui_act_print_release_form)))
	extend(TAG_UI, needs(req(PROC_REF(console_works), because = MSG(pandemic/not_working))))

CAPABILITIES(/datum/prompt/text/pandemic_release_reason)
	ref_one(nameof(affliction), /datum/affliction/contagion/engineered)

CAPABILITIES(/datum/prompt/yes_no/pandemic_release_sign)
	ref_one(nameof(disease), /datum/affliction/contagion/engineered)

MSG_DEF_SELF(pandemic/not_working, "It isn't working.")

/// The console answers only while it works.
/obj/machinery/computer/pandemic/proc/console_works(datum/act/op/A)
	return operable()

/obj/machinery/computer/pandemic/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["is_ready"] = !wait
	if(!beaker)
		data["has_beaker"] = FALSE
		data["has_blood"] = FALSE
		return data
	data["has_beaker"] = TRUE
	data["beaker"] = list(
		"volume" = round(beaker.reagents?.total_volume, 0.01) || 0,
		"capacity" = beaker.volume
	)
	var/datum/reagent/blood/blood = locate_in_list(beaker.reagents.reagent_list, /datum/reagent/blood)
	if(!blood)
		data["has_blood"] = FALSE
		return data

	data["has_blood"] = TRUE
	data["blood"] = list()
	data["blood"]["dna"] = blood.data["blood_DNA"] || "none"
	data["blood"]["type"] = blood.data["blood_type"] || "none"
	data["viruses"] = get_viruses_data(blood)
	data["resistances"] = get_resistance_data(blood)

	return data

/obj/machinery/computer/pandemic/proc/eject_beaker()
	set name = "Eject Beaker"
	set category = VERB_CAT_OBJECT
	set src in oview(1)

	if(usr.stat != 0)
		return

	if(!beaker)
		return
	beaker.forceMove(loc)
	rel_take(src, nameof(beaker))
	icon_state = "pandemic0"

/obj/machinery/computer/pandemic/proc/print_form(datum/affliction/contagion/engineered/D, mob/living/user)
	D = GLOB.archive_diseases[D.GetDiseaseID()]
	if(!istype(D))
		visible_message(span_warning("ERROR: Unable to print form."))
		play_sfx(loc, SFX_MACHINES_BUZZ_SIGH, vary = TRUE)
		return
	if(!(printing) && D)
		open_request(src, /datum/prompt/text/pandemic_release_reason, PROC_REF(release_reason_written), valid = PROC_REF(request_usable), answerer = user, title = "Write", question = "Enter a reason for the release", multiline = TRUE, affliction = D, timeout = 0)

/// The release reason's question: the strain it is for is kept on it.
/datum/prompt/text/pandemic_release_reason
	var/datum/affliction/contagion/engineered/affliction

/obj/machinery/computer/pandemic/proc/release_reason_written(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/text/pandemic_release_reason/R = A.request
	open_request(src, /datum/prompt/yes_no/pandemic_release_sign, PROC_REF(release_form_written), valid = PROC_REF(sign_usable), answerer = R.answerer, title = "Signature", question = "Would you like to add your signature?", disease = R.affliction, reason = A.answer.value, timeout = 0)

/// The signature question: the strain and the reason are kept on it.
/datum/prompt/yes_no/pandemic_release_sign
	var/datum/affliction/contagion/engineered/disease
	var/reason

/// Re-checked: nothing is being printed, and the console is still worth answering.
/obj/machinery/computer/pandemic/proc/sign_usable(datum/request/R)
	return !printing && request_usable(R)

/obj/machinery/computer/pandemic/proc/release_form_written(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/yes_no/pandemic_release_sign/R = A.request
	var/mob/living/user = R.answerer
	var/datum/affliction/contagion/engineered/D = R.disease
	var/reason = R.reason
	reason += "<span class=\"paper_field\"></span>"
	var/english_symptoms = list()
	for(var/I in D.symptoms)
		var/datum/viral_trait/S = I
		english_symptoms += S.name
	var/symptoms = english_list(english_symptoms)

	var/signature
	if(A.answer.value)
		signature = "<font face=\"Times New Roman\">" + span_italics("[user ? user.real_name : "Anonymous"]") + "</font>"
	else
		signature = "<span class=\"paper_field\"></span>"

	printing = TRUE
	var/obj/item/paper/P = new /obj/item/paper(loc)
	visible_message(span_notice("[src] rattles and prints out a sheet of paper."))
	play_sfx(loc, SFX_MACHINES_PRINTER)

	P.info = span_underline(span_huge(span_bold("<center> Releasing Virus </center>")))
	P.info += "<HR>"
	P.info += span_underline("Name of the Virus:") + " [D.name] <BR>"
	P.info += span_underline("Symptoms:") + " [symptoms]<BR>"
	P.info += span_underline("Spreads by:") + " [D.spread_text]<BR>"
	P.info += span_underline("Cured by:") + " [D.cure_text]<BR>"
	P.info += "<BR>"
	P.info += span_underline("Reason for releasing:") + " [reason]"
	P.info += "<HR>"
	P.info += "The Virologist is responsible for any biohazards caused by the virus released.<BR>"
	P.info += span_underline("Virologist's sign:") + " [signature]<BR>"
	P.info += "If approved, stamp below with the Chief Medical Officer's stamp, and/or the Captain's stamp if required:"
	P.updateinfolinks()
	P.name = "Releasing Virus - [D.name]"
	printing = FALSE


/obj/machinery/computer/pandemic/proc/is_beaker_or_syringe(mob/actor, atom/target, obj/item/held)
	return (istype(held, /obj/item/reagent_containers/glass) && held.is_open_container()) || istype(held, /obj/item/reagent_containers/syringe)

/obj/machinery/computer/pandemic/proc/beaker_slot_empty(mob/actor, atom/target, obj/item/held)
	return !beaker

/// The old stat check was silent (no message), so it stays in the effect.
/obj/machinery/computer/pandemic/proc/interaction_insert_beaker(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(!operable())
		return TRUE
	if(!move_into(src, nameof(src.beaker), I, user))
		return TRUE
	to_chat(user, span_notice("You add \the [I] to the machine."))
	update_tgui_static_data(user)
	icon_state = "pandemic1"
	return TRUE

/obj/machinery/computer/pandemic/proc/get_viruses_data(datum/reagent/blood/blood)
	. = list()
	var/list/viruses = blood.get_diseases()
	var/index = 1

	for(var/datum/affliction/contagion/disease as anything in viruses)
		if(CHECK_BITFIELD(disease.visibility_flags, HIDDEN_PANDEMIC))
			continue

		var/list/traits = list()
		traits["name"] = disease.name
		if(istype(disease, /datum/affliction/contagion/engineered))
			var/datum/affliction/contagion/engineered/adv_disease = disease
			traits["can_rename"] = TRUE // Allow for all diseases to change currently. Mutable trait maybe?
			traits["name"] = disease.name
			traits["is_adv"] = TRUE
			traits["symptoms"] = list()
			for(var/datum/viral_trait/symptom as anything in adv_disease.symptoms)
				traits["symptoms"] += list(symptom.get_symptom_data())
			traits["resistance"] = adv_disease.resistance
			traits["stealth"] = adv_disease.stealth
			traits["stage_speed"] = adv_disease.stage_rate
			traits["transmission"] = adv_disease.transmission
			traits["severity"] = adv_disease.threat

		traits["index"] = index++
		traits["agent"] = disease.agent
		traits["description"] = disease.desc || "none"
		traits["spread"] = disease.spread_text || "none"
		traits["cure"] = disease.cure_text || "none"
		traits["danger"] = disease.danger || "none"

		. += list(traits)

/obj/machinery/computer/pandemic/proc/get_resistance_data(datum/reagent/blood/blood)
	var/list/data = list()
	if(!islist(blood.data["resistances"]))
		return data
	var/list/resistances = blood.data["resistances"]
	for(var/id in resistances)
		var/list/resistance = list()
		var/datum/affliction/contagion/disease = GLOB.archive_diseases[id]
		if(disease)
			resistance["id"] = id
			resistance["name"] = disease.name
		data += list(resistance)
	return data

/obj/machinery/computer/pandemic/proc/get_by_index(thing, index)
	if(!beaker || !beaker.reagents)
		return FALSE
	var/datum/reagent/blood/blood = locate_in_list(beaker.reagents.reagent_list, /datum/reagent/blood)
	if(blood?.data[thing])
		return blood.data[thing][index]
	return FALSE

/obj/machinery/computer/pandemic/proc/get_virus_id_by_index(index)
	var/datum/affliction/contagion/disease = get_by_index("viruses", index)
	if(!disease)
		return FALSE
	return disease.GetDiseaseID()

/obj/machinery/computer/pandemic/proc/create_vaccine_bottle(index)
	use_power(active_power_usage)
	var/id = get_virus_id_by_index(text2num(index))
	var/datum/affliction/contagion/disease = GLOB.archive_diseases[id]
	if(!disease)
		return FALSE
	var/obj/item/reagent_containers/glass/beaker/vial/vaccine/bottle = new(drop_location())
	bottle.name = "[disease.name] vaccine"
	bottle.reagents.add_reagent(REAGENT_ID_VACCINE, 15, list(get_by_index("resistances", id)))
	beaker.reagents.remove_reagent(REAGENT_ID_BLOOD, 5)
	wait = TRUE
	after(src, 20 SECONDS, PROC_REF(reset_replicator_cooldown))
	return TRUE

/obj/machinery/computer/pandemic/proc/create_culture_bottle(index, mob/user)
	var/id = get_virus_id_by_index(text2num(index))
	var/datum/affliction/contagion/engineered/adv_disease = GLOB.archive_diseases[id]

	if(!istype(adv_disease))
		to_chat(user, span_warning("ERROR: Cannot replicate virus strain."))
		return FALSE

	if(!beaker.reagents.has_reagent(REAGENT_ID_BLOOD, 10))
		to_chat(user, span_warning("ERROR: Not enough blood in the sample."))
		return

	var/old_name = adv_disease.name

	use_power(active_power_usage)
	adv_disease = adv_disease.Copy()
	adv_disease.name = old_name
	var/list/cures = get_beaker_cures(id)
	if(cures.len)
		adv_disease.cures = cures[1]
		adv_disease.cure_text = cures[2]
	var/list/data = list("viruses" = list(adv_disease))

	var/obj/item/reagent_containers/glass/beaker/vial/bottle = new(drop_location())
	bottle.name = "[adv_disease.name] culture vial"
	bottle.desc = "A small vial containing [adv_disease.agent] culture in synthblood."
	bottle.reagents.add_reagent(REAGENT_ID_BLOOD, 10, data)
	beaker.reagents.remove_reagent(REAGENT_ID_BLOOD, 10)
	wait = TRUE
	after(src, 5 SECONDS, PROC_REF(reset_replicator_cooldown))
	return TRUE

/obj/machinery/computer/pandemic/proc/get_beaker_cures(disease_id)
	var/list/cures = list()
	if(!beaker)
		return cures

	var/datum/reagent/blood/blood = beaker.reagents.get_reagent(REAGENT_ID_BLOOD)
	if(!blood)
		return cures

	var/list/viruses = blood.get_diseases()
	if(!length(viruses))
		return cures

	for(var/datum/affliction/contagion/engineered/disease in viruses)
		if(disease.GetDiseaseID() == disease_id)
			cures.Add(disease.cures)
			cures.Add(disease.cure_text)
			break

	return cures

/obj/machinery/computer/pandemic/proc/rename_disease(index, name)
	var/id = get_virus_id_by_index(text2num(index))
	var/datum/affliction/contagion/engineered/adv_disease = GLOB.archive_diseases[id]

	if(adv_disease)
		if(!name)
			return FALSE
		adv_disease.AssignName(name)
		return TRUE
	return FALSE

/obj/machinery/computer/pandemic/proc/reset_replicator_cooldown()
	wait = FALSE
	SStgui.update_uis(src)
	play_sfx(src, SFX_MACHINES_PING, 0.6, vary = TRUE)
	return TRUE

/obj/machinery/computer/pandemic/ownership()
	. = ..()
	. += owns(nameof(beaker), policy = OWN_CONTAINED)

/obj/machinery/computer/pandemic/proc/beaker_item_holds(datum/act/op/A)
	return is_beaker_or_syringe(A.actor, src, A.held)

/obj/machinery/computer/pandemic/proc/empty_slot_holds(datum/act/op/A)
	return !beaker
