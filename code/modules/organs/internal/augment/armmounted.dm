/*
 * Arm mounted augments.
 */

/obj/item/organ/internal/augment/armmounted
	name = "laser rifle implant"
	desc = "A large implant that fits into a subject's arm. It deploys a laser-emitting array by some painful means."

	icon_state = "augment_laser"

	w_class = ITEMSIZE_LARGE

	organ_tag = O_AUG_L_FOREARM

	parent_organ = BP_L_ARM

	target_slot = slot_l_hand

	target_parent_classes = list(ORGAN_FLESH, ORGAN_ROBOT, ORGAN_NANOFORM)

	integrated_object_type = /obj/item/gun/energy/laser/mounted/augment

/obj/item/organ/internal/augment/armmounted/screwdriver_act(mob/user, obj/item/tool)
	switch(organ_tag)
		if(O_AUG_L_FOREARM)
			organ_tag = O_AUG_R_FOREARM
			parent_organ = BP_R_ARM
			target_slot = slot_r_hand
		if(O_AUG_R_FOREARM)
			organ_tag = O_AUG_L_FOREARM
			parent_organ = BP_L_ARM
			target_slot = slot_l_hand
	to_chat(user, span_notice("You swap \the [src]'s servos to install neatly into \the lower [parent_organ] mount."))
	return ITEM_INTERACT_SUCCESS

/obj/item/organ/internal/augment/armmounted/taser
	name = "taser implant"
	desc = "A large implant that fits into a subject's arm. It deploys a taser-emitting array by some painful means."

	icon_state = "augment_taser"

	integrated_object_type = /obj/item/gun/energy/taser/mounted/augment

/obj/item/organ/internal/augment/armmounted/dartbow
	name = "crossbow implant"
	desc = "A small implant that fits into a subject's arm. It deploys a dart launching mechanism through the flesh through unknown means."

	icon_state = "augment_dart"

	w_class = ITEMSIZE_SMALL

	integrated_object_type = /obj/item/gun/energy/crossbow

// Wrist-or-hand-mounted implant

/obj/item/organ/internal/augment/armmounted/hand
	name = "resonant analyzer implant"
	desc = "An augment that fits neatly into the hand, useful for determining the usefulness of an object for research."
	icon_state = "augment_box"

	w_class = ITEMSIZE_SMALL
	// Needs to be redefined here, or the switch statement beneath with no default case can never change target limb... Also prevents putting it in your shoulder when it's a hand implant.
	organ_tag = O_AUG_R_HAND
	parent_organ = BP_R_HAND
	target_slot = slot_r_hand

	integrated_object_type = null

/obj/item/organ/internal/augment/armmounted/hand/screwdriver_act(mob/user, obj/item/tool)
	switch(organ_tag)
		if(O_AUG_L_HAND)
			organ_tag = O_AUG_R_HAND
			parent_organ = BP_R_HAND
			target_slot = slot_r_hand
		if(O_AUG_R_HAND)
			organ_tag = O_AUG_L_HAND
			parent_organ = BP_L_HAND
			target_slot = slot_l_hand
	to_chat(user, span_notice("You swap \the [src]'s servos to install neatly into \the upper [parent_organ] mount."))
	return ITEM_INTERACT_SUCCESS

/obj/item/organ/internal/augment/armmounted/hand/sword
	name = "energy blade implant"

	integrated_object_type = /obj/item/melee/energy/sword

/obj/item/organ/internal/augment/armmounted/hand/blade
	name = "handblade implant"
	desc = "A small implant that fits neatly into the hand. It deploys a small, but dangerous blade."
	icon_state = "augment_handblade"

	integrated_object_type = /obj/item/melee/augment/blade

/*
 * Shoulder augment.
 */

/obj/item/organ/internal/augment/armmounted/shoulder
	name = "shoulder augment"
	desc = "A large implant that fits into a subject's arm. It looks kind of like a skeleton."

	icon_state = "augment_armframe"

	organ_tag = O_AUG_R_UPPERARM
	parent_organ = BP_R_ARM
	target_slot = slot_r_hand

	w_class = ITEMSIZE_HUGE

	integrated_object_type = null

/obj/item/organ/internal/augment/armmounted/shoulder/screwdriver_act(mob/user, obj/item/tool)
	switch(organ_tag)
		if(O_AUG_L_UPPERARM)
			organ_tag = O_AUG_R_UPPERARM
			parent_organ = BP_R_ARM
			target_slot = slot_r_hand
		if(O_AUG_R_UPPERARM)
			organ_tag = O_AUG_L_UPPERARM
			parent_organ = BP_L_ARM
			target_slot = slot_l_hand
	to_chat(user, span_notice("You swap \the [src]'s servos to install neatly into \the upper [parent_organ] mount."))
	return ITEM_INTERACT_SUCCESS

/obj/item/organ/internal/augment/armmounted/shoulder/surge
	name = "muscle overclocker"

	aug_cooldown = 1.5 MINUTES

/obj/item/organ/internal/augment/armmounted/shoulder/surge/augment_action()
	if(!owner)
		return

	if(aug_cooldown)
		if(COOLDOWN_FINISHED(src, cooldown))
			COOLDOWN_START(src, cooldown, aug_cooldown)
		else
			return

	if(ishuman(owner))
		var/mob/living/carbon/human/H = owner
		H.add_modifier(/datum/modifier/melee_surge, 0.75 MINUTES)

/obj/item/organ/internal/augment/armmounted/shoulder/blade
	name = "armblade implant"
	desc = "A large implant that fits into a subject's arm. It deploys a large metal blade by some painful means."

	icon_state = "augment_armblade"

	integrated_object_type = /obj/item/melee/augment/blade/arm

// The toolkit / multi-tool implant.

/obj/item/organ/internal/augment/armmounted/shoulder/multiple
	name = "rotary toolkit"
	desc = "A large implant that fits into a subject's arm. It deploys an array of tools by some painful means."

	icon_state = "augment_toolkit"

	w_class = ITEMSIZE_HUGE

	integrated_object_type = null

	toolspeed = 0.8

	/// Tool path -> the tool this augment carries, built in Initialize() from tool_types().
	var/list/integrated_tools

	var/list/integrated_tools_by_name

	var/list/integrated_tool_images

	var/list/synths

/// The tools this augment carries (constant per type).
/obj/item/organ/internal/augment/armmounted/shoulder/multiple/proc/tool_types()
	var/static/list/types = list(
		/obj/item/tool/screwdriver,
		/obj/item/tool/wrench,
		/obj/item/tool/crowbar,
		/obj/item/tool/wirecutters,
		/obj/item/multitool,
		/obj/item/stack/cable_coil/gray,
		/obj/item/tape_roll,
		)
	return types

/// Matter synthesizers feeding the augment's stack tools (constant per type).
/obj/item/organ/internal/augment/armmounted/shoulder/multiple/proc/synth_types()
	var/static/list/types = list(/datum/matter_synth/wire)
	return types

/obj/item/organ/internal/augment/armmounted/shoulder/multiple/Initialize(mapload)
	. = ..()

	integrated_tools = list()
	for(var/path in tool_types())
		integrated_tools[path] = null

	if(integrated_object)
		integrated_tools[integrated_object_type] = integrated_object

	if(integrated_tools && integrated_tools.len)

		integrated_tools_by_name = list()

		integrated_tool_images = list()

		var/list/synth_paths = synth_types()
		if(length(synth_paths))
			synths = list()
			for(var/datumpath in synth_paths)
				var/datum/matter_synth/MS = new datumpath
				synths += MS

		for(var/path in integrated_tools)
			if(!integrated_tools[path])
				integrated_tools[path] = new path(src)
			var/obj/item/I = integrated_tools[path]
			I.canremove = FALSE
			I.toolspeed = toolspeed
			I.my_augment = src
			I.name = "integrated [I.name]"

		for(var/tool in integrated_tools)
			var/obj/item/Tool = integrated_tools[tool]
			if(istype(Tool, /obj/item/stack))
				var/obj/item/stack/S = Tool
				S.synths = synths
				S.uses_charge = synths.len
			integrated_tools_by_name[Tool.name] = Tool
			integrated_tool_images[Tool.name] = image(icon = Tool.icon, icon_state = Tool.icon_state)

/obj/item/organ/internal/augment/armmounted/shoulder/multiple/handle_organ_proc_special()
	..()

	if(!owner || is_bruised() || !synths)
		return

	if(prob(20))
		for(var/datum/matter_synth/MS in synths)
			MS.add_charge(MS.recharge_rate)

/obj/item/organ/internal/augment/armmounted/shoulder/multiple/augment_action()
	if(!owner)
		return

	var/list/options = list()

	for(var/Iname in integrated_tools_by_name)
		options[Iname] = integrated_tool_images[Iname]

	var/list/choice = list()
	if(length(options) == 1)
		for(var/key in options)
			choice = key
	else
		choice = show_radial_menu(owner, owner, options)

	integrated_object = integrated_tools_by_name[choice]

	..()

/obj/item/organ/internal/augment/armmounted/shoulder/multiple/medical
	name = "rotary medical kit"
	icon_state = "augment_medkit"
	integrated_object_type = null

/obj/item/organ/internal/augment/armmounted/shoulder/multiple/medical/tool_types()
	var/static/list/types = list(
		/obj/item/surgical/hemostat,
		/obj/item/surgical/retractor,
		/obj/item/surgical/cautery,
		/obj/item/surgical/surgicaldrill,
		/obj/item/surgical/scalpel,
		/obj/item/surgical/circular_saw,
		/obj/item/surgical/bonegel,
		/obj/item/surgical/FixOVein,
		/obj/item/surgical/bonesetter,
		/obj/item/stack/medical/crude_pack,
		)
	return types

/obj/item/organ/internal/augment/armmounted/shoulder/multiple/medical/synth_types()
	var/static/list/types = list(/datum/matter_synth/bandage)
	return types
