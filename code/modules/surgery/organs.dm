// Organ operations: remove, insert (replace = remove then insert), reconnect.
//
// These go through the organ lifecycle (removed() / replaced()), which moves
// the organ's afflictions with it: lesions leave the body in the organ and
// come back when it's implanted again, in this body or another.

/datum/surgical_step/organ
	abstract_type = /datum/surgical_step/organ
	phase = SURGERY_PHASE_OPERATE
	priority = 3
	part_biology = BIOLOGY_ALL
	needs_full_access = TRUE
	duration = 6 SECONDS
	pain = 80
	blood_level = 2

/datum/surgical_step/organ/extract
	name = "Remove Organ"
	allowed_tools = list(
		/obj/item/surgical/hemostat = 100,
		/obj/item/surgical/scalpel/ripper = 100,
		/obj/item/material/kitchen/utensil/fork = 50,
	)
	allowed_tool_qualities = list(TOOL_WIRECUTTER = 100)
	begin_text = "removing"
	end_text = "removes"
	fail_text = "slips, tearing"
	pain_text = "Someone's ripping out something in your %PART%!"
	// A torn organ: a laceration on the organ that was being lifted out.
	complication_kind = INJURY_CUT
	complication_amount = 15
	complication_affliction = /datum/affliction/lesion/laceration

/datum/surgical_step/organ/extract/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return length(removable_organs(target, part)) > 0

/datum/surgical_step/organ/extract/proc/removable_organs(mob/living/carbon/human/target, obj/item/organ/external/part)
	. = list()
	for(var/obj/item/organ/internal/I as anything in part.internal_organs)
		if(I.owner == target)
			.[I.name] = I

/datum/surgical_step/organ/extract/choose_target(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/list/choices = removable_organs(target, part)
	if(!length(choices))
		return null
	var/choice = tgui_input_list(user, "Which organ do you want to remove?", name, choices)
	return choice ? choices[choice] : null

/datum/surgical_step/organ/extract/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/organ/internal/I = work_target
	if(!istype(I) || I.owner != target)
		return
	log_game("SURGERY: [key_name(user)] removed [I] ([I.type]) from [key_name(target)], carrying [length(I.afflictions_here())] afflictions")
	add_attack_logs(user, target, "Surgically removed [I.name]")
	I.removed(user)
	if(ishuman(user))
		user.put_in_hands(I)

/datum/surgical_step/organ/insert
	name = "Insert Organ"
	allowed_tools = list(/obj/item/organ/internal = 100)
	duration = 4 SECONDS
	begin_text = "transplanting an organ into"
	end_text = "transplants an organ into"
	fail_text = "slips, bruising the organ against"
	pain_text = "Someone's rooting around in your %PART%!"
	complication_amount = 0

/datum/surgical_step/organ/insert/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/obj/item/organ/internal/O = tool
	if(!istype(O))
		return FALSE
	if((part.robotic >= ORGAN_ROBOT) && !(O.robotic >= ORGAN_ROBOT))
		to_chat(user, span_warning("There are only sockets and mounts inside \the [part.name]; nothing \the [O] could be seated on."))
		return SURGERY_REFUSED
	if(target.internal_organs_by_name[O.organ_tag])
		to_chat(user, span_warning("There's already something sitting where \the [O] would go."))
		return SURGERY_REFUSED
	if(istype(O, /obj/item/organ/internal/malignant))
		var/obj/item/organ/internal/malignant/ML = O
		if(!(part.organ_tag in ML.surgeryAllowedSites))
			to_chat(user, span_warning("You can't find anywhere in \the [part.name] that \the [O] would fit."))
			return SURGERY_REFUSED
		return TRUE
	if(part.organ_tag != O.parent_organ)
		to_chat(user, span_warning("You can't find anywhere in \the [part.name] that \the [O] would fit."))
		return SURGERY_REFUSED
	return TRUE

/datum/surgical_step/organ/insert/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/organ/internal/O = tool
	if(!istype(O) || target.internal_organs_by_name[O.organ_tag])
		return
	if(istype(O, /obj/item/organ/internal/malignant))
		O.parent_organ = part.organ_tag
	user.remove_from_mob(O)
	O.replaced(target, part)
	log_game("SURGERY: [key_name(user)] implanted [O] ([O.type]) into [key_name(target)] [part], carrying [length(O.afflictions_here())] afflictions")

/// A fumbled transplant bruises the organ being inserted.
/datum/surgical_step/organ/insert/complicate(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	..()
	var/obj/item/organ/internal/O = tool
	if(istype(O))
		O.bench_damage(rand(3, 5), /datum/affliction/lesion/contusion)

/// Rejoin an organ's vessels (a printed or loosened organ is cut away).
/datum/surgical_step/organ/reconnect
	name = "Attach Organ"
	allowed_tools = list(
		/obj/item/surgical/FixOVein = 100,
		/obj/item/stack/cable_coil = 75,
	)
	begin_text = "reconnecting"
	end_text = "reconnects"
	fail_text = "slips, tearing the vessels of"
	complication_kind = INJURY_CUT
	complication_amount = 10
	complication_affliction = /datum/affliction/lesion/laceration

/datum/surgical_step/organ/reconnect/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	for(var/obj/item/organ/internal/I as anything in part.internal_organs)
		if(I.status & ORGAN_CUT_AWAY)
			return TRUE
	return FALSE

/datum/surgical_step/organ/reconnect/choose_target(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/list/choices = list()
	for(var/obj/item/organ/internal/I as anything in part.internal_organs)
		if(I.status & ORGAN_CUT_AWAY)
			choices[I.name] = I
	if(!length(choices))
		return null
	if(length(choices) == 1)
		return choices[choices[1]]
	var/choice = tgui_input_list(user, "Which organ do you want to reattach?", name, choices)
	return choice ? choices[choice] : null

/datum/surgical_step/organ/reconnect/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/organ/internal/I = work_target
	if(istype(I))
		I.status &= ~ORGAN_CUT_AWAY
		log_game("SURGERY: [key_name(user)] reconnected [I] in [key_name(target)]")


// --- Synthetic minds and cephalons ----------------------------------------------------------

/datum/surgical_step/organ/install_mmi
	name = "Install MMI"
	allowed_tools = list(/obj/item/mmi = 100)
	zones = list(BP_HEAD)
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "installing a brain interface into"
	end_text = "installs a brain interface into"
	fail_text = "slips, knocking the interface against"
	complication_kind = INJURY_BLUNT
	complication_amount = 3

/datum/surgical_step/organ/install_mmi/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	if(!istype(tool, /obj/item/mmi))
		return FALSE
	if(!(part.robotic >= ORGAN_ROBOT))
		to_chat(user, span_warning("Inside \the [part.name] is bone and soft tissue; there's no socket for \the [tool]."))
		return SURGERY_REFUSED
	if(!target.should_have_organ(O_BRAIN))
		to_chat(user, span_warning("You search \the [part.name], but there's no cradle for a brain anywhere in it."))
		return SURGERY_REFUSED
	if(target.internal_organs_by_name[O_BRAIN])
		to_chat(user, span_warning("The brain cradle in \the [part.name] is already occupied."))
		return SURGERY_REFUSED
	return TRUE

/datum/surgical_step/organ/install_mmi/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/mmi/M = tool
	var/obj/item/organ/internal/mmi_holder/holder
	user.drop_from_inventory(M)
	if(istype(M, /obj/item/mmi/digital/posibrain/nano))
		holder = new /obj/item/organ/internal/mmi_holder/posibrain/nano(target, 1, M)
	else if(istype(M, /obj/item/mmi/digital/posibrain))
		holder = new /obj/item/organ/internal/mmi_holder/posibrain(target, 1, M)
	else if(istype(M, /obj/item/mmi/digital/robot))
		holder = new /obj/item/organ/internal/mmi_holder/robot(target, 1, M)
	else
		holder = new /obj/item/organ/internal/mmi_holder(target, 1, M)
	target.internal_organs_by_name[O_BRAIN] = holder
	var/datum/component/mind_host/host = get_mind_host(M)
	host?.release_mind(target, "MMI installed into [target] by [key_name(user)]")
	log_game("SURGERY: [key_name(user)] installed [M] into [key_name(target)]")
	INVOKE_ASYNC(target, TYPE_PROC_REF(/mob/living/carbon/human, pick_new_form_name), FALSE)

/datum/surgical_step/organ/install_nymph
	name = "Install Nymph"
	allowed_tools = list(/obj/item/holder/diona = 100)
	zones = list(BP_TORSO)
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "setting a nymph into"
	end_text = "sets a nymph into"
	fail_text = "slips, knocking the nymph against"
	complication_kind = INJURY_BLUNT
	complication_amount = 3

/datum/surgical_step/organ/install_nymph/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/obj/item/holder/diona/N = tool
	if(!istype(N))
		return FALSE
	if(!N.held_mob?.client || N.held_mob.stat >= DEAD)
		to_chat(user, span_warning("\The [N] hangs limp and unresponsive in your hands."))
		return SURGERY_REFUSED
	if(!(part.robotic >= ORGAN_ROBOT))
		to_chat(user, span_warning("\The [part.name] is flesh and bone; there's no frame for \the [N] to take root in."))
		return SURGERY_REFUSED
	if(part.model != "Skrellian Exoskeleton")
		to_chat(user, span_warning("\The [N] shies away from the frame; it isn't built for a nymph to take root in."))
		return SURGERY_REFUSED
	if(!target.should_have_organ(O_BRAIN))
		to_chat(user, span_warning("You search \the [part.name], but there's no cradle for a cephalon anywhere in it."))
		return SURGERY_REFUSED
	if(target.internal_organs_by_name[O_BRAIN])
		to_chat(user, span_warning("There's already something rooted in the frame."))
		return SURGERY_REFUSED
	return TRUE

/datum/surgical_step/organ/install_nymph/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/holder/diona/N = tool
	var/obj/item/organ/internal/brain/cephalon/cephalon = new(target, 1)
	target.internal_organs_by_name[O_BRAIN] = cephalon
	var/mob/living/carbon/alien/diona/D = N.held_mob
	user.drop_from_inventory(tool)
	if(D?.mind)
		D.mind.transfer_to(target)
		target.languages |= D.languages
	qdel(D)
	target.species = GLOB.all_species[SPECIES_DIONA]
	target.invalidate_factors()
	add_verb(target, /mob/living/carbon/human/proc/diona_split_nymph)
	add_verb(target, /mob/living/carbon/human/proc/regenerate)
	log_game("SURGERY: [key_name(user)] installed a nymph into [key_name(target)]")
	INVOKE_ASYNC(target, TYPE_PROC_REF(/mob/living/carbon/human, pick_new_form_name), TRUE)

/// Let the new occupant of a synthetic body pick a name. `required`: keep
/// asking (a bounded number of times) until they do.
/mob/living/carbon/human/proc/pick_new_form_name(required = FALSE)
	var/new_name = required ? "" : real_name
	for(var/attempt in 1 to (required ? 10 : 3))
		if(QDELETED(src) || !client)
			return
		var/try_name = tgui_input_text(src, "Pick a name for your new form!", "New Name", name)
		var/clean_name = sanitizeName(try_name, allow_numbers = TRUE)
		if(clean_name && tgui_alert(src, "New name will be '[clean_name]', ok?", "Confirmation", list("Cancel", "Ok")) == "Ok")
			new_name = clean_name
			break
	if(!new_name)
		return
	name = sanitizeName(new_name, allow_numbers = TRUE)
	real_name = name
