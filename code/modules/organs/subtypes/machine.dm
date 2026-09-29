/obj/item/organ/internal/cell
	name = "microbattery"
	desc = "A small, powerful cell for use in fully prosthetic bodies."
	icon_state = "scell"
	organ_tag = O_CELL
	parent_organ = BP_TORSO
	vital = TRUE

/obj/item/organ/internal/cell/Initialize(mapload, internal)
	robotize()
	. = ..()

/obj/item/organ/internal/cell/replaced()
	..()
	// This is very ghetto way of rebooting an IPC. TODO better way.
	if(owner && owner.is_dead() && owner.return_from_death("power cell replaced", src) == TRUE)
		owner.visible_message(span_danger("\The [owner] twitches visibly!"))

/// A pulse drains the owner's charge.
/obj/item/organ/internal/cell/organ_emp(datum/damage_packet/packet)
	..()
	owner?.adjust_nutrition(-rand(10 / packet.severity, 50 / packet.severity))

/obj/item/organ/internal/cell/machine/handle_organ_proc_special()
	..()
	// D25: the power cell is the one source of chassis waste heat.
	apply_robobody_heat()

// Used for an MMI or posibrain being installed into a human.
/obj/item/organ/internal/mmi_holder
	name = "brain interface"
	organ_tag = O_BRAIN
	parent_organ = BP_HEAD
	vital = TRUE
	var/brain_type = /obj/item/mmi
	var/obj/item/mmi/stored_mmi
	robotic = ORGAN_ASSISTED
	butcherable = FALSE

DECLARE_REF(/obj/item/organ/internal/mmi_holder, "stored_mmi", OWNED, null)

/obj/item/organ/internal/mmi_holder/Initialize(mapload, internal, obj/item/mmi/installed)
	. = ..(mapload, internal)
	if(!ishuman(owner) || ismannequin(owner))
		return
	if(installed)
		stored_mmi = installed
		installed.forceMove(src)
	else
		stored_mmi = new brain_type(src)
	return INITIALIZE_HINT_LATELOAD

/// THE way an MMI goes into a human's brain slot (surgery, vore reform): born in `target`, a
/// holder of the MMI's kind takes the slot and stores `M`. Returns the holder.
/proc/install_mmi_holder(mob/living/carbon/human/target, obj/item/mmi/M)
	var/holder_type = /obj/item/organ/internal/mmi_holder
	if(istype(M, /obj/item/mmi/digital/posibrain/nano))
		holder_type = /obj/item/organ/internal/mmi_holder/posibrain/nano
	else if(istype(M, /obj/item/mmi/digital/posibrain))
		holder_type = /obj/item/organ/internal/mmi_holder/posibrain
	else if(istype(M, /obj/item/mmi/digital/robot))
		holder_type = /obj/item/organ/internal/mmi_holder/robot
	return new holder_type(target, 1, M)

/obj/item/organ/internal/mmi_holder/LateInitialize()
	update_from_mmi()


/obj/item/organ/internal/mmi_holder/proc/update_from_mmi()
	if(!owner) return

	// An assisted interface keeps real brain tissue in its MMI; the mind stays
	// in the body until the interface is removed.
	if(!istype(stored_mmi, /obj/item/mmi/digital) && !stored_mmi.brainobj)
		stored_mmi.set_brain(new /obj/item/organ/internal/brain(stored_mmi))
		stored_mmi.name = "[initial(stored_mmi.name)] ([owner.real_name])"

	name = stored_mmi.name
	desc = stored_mmi.desc
	icon = stored_mmi.icon

	stored_mmi.icon_state = "mmi_full"
	icon_state = stored_mmi.icon_state

	if(owner && owner.is_dead() && owner.return_from_death("MMI installed", stored_mmi) == TRUE)
		owner.visible_message(span_danger("\The [owner] twitches visibly!"))

/obj/item/organ/internal/mmi_holder/removed(mob/living/user)

	if(stored_mmi)
		. = stored_mmi // Code
		stored_mmi.forceMove(drop_location())
		if(owner.mind)
			var/datum/mind_host/host = get_mind_host(stored_mmi)
			var/mob/living/carbon/brain/view = host?.receive_mind(owner.mind, "brain interface removed from [owner]")
			view?.reset_perspective()
	..()

	var/mob/living/holder_mob = loc
	if(istype(holder_mob))
		holder_mob.drop_from_inventory(src)
	qdel(src)
/obj/item/organ/internal/mmi_holder/posibrain
	name = "positronic brain interface"
	brain_type = /obj/item/mmi/digital/posibrain
	robotic = ORGAN_ROBOT

/obj/item/organ/internal/mmi_holder/posibrain/update_from_mmi()
	..()
	stored_mmi.icon_state = "posibrain-occupied"
	icon_state = stored_mmi.icon_state

/obj/item/organ/internal/mmi_holder/robot
	name = "digital brain interface"
	brain_type = /obj/item/mmi/digital/robot
	robotic = ORGAN_ROBOT

/obj/item/organ/internal/mmi_holder/robot/update_from_mmi()
	..()
	stored_mmi.icon_state = "mainboard"
	icon_state = stored_mmi.icon_state


// MED-6: this organ has work every periodic_step(), so the organs life stage stays awake for it.
/obj/item/organ/internal/cell/machine/life_step_idle()
	return FALSE

