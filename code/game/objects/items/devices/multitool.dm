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
	drop_sound = 'sound/items/drop/multitool.ogg'
	pickup_sound = 'sound/items/pickup/multitool.ogg'


	var/mode_index = 1
	var/toolmode = MULTITOOL_MODE_STANDARD
	var/static/list/modes = list(MULTITOOL_MODE_STANDARD, MULTITOOL_MODE_INTCIRCUITS)

	var/buffer_handle // simple machine buffer for device linkage
	var/connecting_handle //same for cryopod linkage
	var/connectable_handle	//Used to connect machinery.
	var/ref_wiring //An IC ref (ic_ref()) for integrated circuitry. This is now the Omnitool.
	toolspeed = 1
	tool_qualities = list(TOOL_MULTITOOL)

	var/uplink = FALSE

DECLARE_INTERACTIONS(/obj/item/multitool, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/multitool/proc/interaction_self(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(uplink)
		return

	if(selected_io())
		selected_io_handle = null
		to_chat(user, span_notice("You clear the wired connection from the multitool."))
		update_icon()
		return

	update_icon()
	om_ask(user, /datum/om/prompt/choice, PROC_REF(menu_chosen), message = "What do you want to do with \the [src]?", title = "Multitool Menu", choices = list("Switch Mode", "Clear Buffers", "Cancel"), buttons = TRUE, ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/multitool/proc/menu_chosen(datum/om/prompt/choice/ask)
	var/mob/living/user = ask.answerer
	switch(ask.choice)
		if("Clear Buffers")
			to_chat(user,span_notice("You clear \the [src]'s memory."))
			buffer_handle = null
			connecting_handle = null
			connectable_handle = null
			ref_wiring = null
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
/obj/item/multitool/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(!ishuman(M) || stance != I_HELP)
		return ..()
	var/mob/living/carbon/human/H = M
	var/obj/item/organ/external/E = H.get_organ(target_zone)
	if(!E || !(H.body.biology_of(E) & treatment_tag_biology(TREAT_CALIBRATION)))
		return ..()
	user.visible_message(span_notice("[user] plugs \the [src] into a diagnostic port on [H]'s [E.name] and starts recalibrating."), \
		span_notice("You start recalibrating [H]'s [E.name]."))
	om_task_start(/datum/om/task/timed/multitool_attack, user, H, receiver = src, E = E)
	return TRUE

/datum/om/task/timed/multitool_attack
	duration = 4 SECONDS
	complete_proc = /obj/item/multitool/proc/attack_timed_done
	var/obj/item/organ/external/E

/obj/item/multitool/proc/attack_timed_done(datum/om/task/timed/multitool_attack/task)
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

/// LC-refs: buffer -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/multitool/proc/buffer() as /obj/machinery/telecomms
	return om_resolve(buffer_handle)

/// LC-refs: connecting -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/multitool/proc/connecting() as /obj/machinery/clonepod
	return om_resolve(connecting_handle)

/// LC-refs: connectable -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/multitool/proc/connectable() as /obj/machinery
	return om_resolve(connectable_handle)
