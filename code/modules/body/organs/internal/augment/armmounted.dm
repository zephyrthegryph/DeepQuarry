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

	target_slot = SLOT_ID_HAND_L

	target_parent_classes = list(ORGAN_FLESH, ORGAN_ROBOT, ORGAN_NANOFORM)

	integrated_object_type = /obj/item/gun/energy/laser/mounted/augment

// A screwdriver swaps the servos to the other side's mount.
CAPABILITIES(/obj/item/organ/internal/augment/armmounted)
	op("swap_mount", tool(TOOL_SCREWDRIVER), wait(0), label("Swap mount"), then(PROC_REF(swap_mount)))

/obj/item/organ/internal/augment/armmounted/proc/swap_mount(datum/act/op/A)
	var/mob/user = A.actor
	switch(organ_tag)
		if(O_AUG_L_FOREARM)
			organ_tag = O_AUG_R_FOREARM
			parent_organ = BP_R_ARM
			target_slot = SLOT_ID_HAND_R
		if(O_AUG_R_FOREARM)
			organ_tag = O_AUG_L_FOREARM
			parent_organ = BP_L_ARM
			target_slot = SLOT_ID_HAND_L
	to_chat(user, span_notice("You swap \the [src]'s servos to install neatly into \the lower [parent_organ] mount."))

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
	target_slot = SLOT_ID_HAND_R

	integrated_object_type = null

/obj/item/organ/internal/augment/armmounted/hand/swap_mount(datum/act/op/A)
	var/mob/user = A.actor
	switch(organ_tag)
		if(O_AUG_L_HAND)
			organ_tag = O_AUG_R_HAND
			parent_organ = BP_R_HAND
			target_slot = SLOT_ID_HAND_R
		if(O_AUG_R_HAND)
			organ_tag = O_AUG_L_HAND
			parent_organ = BP_L_HAND
			target_slot = SLOT_ID_HAND_L
	to_chat(user, span_notice("You swap \the [src]'s servos to install neatly into \the upper [parent_organ] mount."))

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
	target_slot = SLOT_ID_HAND_R

	w_class = ITEMSIZE_HUGE

	integrated_object_type = null

/obj/item/organ/internal/augment/armmounted/shoulder/swap_mount(datum/act/op/A)
	var/mob/user = A.actor
	switch(organ_tag)
		if(O_AUG_L_UPPERARM)
			organ_tag = O_AUG_R_UPPERARM
			parent_organ = BP_R_ARM
			target_slot = SLOT_ID_HAND_R
		if(O_AUG_R_UPPERARM)
			organ_tag = O_AUG_L_UPPERARM
			parent_organ = BP_L_ARM
			target_slot = SLOT_ID_HAND_L
	to_chat(user, span_notice("You swap \the [src]'s servos to install neatly into \the upper [parent_organ] mount."))

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
		H.apply_body_effect(/datum/body_effect/melee_surge, 0.75 MINUTES)

/obj/item/organ/internal/augment/armmounted/shoulder/blade
	name = "armblade implant"
	desc = "A large implant that fits into a subject's arm. It deploys a large metal blade by some painful means."

	icon_state = "augment_armblade"

	integrated_object_type = /obj/item/melee/augment/blade/arm

// The toolkit / multi-tool implant.

/obj/item/organ/internal/augment/armmounted/shoulder/multiple
	name = "rotary toolkit"
	desc = "A large implant that fits into a subject's arm. It deploys an array of tools by some painful means."
	/// Set by integrated_tool_chosen() so the re-entered augment_action() deploys without asking again.
	var/tool_picked = FALSE

	icon_state = "augment_toolkit"

	w_class = ITEMSIZE_HUGE

	integrated_object_type = null

	toolspeed = 0.8

	/// Tool path -> each stowed tool this augment carries (owned), built in Initialize() from
	/// tool_types(). The deployed tool is owned by integrated_object instead, and moves back here
	/// when another is picked (select_integrated_tool()).
	var/list/integrated_tools

	/// Tool name -> its radial image; also the list of names augment_action() offers.
	var/list/integrated_tool_images

	var/list/synths

CAPABILITIES(/obj/item/organ/internal/augment/armmounted/shoulder/multiple)
	owns_many(nameof(synths), starts = PROC_REF(starting_synths))
	owns_many(nameof(integrated_tools), starts = PROC_REF(starting_tools))

/// The stowed tools: tool path -> its instance, for every carried tool the deployed object is not already.
/obj/item/organ/internal/augment/armmounted/shoulder/multiple/proc/starting_tools()
	. = list()
	for(var/path in TYPE_TABLE_GET(src, tool_types))
		if(integrated_object_type && ispath(integrated_object_type, path))
			continue
		.[path] = new path(src)

/// The matter synthesizers feeding the stack tools.
/obj/item/organ/internal/augment/armmounted/shoulder/multiple/proc/starting_synths()
	. = list()
	for(var/datumpath in TYPE_TABLE_GET(src, synth_types))
		. += new datumpath

/// The tools this augment carries (constant per type).
TYPE_TABLE_DECLARE(/obj/item/organ/internal/augment/armmounted/shoulder/multiple, tool_types, list( \
		/obj/item/tool/screwdriver, \
		/obj/item/tool/wrench, \
		/obj/item/tool/crowbar, \
		/obj/item/tool/wirecutters, \
		/obj/item/multitool, \
		/obj/item/stack/cable_coil/gray, \
		/obj/item/tape_roll, \
		))

/// Matter synthesizers feeding the augment's stack tools (constant per type).
TYPE_TABLE_DECLARE(/obj/item/organ/internal/augment/armmounted/shoulder/multiple, synth_types, list(/datum/matter_synth/wire))

/obj/item/organ/internal/augment/armmounted/shoulder/multiple/Initialize(mapload)
	. = ..()

	var/list/tools = all_integrated_tools()
	if(!length(tools))
		return

	integrated_tool_images = list()

	for(var/obj/item/I as anything in tools)
		I.canremove = FALSE
		I.toolspeed = toolspeed
		rel_set(I, nameof(I.my_augment), src)
		I.name = "integrated [I.name]"

	for(var/obj/item/Tool as anything in tools)
		if(istype(Tool, /obj/item/stack))
			var/obj/item/stack/S = Tool
			for(var/datum/matter_synth/MS as anything in synths)
				rel_add(S, nameof(S.synths), MS)
			S.uses_charge = length(synths)
		integrated_tool_images[Tool.name] = image(icon = Tool.icon, icon_state = Tool.icon_state)

/// Every tool this augment carries: the stowed ones and the deployed one.
/obj/item/organ/internal/augment/armmounted/shoulder/multiple/proc/all_integrated_tools()
	. = own_values(src, nameof(integrated_tools))
	if(integrated_object)
		. |= integrated_object

/// The carried tool called `tool_name`, or null.
/obj/item/organ/internal/augment/armmounted/shoulder/multiple/proc/integrated_tool_named(tool_name)
	for(var/obj/item/tool as anything in all_integrated_tools())
		if(tool.name == tool_name)
			return tool
	return null

/// Deploys `tool` as the integrated object. The one put away moves back into integrated_tools
/// (never disposed of), then the chosen one moves out of it into integrated_object.
/obj/item/organ/internal/augment/armmounted/shoulder/multiple/proc/select_integrated_tool(obj/item/tool)
	if(!tool || integrated_object == tool)
		return
	var/tool_key = null
	for(var/key in integrated_tools)
		if(integrated_tools[key] == tool)
			tool_key = key
			break
	if(isnull(tool_key))
		return
	if(integrated_object)
		own_transfer(src, nameof(integrated_object), src, nameof(integrated_tools), null, integrated_object.type)
	own_transfer(src, nameof(integrated_tools), src, nameof(integrated_object), tool_key)

/obj/item/organ/internal/augment/armmounted/shoulder/multiple/handle_organ_proc_special(cycles)
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

	for(var/Iname in integrated_tool_images)
		options[Iname] = integrated_tool_images[Iname]

	if(tool_picked)
		// Re-entry from integrated_tool_chosen(): the tool is already set.
		tool_picked = FALSE
		return ..()

	if(length(options) == 1)
		for(var/key in options)
			select_integrated_tool(integrated_tool_named(key))
		return ..()

	open_request(src, /datum/prompt/choice, PROC_REF(integrated_tool_chosen), answerer = owner, choices = options, anchor = owner, radial = TRUE, autopick_single_option = TRUE, timeout = 0)

/// Answer to augment_action(): set the picked tool and run the deploy (the old ..()).
/obj/item/organ/internal/augment/armmounted/shoulder/multiple/proc/integrated_tool_chosen(datum/act/request/A)
	if(!A.answer)
		return
	if(!owner || A.request.answerer != owner || is_broken())
		return
	select_integrated_tool(integrated_tool_named(A.answer.value))
	tool_picked = TRUE
	augment_action()

/obj/item/organ/internal/augment/armmounted/shoulder/multiple/medical
	name = "rotary medical kit"
	icon_state = "augment_medkit"
	integrated_object_type = null

TYPE_TABLE(/obj/item/organ/internal/augment/armmounted/shoulder/multiple/medical, tool_types, list( \
		/obj/item/surgical/hemostat, \
		/obj/item/surgical/retractor, \
		/obj/item/surgical/cautery, \
		/obj/item/surgical/surgicaldrill, \
		/obj/item/surgical/scalpel, \
		/obj/item/surgical/circular_saw, \
		/obj/item/surgical/bonegel, \
		/obj/item/surgical/FixOVein, \
		/obj/item/surgical/bonesetter, \
		/obj/item/stack/medical/crude_pack, \
		))

TYPE_TABLE(/obj/item/organ/internal/augment/armmounted/shoulder/multiple/medical, synth_types, list(/datum/matter_synth/bandage))

// This organ has work every organ_tick(), so the body's organ clock stays running for it.
/obj/item/organ/internal/augment/armmounted/shoulder/multiple/life_step_idle()
	return FALSE

