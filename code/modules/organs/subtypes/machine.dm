/obj/item/organ/internal/cell
	name = "microbattery"
	desc = "A small, powerful cell for use in fully prosthetic bodies."
	icon_state = "scell"
	organ_tag = O_CELL
	parent_organ = BP_TORSO
	vital = TRUE
	var/defib_timer = 1 // This sits in the brain organ slot, but is not a brain.

/obj/item/organ/internal/cell/Initialize(mapload, internal)
	robotize()
	. = ..()

/obj/item/organ/internal/cell/replaced()
	..()
	// This is very ghetto way of rebooting an IPC. TODO better way.
	if(owner && owner.stat == DEAD)
		owner.set_stat(CONSCIOUS)
		owner.visible_message(span_danger("\The [owner] twitches visibly!"))

/obj/item/organ/internal/cell/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	owner?.adjust_nutrition(-rand(10 / severity, 50 / severity))

/obj/item/organ/internal/cell/machine/handle_organ_proc_special()
	..()
	if(owner && owner.stat != DEAD)
		owner.bodytemperature += round(owner.robobody_count * 0.5, 0.1)

	return

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

/obj/item/organ/internal/mmi_holder/Destroy()
	if(stored_mmi && (stored_mmi.loc == src))
		qdel(stored_mmi)
		stored_mmi = null
	return ..()

/obj/item/organ/internal/mmi_holder/Initialize(mapload, internal, obj/item/mmi/installed)
	. = ..(mapload, internal)
	if(!ishuman(loc) || ismannequin(loc))
		return
	if(installed)
		stored_mmi = installed
	else
		stored_mmi = new brain_type(src)
	return INITIALIZE_HINT_LATELOAD

/obj/item/organ/internal/mmi_holder/LateInitialize()
	update_from_mmi()

// This sits in the brain organ slot, but is not a brain. Posibrains and dronecores aren't brains either.
/obj/item/organ/internal/mmi_holder/proc/tick_defib_timer()
	return

/obj/item/organ/internal/mmi_holder/proc/get_control_efficiency()
	. = max(0, 1 - round(damage / max_damage, 0.1))

	return .

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

	if(owner && owner.stat == DEAD)
		owner.set_stat(CONSCIOUS)
		GLOB.dead_mob_list -= owner
		GLOB.living_mob_list |= owner
		owner.visible_message(span_danger("\The [owner] twitches visibly!"))

/obj/item/organ/internal/mmi_holder/removed(mob/living/user)

	if(stored_mmi)
		. = stored_mmi // Code
		stored_mmi.forceMove(drop_location())
		if(owner.mind)
			var/datum/component/mind_host/host = get_mind_host(stored_mmi)
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

