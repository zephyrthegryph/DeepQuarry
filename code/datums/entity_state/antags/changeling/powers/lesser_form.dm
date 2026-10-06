/datum/power/changeling/lesser_form
	name = "Lesser Form"
	desc = "We debase ourselves and become lesser.  We become a monkey."
	genomecost = 1
	verbpath = /mob/proc/changeling_lesser_form

//Transform into a monkey.
/mob/proc/changeling_lesser_form()
	set category = VERB_CAT_CHANGELING
	set name = "Lesser Form (1)"

	var/datum/changeling/changeling = changeling_power(1,0,0)
	if(!changeling)
		return

	if(has_brain_worms())
		to_chat(src, span_warning("We cannot perform this ability at the present time!"))
		return

	var/mob/living/carbon/human/H = src

	if(!istype(H))
		to_chat(src, span_warning("We must be a humanoid to use thia bility!!"))
		return

	else if(!H.species.primitive_form)
		to_chat(src, span_warning("The species we are currently in the form of does not have a primitive form!"))
		to_chat(src, span_info("NOTE: Species such as Unathi, Tajaran, Akula, and Human have primitive forms. Things such as custom species do not.")) //Let's add a warning...Ideally, we change primitive form to be based off body style, but we still run into the problem of some speices not having them.
		return

	changeling.chem_charges--
	H.remove_changeling_powers()
	act_message(H, null, others = span_warning("%U% transforms!"))
	changeling.geneticdamage = 30
	to_chat(H, span_warning("Our genes cry out!"))
	var/list/implants = list() //Try to preserve implants.
	for(var/obj/item/implant/W in contents_of(H))
		implants += W
	H.monkeyize()
	feedback_add_details("changeling_powers","LF")
	return 1

//Transform into a human
/mob/proc/changeling_lesser_transform()
	set category = VERB_CAT_CHANGELING
	set name = "Transform (1)"

	return lesser_transform_stage()

/mob/proc/lesser_transform_stage(selected_form, selected_ready = FALSE)

	var/datum/changeling/changeling = changeling_power(1,1,0)
	if(!changeling)	return

	var/list/names = list()
	for(var/datum/dna/DNA in changeling.absorbed_dna)
		names += "[DNA.real_name]"

	if(!selected_ready)
		open_request(src, /datum/prompt/choice, PROC_REF(lesser_transform_answered), answerer = src, question = "Select the target DNA:", title = "Target DNA", choices = names, timeout = 0)
		return
	var/S = selected_form
	if(isnull(S))
		return
	if(!S)
		return

	var/datum/dna/chosen_dna = changeling.GetDNA(S)
	if(!chosen_dna)
		return

	var/mob/living/carbon/C = src

	changeling.chem_charges--
	C.remove_changeling_powers()
	act_message(C, null, others = span_warning("%U% transforms!"))
	rel_set(C, nameof(C.dna), chosen_dna.Clone())

	var/list/implants = list()
	for (var/obj/item/implant/I in C) //Still preserving implants
		implants += I

	C.set_transforming(1)
	C.canmove = 0
	C.icon = null
	C.cut_overlays()
	C.invisibility = INVISIBILITY_ABSTRACT
	var/atom/movable/overlay/animation = new /atom/movable/overlay( C.loc )
	animation.icon_state = "blank"
	animation.icon = 'icons/mob/mob.dmi'
	rel_set(animation, nameof(animation.master), src)
	flick("monkey2h", animation)
	after(src, 4.8 SECONDS, PROC_REF(changeling_lesser_transform_finish), with = list(animation, chosen_dna, implants))
	return 1

/// The transformation, once its animation has played.
/mob/proc/changeling_lesser_transform_finish(atom/movable/overlay/animation, datum/dna/chosen_dna, list/implants)
	var/mob/living/carbon/C = src
	var/datum/changeling/changeling = is_changeling(src)
	spent(animation)

	for(var/obj/item/W in contents_of(src))
		C.drop_from_inventory(W)

	var/mob/living/carbon/human/O = new /mob/living/carbon/human( src )
	if (C.dna.GetUIState(DNA_UI_GENDER))
		O.gender = FEMALE
	else
		O.gender = MALE
	rel_set(O, nameof(O.dna), C.dna.Clone())
	own_clear(C, nameof(C.dna), OWN_DELETE)
	O.real_name = chosen_dna.real_name

	for(var/obj/T in C)
		spent(T)

	O.forceMove(C.loc)

	O.UpdateAppearance()
	domutcheck(O, null)
	// Carry the injury load over to the new form.
	O.injure(INJURY_TOXIN, C.injury_load(INJURY_CATEGORY_TOXIC), flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	O.injure(INJURY_BLUNT, C.injury_load(INJURY_CATEGORY_PHYSICAL), flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	O.add_oxygen_debt(C.oxygen_debt())
	O.injure(INJURY_BURN, C.injury_load(INJURY_CATEGORY_THERMAL), flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	O.set_stat(C.stat)
	for (var/obj/item/implant/I in implants)
		I.forceMove(O)
		I.implanted = O

	C.mind.transfer_to(O)
	O.make_changeling()
	O.changeling_update_languages(changeling.absorbed_languages)

	feedback_add_details("changeling_powers","LFT")
	spent(C)
	return 1

/mob/proc/lesser_transform_answered(datum/act/request/context)
	if(!context.answer)
		return
	. = lesser_transform_apply(context)
	SStgui.update_uis(src)

/mob/proc/lesser_transform_apply(datum/act/request/context)
	return lesser_transform_stage(context.answer.value, TRUE)
