/**
 * Multitool -- A multitool is used for hacking electronic devices.
 * TO-DO -- Using it as a power measurement tool for cables etc. Nannek.
 *
 */

/obj/item/multitool
	name = "multitool"
	desc = "Used for pulsing wires to test which to cut. Not recommended by doctors."
	description_info = "You can use this on airlocks or APCs to try to hack them without cutting wires."
	icon = 'icons/obj/device.dmi'
	icon_state = "multitool"
	force = 5.0
	w_class = ITEMSIZE_SMALL
	throwforce = 5.0
	throw_range = 15
	throw_speed = 3
	drop_sound = 'sound/items/drop/multitool.ogg'
	pickup_sound = 'sound/items/pickup/multitool.ogg'

	matter = list(MAT_STEEL = 50,MAT_GLASS = 20)

	var/mode_index = 1
	var/toolmode = MULTITOOL_MODE_STANDARD
	var/static/list/modes = list(MULTITOOL_MODE_STANDARD, MULTITOOL_MODE_INTCIRCUITS)

	var/obj/machinery/telecomms/buffer // simple machine buffer for device linkage
	var/obj/machinery/clonepod/connecting //same for cryopod linkage
	var/obj/machinery/connectable	//Used to connect machinery.
	var/weakref_wiring //Used to store weak references for integrated circuitry. This is now the Omnitool.
	toolspeed = 1
	tool_qualities = list(TOOL_MULTITOOL)

	var/uplink = FALSE

/obj/item/multitool/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	if(uplink)
		return

	if(selected_io)
		selected_io = null
		to_chat(user, span_notice("You clear the wired connection from the multitool."))
		update_icon()
		return

	update_icon()
	var/choice = tgui_alert(user, "What do you want to do with \the [src]?", "Multitool Menu", list("Switch Mode", "Clear Buffers", "Cancel"))
	switch(choice)
		if("Clear Buffers")
			to_chat(user,span_notice("You clear \the [src]'s memory."))
			buffer = null
			connecting = null
			connectable = null
			weakref_wiring = null
			accepting_refs = 0
			if(toolmode == MULTITOOL_MODE_INTCIRCUITS)
				accepting_refs = 1
		if("Switch Mode")
			mode_switch(user)
		else
			to_chat(user,span_notice("You lower \the [src]."))
			return

	update_icon()

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
/obj/item/multitool/alien/update_icon()
	if(accepting_refs)
		icon_state = "multitool_ref_scan"
		return
	icon_state = "multitool"

/// Recalibrating a synthetic body part: actuator misalignment responds to
/// TREAT_CALIBRATION, and a pass over the head also runs a system restore
/// for processor corruption. Only synthetic parts respond — the body gates
/// treatment by the part's biology.
/obj/item/multitool/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!ishuman(M) || user.a_intent != I_HELP)
		return ..()
	var/mob/living/carbon/human/H = M
	var/obj/item/organ/external/E = H.get_organ(target_zone)
	if(!E || !(H.body.biology_of(E) & treatment_tag_biology(TREAT_CALIBRATION)))
		return ..()
	user.visible_message(span_notice("[user] plugs \the [src] into a diagnostic port on [H]'s [E.name] and starts recalibrating."), \
		span_notice("You start recalibrating [H]'s [E.name]."))
	if(!do_after(user, 4 SECONDS, H))
		return ITEM_INTERACT_SUCCESS
	var/treated = H.mend(TREAT_CALIBRATION, 30, E.organ_tag)
	if(E.organ_tag == BP_HEAD)
		treated += H.mend(TREAT_SYSTEM_RESTORE, 20, BP_HEAD)
	to_chat(user, treated ? span_notice("Calibration offsets corrected.") : span_notice("Everything already reads within tolerance."))
	return ITEM_INTERACT_SUCCESS
