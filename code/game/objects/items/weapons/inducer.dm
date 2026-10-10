/obj/item/inducer
	name = "industrial inducer"
	desc = "A tool for inductively charging internal power cells."
	icon = 'icons/obj/tools_vr.dmi'
	icon_state = "inducer-engi"
	item_state = "inducer-engi"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_vr.dmi',
	)
	force = 7

	var/powertransfer = 1000 //Transfer per time when charging something
	var/cell_type = /obj/item/cell/high //Type of cell to spawn in it
	var/charge_guns = FALSE //Can it charge guns?

	var/obj/item/cell/cell
	var/recharging = FALSE
	var/opened = FALSE

TRACKED(/obj/item/inducer, opened)

/obj/item/inducer/unloaded
	cell_type = null
	opened = TRUE

/obj/item/inducer/Initialize(mapload)
	. = ..()
	if(!cell && cell_type)
		rel_set(src, nameof(cell), new cell_type(src)) // ALLOW(decl): cell_type is picked per instance

/obj/item/inducer/proc/induce(obj/item/cell/target, coefficient)
	var/totransfer = min(cell.charge,(powertransfer * coefficient))
	var/transferred = target.give(totransfer)
	cell.use(transferred)

/obj/item/inducer/get_cell()
	return cell

/obj/item/inducer/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(stance == I_HURT)
		return ..()
	else
		return ITEM_INTERACT_FAILURE //No accidental bludgeons!

/obj/item/inducer/afterattack(atom/A, mob/living/carbon/user, proximity, click_parameters, stance = I_HURT)
	if(stance == I_HURT)
		return ..()

	if(cantbeused(user))
		return

	if(recharge(A, user))
		return

	return ..()

/obj/item/inducer/proc/cantbeused(mob/user)
	if(!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You don't have the dexterity to use [src]!"))
		return TRUE

	if(!cell)
		to_chat(user, span_warning("[src] doesn't have a power cell installed!"))
		return TRUE

	if(!cell.charge)
		to_chat(user, span_warning("[src]'s battery is dead!"))
		return TRUE
	return FALSE


/// Old attackby.
/obj/item/inducer/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/cell))
		if(opened)
			if(!cell)
				to_chat(user, span_notice("You insert [W] into [src]."))
				if(!move_into(src, nameof(src.cell), W, user))
					return OP_PASS
				return OP_PASS
			else
				to_chat(user, span_warning("[src] already has \a [cell] installed!"))
				return OP_PASS

	if(cantbeused(user))
		return OP_PASS

	if(recharge(W, user))
		return OP_PASS

	return OP_DECLINE

CAPABILITIES(/obj/item/inducer)
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	// Charging a cell in two-second pulses until it is full, the inducer runs dry or the user stops.
	op("induce", ai(), takes("charged", "charging", "coefficient", "beam", "filter", "progress"), wait(2 SECONDS, keeps = HELD | TARGET_PRESENT | ALIVE | STAY, repeats = PROC_REF(recharge_more), after_step = PROC_REF(recharge_pulse)), on_interrupt(PROC_REF(recharge_end)), then(PROC_REF(recharge_end)))

/obj/item/inducer/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 50, 1)
	set_opened(!opened)
	to_chat(user, span_notice("You [opened ? "open" : "close"] the battery compartment."))
	return OP_OK

/obj/item/inducer/proc/recharge(atom/movable/A, mob/user)
	if(!isturf(A) && user.loc == A)
		return FALSE
	if(recharging)
		return TRUE
	else
		recharging = TRUE

	if(istype(A, /obj/item/gun/energy) && !charge_guns)
		to_chat(user, span_warning("Error: Device is unable to interface with weapons."))
		recharging = FALSE
		return FALSE

	//The cell we hopefully eventually find
	var/obj/item/cell/C

	//Synthetic humanoids
	if(ishuman(A))
		var/mob/living/carbon/human/H = A
		if(HAS_SYNTHETIC_BIOLOGY(H))
			C = new /obj/item/cell/standin(null, H) // o o f

	//Borg frienbs
	else if(isrobot(A))
		var/mob/living/silicon/robot/R = A
		C = R.cell

	//Can set different coefficients per item if you want
	var/coefficient = 1

	//Last ditch effort
	var/obj/O //For updating icons, just in case they have a battery meter icon
	if(!C && isobj(A))
		O = A
		C = O.get_cell()

	if(C)

		if(C.charge >= C.maxcharge)
			to_chat(user, span_notice("[A] is fully charged ([round(C.charge)] / [C.maxcharge])!"))
			recharging = FALSE
			return TRUE
		act_message(user, src, MSG_SELF(span_notice("You start recharging [A] with %T%.")), MSG_OTHERS(span_notice("%U% starts recharging [A] with %T%.")))

		var/datum/beam/charge_beam = user.Beam(A, icon_state = "rped_upgrade", time = 20 SECONDS)
		var/filter = filter(type = "outline", size = 1, color = "#22AAFF")
		A.filters += filter

		var/datum/op_result/started = perform_op(user, src, "induce", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("charged" = A, "charging" = C, "coefficient" = coefficient, "beam" = charge_beam, "filter" = filter, "progress" = list("done_any" = FALSE)))
		if(!started || (started.outcome & ACT_REFUSED))
			recharge_finish(user, A, charge_beam, filter, FALSE)
		return TRUE
	else //Couldn't find a cell
		to_chat(user, span_warning("Error unable to interface with device."))

	recharging = FALSE

/// Another pulse follows while the cell being charged is not full and the inducer still has charge.
/obj/item/inducer/proc/recharge_more(datum/act/op/A)
	var/obj/item/cell/C = A.arg("charging")
	return !QDELETED(C) && cell?.charge && C.charge < C.maxcharge

/// One pulse: charge moves from the inducer's cell to the one being charged.
/obj/item/inducer/proc/recharge_pulse(datum/act/op/A)
	if(!cell?.charge)
		return
	var/obj/item/cell/C = A.arg("charging")
	if(QDELETED(C))
		return
	induce(C, A.arg("coefficient"))
	var/atom/charged = A.arg("charged")
	if(charged)
		fx_sparks(charged, 5, FALSE)
	var/list/progress = A.arg("progress")
	progress["done_any"] = TRUE

/obj/item/inducer/proc/recharge_end(datum/act/op/A)
	var/list/progress = A.arg("progress")
	recharge_finish(A.actor, A.arg("charged"), A.arg("beam"), A.arg("filter"), progress?["done_any"])
	return OP_OK

/// The charging is over (done, stopped or never started): the beam and the outline go, and the user hears of a charge that happened.
/obj/item/inducer/proc/recharge_finish(mob/user, atom/A, datum/beam/charge_beam, filter, done_any)
	spent(charge_beam)
	if(A)
		A.filters -= filter
	if(done_any && user) // Only show a message if we succeeded at least once
		act_message(user, null, MSG_SELF(span_notice("You recharged [A]!")), MSG_OTHERS(span_notice("%U% recharged [A]!")))
	recharging = FALSE

/// Old attack_self.
/obj/item/inducer/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(opened && cell)
		act_message(user, src, MSG_SELF(span_notice("You remove [cell].")), MSG_OTHERS(span_notice("%U% removes [cell] from %T%!")))
		user.put_in_hands(cell)
		rel_take(src, nameof(cell))
	return TRUE

/obj/item/inducer/examine(mob/living/M)
	. = ..()
	if(cell)
		. += span_notice("Its display shows: [round(cell.charge)] / [cell.maxcharge].")
	else
		. += span_notice("Its display is dark.")
	if(opened)
		. += span_notice("Its battery compartment is open.")

/obj/item/inducer/proc/appearance_compartment()
	if(!opened)
		return ""
	return cell ? "bat" : "nobat"

/// The look (the draw sweep: from its layers).
/obj/item/inducer/draw(datum/look/look)
	..()
	switch("[appearance_compartment()]")
		if("nobat")
			look.overlay("inducer-nobat")
		if("bat")
			look.overlay("inducer-bat")

//////// Variants
/obj/item/inducer/sci
	name = "inducer"
	desc = "A tool for inductively charging internal power cells. This one has a science color scheme, and is less potent than its engineering counterpart."
	icon_state = "inducer-sci"
	item_state = "inducer-sci"
	cell_type = null
	powertransfer = 500
	opened = TRUE

/obj/item/inducer/syndicate
	name = "suspicious inducer"
	desc = "A tool for inductively charging internal power cells. This one has a suspicious colour scheme, and seems to be rigged to transfer charge at a much faster rate."
	icon_state = "inducer-syndi"
	item_state = "inducer-syndi"
	powertransfer = 2000
	cell_type = /obj/item/cell/super
	charge_guns = TRUE

/obj/item/inducer/hybrid
	name = "hybrid-tech inducer"
	desc = "A tool for inductively charging internal power cells. This one has some flashy bits and recharges devices slower, but seems to recharge itself between uses."
	icon_state = "inducer-hybrid"
	item_state = "inducer-hybrid"
	powertransfer = 250
	cell_type = /obj/item/cell/void
	charge_guns = TRUE

// A 'human stand-in' cell for recharging 'nutrition' on synthetic humans (wow this is terrible! \o/)
#define NUTRITION_COEFF 0.05 // 1000 charge = 50 nutrition at 0.05
/obj/item/cell/standin
	name = "don't spawn this"
	desc = "this is for weird code use, don't spawn it!!!"

	charge = 100
	maxcharge = 100
	item_flags = ABSTRACT

	var/mob/living/carbon/human/hume

CAPABILITIES(/obj/item/cell/standin)
	param(nameof(hume), pos = 1)

// ALLOW(init/INSTANCE_STATE): a stand-in cell charges from its human's nutrition, over its parents' charge, and lasts twenty seconds
/obj/item/cell/standin/Initialize(mapload)
	. = ..()
	if(!istype(hume))
		return INITIALIZE_HINT_QDEL
	set_charge(hume.nutrition)
	set_maxcharge(initial(hume.nutrition))
	expire(20 SECONDS)


/obj/item/cell/standin/give(amount)
	. = ..(amount * NUTRITION_COEFF) //Shrink amount to store
	hume().adjust_nutrition(.) //Add the amount we really stored
	. /= NUTRITION_COEFF //Inflate amount to take from the giver

#undef NUTRITION_COEFF

// Various sideways-defined get_cells
/obj/mecha/get_cell()
	return cell

/obj/vehicle/get_cell()
	return cell

/obj/item/inducer/ownership()
	. = ..()
	. += owns(nameof(cell), policy = OWN_CONTAINED)

/// Relation view: hume (reads null once it is gone).
/obj/item/cell/standin/proc/hume() as /mob/living/carbon/human
	return hume
