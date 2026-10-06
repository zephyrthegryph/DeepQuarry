/**
 * Multitool -- A multitool is used for hacking electronic devices.
 * TO-DO -- Using it as a power measurement tool for cables etc. Nannek.
 *
 */

MATERIAL_MIX(/obj/item/multitool, list(MAT_STEEL = 50,MAT_GLASS = 20))
/obj/item/multitool
	name = "multitool"
	desc = "Used for pulsing wires to test which to cut. Not recommended by doctors."
	icon = 'icons/obj/device.dmi'
	icon_state = "multitool"
	force = 5.0
	w_class = ITEMSIZE_SMALL
	throwforce = 5.0
	throw_range = 15
	throw_speed = 3
	drop_sound = SFX_ITEMS_DROP_MULTITOOL
	pickup_sound = SFX_ITEMS_PICKUP_MULTITOOL


	var/mode_index = 1
	var/toolmode = MULTITOOL_MODE_STANDARD
	var/static/list/modes = list(MULTITOOL_MODE_STANDARD, MULTITOOL_MODE_INTCIRCUITS)

	var/obj/machinery/telecomms/buffer // simple machine buffer for device linkage
	var/obj/machinery/clonepod/connecting //same for cryopod linkage
	var/obj/machinery/connectable	//Used to connect machinery.
	var/ref_wiring //An IC ref (ic_ref()) for integrated circuitry. This is now the Omnitool.
	toolspeed = 1
	tool_qualities = list(TOOL_MULTITOOL)

	var/uplink = FALSE

TRACKED(/obj/item/multitool, uplink)

CAPABILITIES(/obj/item/multitool)
	ref_one(nameof(selected_io), /datum/integrated_io)
	// the old attack_self: a wired connection is cleared; otherwise the multitool's menu
	op("menu", in_hand(), when(cond_not(nameof(uplink))),
		asks(/datum/prompt/choice, fields = list("title" = "Multitool Menu", "question" = computed(PROC_REF(menu_question)), "choices" = list("Switch Mode", "Clear Buffers", "Cancel"), "buttons" = TRUE, "timeout" = 0), when = PROC_REF(no_wired_connection)),
		then(PROC_REF(menu_chosen)))
	// an uplink multitool opens its hidden uplink instead
	op("uplink", in_hand(), when(nameof(uplink)), then(PROC_REF(open_uplink)))

/obj/item/multitool/proc/open_uplink(datum/act/op/A)
	item_hidden_uplink(src)?.trigger(A.actor)
	return OP_OK

/obj/item/multitool/proc/menu_question(datum/act/A)
	return "What do you want to do with \the [src]?"

/// No wired connection is held: the menu is asked.
/obj/item/multitool/proc/no_wired_connection(datum/act/op/A)
	return !selected_io

/// Old attack_self: clear the wired connection, or what the menu picked.
/obj/item/multitool/proc/menu_chosen(datum/act/op/A)
	var/mob/living/user = A.actor
	if(selected_io())
		rel_clear(src, nameof(selected_io))
		to_chat(user, span_notice("You clear the wired connection from the multitool."))
		return OP_OK
	var/datum/prompt/R = A.answer
	if(!R)
		return OP_OK
	switch(R.value)
		if("Clear Buffers")
			to_chat(user,span_notice("You clear \the [src]'s memory."))
			rel_clear(src, nameof(buffer))
			rel_clear(src, nameof(connecting))
			rel_clear(src, nameof(connectable))
			ref_wiring = null
			accepting_refs = 0
			if(toolmode == MULTITOOL_MODE_INTCIRCUITS)
				accepting_refs = 1
		if("Switch Mode")
			mode_switch(user)
		else
			to_chat(user,span_notice("You lower \the [src]."))
			return OP_OK

	return OP_OK

/obj/item/multitool/proc/mode_switch(mob/living/user)
	if(mode_index + 1 > modes.len) mode_index = 1

	else
		mode_index += 1

	toolmode = modes[mode_index]
	to_chat(user,span_notice("\The [src] is now set to [toolmode]."))

	accepting_refs = (toolmode == MULTITOOL_MODE_INTCIRCUITS)

	return

/datum/category_item/catalogue/anomalous/precursor_a/alien_multitool
	name = "Precursor Alpha Object - Pulse Tool"
	desc = "This ancient object appears to be an electrical tool. \
	It has a simple mechanism at the handle, which will cause a pulse of \
	energy to be emitted from the head of the tool. This can be used on a \
	conductive object such as a wire, in order to send a pulse signal through it.\
	<br><br>\
	These qualities make this object somewhat similar in purpose to the common \
	multitool, and can probably be used for tasks such as direct interfacing with \
	an airlock, if one knows how."
	value = CATALOGUER_REWARD_EASY

/obj/item/multitool/alien
	name = "alien multitool"
	desc = "An omni-technological interface."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_multitool)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "multitool"
	toolspeed = 0.1

// Alien multitool only has those icon states
/obj/item/multitool/alien/look_parts(datum/look/look)
	if(accepting_refs)
		look.state("multitool_ref_scan")
		return
	look.state("multitool")

/// Recalibrating a synthetic body part: actuator misalignment responds to
/// TREAT_CALIBRATION, and a pass over the head also runs a system restore
/// for processor corruption. Only synthetic parts respond — the body gates
/// treatment by the part's biology.
/obj/item/multitool/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(!ishuman(M) || stance != I_HELP)
		return ..()
	var/mob/living/carbon/human/H = M
	var/obj/item/organ/external/E = H.get_organ(target_zone)
	if(!E || !(H.body.biology_of(E) & treatment_tag_biology(TREAT_CALIBRATION)))
		return ..()
	act_message(user, src, MSG_SELF(span_notice("You start recalibrating [H]'s [E.name].")), \
		MSG_OTHERS(span_notice("%U% plugs %T% into a diagnostic port on [H]'s [E.name] and starts recalibrating.")))
	task_start(/datum/task/timed/multitool_attack, user, H, receiver = src, E = E)
	return TRUE

/datum/task/timed/multitool_attack
	duration = 4 SECONDS
	complete_proc = /obj/item/multitool/proc/attack_timed_done
	var/obj/item/organ/external/E

/obj/item/multitool/proc/attack_timed_done(datum/task/timed/multitool_attack/task)
	var/mob/living/user = task.actor
	var/mob/living/carbon/human/H = task.target
	var/obj/item/organ/external/E = task.E
	var/treated = H.mend(TREAT_CALIBRATION, 30, E.organ_tag)
	if(E.organ_tag == BP_HEAD)
		treated += H.mend(TREAT_SYSTEM_RESTORE, 20, BP_HEAD)
	to_chat(user, treated ? span_notice("Calibration offsets corrected.") : span_notice("Everything already reads within tolerance."))
	return ITEM_INTERACT_SUCCESS

/obj/item/multitool/get_multitool()
	return src

/// Relation view: buffer (reads null once it is gone).
/obj/item/multitool/proc/buffer() as /obj/machinery/telecomms
	return buffer

/// Relation view: connecting (reads null once it is gone).
/obj/item/multitool/proc/connecting() as /obj/machinery/clonepod
	return connecting

/// Relation view: connectable (reads null once it is gone).
/obj/item/multitool/proc/connectable() as /obj/machinery
	return connectable
