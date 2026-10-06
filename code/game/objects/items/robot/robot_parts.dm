/obj/item/robot_parts
	name = "robot parts"
	icon = 'icons/obj/robot_parts.dmi'
	item_state = "buildpipe"
	icon_state = "blank"
	slot_flags = SLOT_BELT
	var/list/part = null // Order of args is important for installing robolimbs.
	var/sabotaged = 0 //Emagging limbs can have repercussions when installed as prosthetics.
	var/model_info
	dir = SOUTH

/obj/item/robot_parts/l_arm
	name = "cyborg left arm"
	desc = "A skeletal limb wrapped in pseudomuscles, with a low-conductivity case."
	icon_state = "l_arm"
	part = list(BP_L_ARM, BP_L_HAND)
	model_info = 1

/obj/item/robot_parts/r_arm
	name = "cyborg right arm"
	desc = "A skeletal limb wrapped in pseudomuscles, with a low-conductivity case."
	icon_state = "r_arm"
	part = list(BP_R_ARM, BP_R_HAND)
	model_info = 1

/obj/item/robot_parts/l_leg
	name = "cyborg left leg"
	desc = "A skeletal limb wrapped in pseudomuscles, with a low-conductivity case."
	icon_state = "l_leg"
	part = list(BP_L_LEG, BP_L_FOOT)
	model_info = 1

/obj/item/robot_parts/r_leg
	name = "cyborg leg"
	desc = "A skeletal limb wrapped in pseudomuscles, with a low-conductivity case."
	icon_state = "r_leg"
	part = list(BP_R_LEG, BP_R_FOOT)
	model_info = 1

/obj/item/robot_parts/chest
	name = "cyborg chest"
	desc = "A heavily reinforced case containing cyborg logic boards, with space for a standard power cell."
	icon_state = "chest"
	part = list(BP_GROIN,BP_TORSO)
	var/wires_const = 0.0
	var/obj/item/cell/cell = null

/obj/item/robot_parts/head
	name = "cyborg head"
	desc = "A standard reinforced braincase, with spine-plugged neural socket and sensor gimbals."
	icon_state = "head"
	part = list(BP_HEAD)
	var/obj/item/flash/flash1 = null
	var/obj/item/flash/flash2 = null

/obj/item/robot_parts/robot_suit
	name = "endoskeleton"
	desc = "A complex metal backbone with standard limb sockets and pseudomuscle anchors."
	icon_state = "robo_suit"
	var/obj/item/robot_parts/l_arm/l_arm = null
	var/obj/item/robot_parts/r_arm/r_arm = null
	var/obj/item/robot_parts/l_leg/l_leg = null
	var/obj/item/robot_parts/r_leg/r_leg = null
	var/obj/item/robot_parts/chest/chest = null
	var/obj/item/robot_parts/head/head = null
	var/created_name = ""

/obj/item/robot_parts/robot_suit/draw(datum/look/look)
	..()
	if(src.l_arm)
		look.overlay("l_arm+o")
	if(src.r_arm)
		look.overlay("r_arm+o")
	if(src.chest)
		look.overlay("chest+o")
	if(src.l_leg)
		look.overlay("l_leg+o")
	if(src.r_leg)
		look.overlay("r_leg+o")
	if(src.head)
		look.overlay("head+o")

/obj/item/robot_parts/robot_suit/proc/check_completion()
	if(src.l_arm && src.r_arm)
		if(src.l_leg && src.r_leg)
			if(src.chest && src.head)
				feedback_inc("cyborg_frames_built",1)
				return 1
	return 0

CAPABILITIES(/obj/item/robot_parts/robot_suit)
	// the old attackby: limbs, chest, head, then the MMI that finishes it; steel arms a bare frame (the hit goes on after)
	op("build", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	// a pen names the robot it will become
	op("name", item(/obj/item/pen), label("Name"), priority(OP_PRIORITY_PART + 1),
		asks(/datum/prompt/text, fields = list("title" = "name", "question" = "Enter new robot name", "default" = computed(PROC_REF(current_name)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0)),
		then(PROC_REF(robot_named)))

/obj/item/robot_parts/robot_suit/proc/current_name(datum/act/op/A)
	return created_name

/obj/item/robot_parts/robot_suit/proc/robot_named(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(R?.value)
		src.created_name = R.value
	return OP_PASS

/// Old attackby.
/obj/item/robot_parts/robot_suit/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/stack/material) && W.get_material_name() == MAT_STEEL && !l_arm && !r_arm && !l_leg && !r_leg && !chest && !head)
		var/obj/item/stack/material/M = W
		if (M.use(1))
			var/obj/item/secbot_assembly/ed209_assembly/B = new /obj/item/secbot_assembly/ed209_assembly
			B.forceMove(get_turf(src))
			to_chat(user, span_notice("You armed the robot frame."))
			if (user.get_inactive_hand()==src)
				user.remove_from_mob(src)
				user.put_in_inactive_hand(B)
			consume(src, user)
		else
			to_chat(user, span_warning("You need one sheet of metal to arm the robot frame."))
	if(istype(W, /obj/item/robot_parts/l_leg))
		if(src.l_leg)	return OP_PASS
		if(!move_into(src, nameof(src.l_leg), W, user))
			return OP_PASS
		src.update_icon()

	if(istype(W, /obj/item/robot_parts/r_leg))
		if(src.r_leg)	return OP_PASS
		if(!move_into(src, nameof(src.r_leg), W, user))
			return OP_PASS
		src.update_icon()

	if(istype(W, /obj/item/robot_parts/l_arm))
		if(src.l_arm)	return OP_PASS
		if(!move_into(src, nameof(src.l_arm), W, user))
			return OP_PASS
		src.update_icon()

	if(istype(W, /obj/item/robot_parts/r_arm))
		if(src.r_arm)	return OP_PASS
		if(!move_into(src, nameof(src.r_arm), W, user))
			return OP_PASS
		src.update_icon()

	if(istype(W, /obj/item/robot_parts/chest))
		if(src.chest)	return OP_PASS
		if(W:wires_const && W:cell)
			if(!move_into(src, nameof(src.chest), W, user))
				return OP_PASS
			src.update_icon()
		else if(!W:wires_const)
			to_chat(user, span_warning("You need to attach wires_const to it first!"))
		else
			to_chat(user, span_warning("You need to attach a cell to it first!"))

	if(istype(W, /obj/item/robot_parts/head))
		if(src.head)	return OP_PASS
		if(W:flash2 && W:flash1)
			if(!move_into(src, nameof(src.head), W, user))
				return OP_PASS
			src.update_icon()
		else
			to_chat(user, span_warning("You need to attach a flash to it first!"))

	if(istype(W, /obj/item/mmi))
		var/obj/item/mmi/M = W
		if (isshell(user) && istype(W, /obj/item/mmi/inert/ai_remote))
			to_chat(user, span_warning("Your hardware prohibits you from self-replicating."))
			return OP_PASS
		if(check_completion())
			if(!istype(loc,/turf))
				to_chat(user, span_warning("You can't put \the [W] in, the frame has to be standing on the ground to be perfectly precise."))
				return OP_PASS
			var/mob/living/carbon/brain/occupant = M.get_occupant()
			if(!istype(W, /obj/item/mmi/inert))
				if(!occupant)
					to_chat(user, span_warning("Sticking an empty [W] into the frame would sort of defeat the purpose."))
					return OP_PASS
				if(!occupant.key)
					var/ghost_can_reenter = 0
					if(occupant.mind)
						for(var/mob/observer/dead/G in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
							if(G.can_reenter_corpse && G.mind == occupant.mind)
								ghost_can_reenter = 1 //May come in use again at another point.
								to_chat(user, span_notice("\The [W] is completely unresponsive; though it may be able to auto-resuscitate.")) //Jamming a ghosted brain into a borg is likely detrimental, and may result in some problems.
								return OP_PASS
					if(!ghost_can_reenter)
						to_chat(user, span_notice("\The [W] is completely unresponsive; there's no point."))
						return OP_PASS

				if(occupant.stat == DEAD)
					to_chat(user, span_warning("Sticking a dead [W] into the frame would sort of defeat the purpose."))
					return OP_PASS

				if(jobban_isbanned(occupant, JOB_CYBORG))
					to_chat(user, span_warning("This [W] does not seem to fit."))
					return OP_PASS

			var/mob/living/silicon/robot/O = new /mob/living/silicon/robot(get_turf(loc), FALSE, TRUE)
			if(!O)	return OP_PASS

			if(!move_into(O, nameof(O.mmi), W, user))
				return OP_PASS
			O.post_mmi_setup()
			O.invisibility = INVISIBILITY_NONE
			O.custom_name = created_name
			O.updatename("Default")

			var/datum/mind_host/host = get_mind_host(M)
			if(host?.release_mind(O, "borged by [key_name(user)]"))
				if(O.mind && O.mind.special_role)
					O.mind.store_memory("In case you look at this after being borged, the objectives are only here until I find a way to make them not show up for you, as I can't simply delete them without screwing up round-end reporting. --NeoFite")
				for(var/datum/language/L in O.identity().languages)
					O.add_language(L.name)
			O.job = JOB_CYBORG
			var/obj/item/cell/chest_cell = own_take(chest, nameof(chest.cell)) // detach from the chest first: set_cell() adopts it
			chest_cell?.forceMove(O) // the borg's cell is CONTAINED
			O.set_cell(chest_cell)
			W.forceMove(O)//Should fix cybros run time erroring when blown up. It got deleted before, along with the frame.

			feedback_inc("cyborg_birth",1)

			consume(src, user)
		else
			to_chat(user, span_warning("The MMI must go in after everything else!"))

	return OP_PASS

CAPABILITIES(/obj/item/robot_parts/chest)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/robot_parts/chest/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/cell))
		if(src.cell)
			to_chat(user, span_warning("You have already inserted a cell!"))
			return OP_PASS
		else
			if(!move_into(src, nameof(src.cell), W, user))
				return OP_PASS
			to_chat(user, span_notice("You insert the cell!"))
	if(istype(W, /obj/item/stack/cable_coil))
		if(src.wires_const)
			to_chat(user, span_warning("You have already inserted wire!"))
			return OP_PASS
		else
			var/obj/item/stack/cable_coil/coil = W
			coil.use(1)
			src.wires_const = 1.0
			to_chat(user, span_notice("You insert the wire!"))
	return OP_PASS

CAPABILITIES(/obj/item/robot_parts/head)
	// an infrared sensor starts a TV camera (tvcamera.dm); a flash goes into an eye socket (a cyborg's flash is its own module)
	op("tv_sensor", item(/obj/item/assembly/infra), label("Add sensor"), then(PROC_REF(interaction_item)))
	op("insert_flash", item(/obj/item/flash), label("Insert flash"), when(cond_not(req(/mob/living/silicon/robot, of = ON_ACTOR))), then(PROC_REF(head_insert_flash)))
	op("insert_own_flash", item(/obj/item/flash), label("Insert flash"), when(req(/mob/living/silicon/robot, of = ON_ACTOR)), then(PROC_REF(own_flash_refused)))

/// A cyborg's flash is its own module.
/obj/item/robot_parts/head/proc/own_flash_refused(datum/act/op/A)
	to_chat(A.actor, span_warning("How do you propose to do that?"))
	return OP_PASS

/// Old attackby's flash branch.
/obj/item/robot_parts/head/proc/head_insert_flash(datum/act/op/A)
	add_flashes(A.held, A.actor)
	return OP_PASS

/obj/item/robot_parts/head/proc/add_flashes(obj/item/W as obj, mob/user as mob) //Made into a seperate proc to avoid copypasta
	if(src.flash1 && src.flash2)
		to_chat(user, span_notice("You have already inserted the eyes!"))
		return
	else if(src.flash1)
		if(!move_into(src, nameof(src.flash2), W, user))
			return
		to_chat(user, span_notice("You insert the flash into the eye socket!"))
	else
		if(!move_into(src, nameof(src.flash1), W, user))
			return
		to_chat(user, span_notice("You insert the flash into the eye socket!"))


CAPABILITIES(/obj/item/robot_parts)
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

/obj/item/robot_parts/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(sabotaged)
		to_chat(user, span_warning("[src] is already sabotaged!"))
	else
		to_chat(user, span_warning("You short out the safeties."))
		sabotaged = 1
		return OP_OK
	return OP_DECLINE

/obj/item/robot_parts/chest/ownership()
	. = ..()
	. += owns(nameof(cell), policy = OWN_CONTAINED)
/obj/item/robot_parts/head/ownership()
	. = ..()
	. += owns(nameof(flash1), policy = OWN_CONTAINED)
	. += owns(nameof(flash2), policy = OWN_CONTAINED)
/obj/item/robot_parts/robot_suit/ownership()
	. = ..()
	. += owns(nameof(l_arm), policy = OWN_CONTAINED)
	. += owns(nameof(r_arm), policy = OWN_CONTAINED)
	. += owns(nameof(l_leg), policy = OWN_CONTAINED)
	. += owns(nameof(r_leg), policy = OWN_CONTAINED)
	. += owns(nameof(chest), policy = OWN_CONTAINED)
	. += owns(nameof(head), policy = OWN_CONTAINED)
