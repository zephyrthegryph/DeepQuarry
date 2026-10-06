#define TANK_DISPENSER_CAPACITY 10

/obj/structure/dispenser
	silicon_use = ROBOT_USE_HAND_ADJACENT
	name = "tank storage unit"
	desc = "A simple yet bulky storage device for gas tanks. Has room for up to ten oxygen tanks, and ten phoron tanks."
	icon = 'icons/obj/objects_vr.dmi'
	icon_state = "dispenser"
	density = TRUE
	anchored = TRUE
	w_class = ITEMSIZE_HUGE
	var/oxygentanks = TANK_DISPENSER_CAPACITY
	var/phorontanks = TANK_DISPENSER_CAPACITY


/obj/structure/dispenser/oxygen
	phorontanks = 0

/obj/structure/dispenser/phoron
	oxygentanks = 0


/obj/structure/dispenser/Initialize(mapload)
	. = ..()
	for(var/i in 1 to oxygentanks)
		new /obj/item/tank/oxygen(src)
	for(var/i in 1 to phorontanks)
		new /obj/item/tank/phoron(src)

/obj/structure/dispenser/proc/appearance_oxygen()
	return oxygentanks >= 1 ? min(oxygentanks, 4) : 0

/obj/structure/dispenser/proc/appearance_phoron()
	return phorontanks >= 1 ? min(phorontanks, 5) : 0

/// The look (the draw sweep: from its layers).
/obj/structure/dispenser/draw(datum/look/look)
	..()
	switch("[appearance_oxygen()]")
		if("1")
			look.overlay("oxygen-1")
		if("2")
			look.overlay("oxygen-2")
		if("3")
			look.overlay("oxygen-3")
		if("4")
			look.overlay("oxygen-4")
	switch("[appearance_phoron()]")
		if("1")
			look.overlay("phoron-1")
		if("2")
			look.overlay("phoron-2")
		if("3")
			look.overlay("phoron-3")
		if("4")
			look.overlay("phoron-4")
		if("5")
			look.overlay("phoron-5")

/obj/structure/dispenser/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/dispenser_open_ui,
		/datum/interaction/entry_item/dispenser_item/harm,
		/datum/interaction/entry_item/dispenser_item,
	)
	..()

/datum/interaction/entry_hand/dispenser_open_ui
	id = "dispenser_open_ui"
	name = "Use"
	effect = /atom/proc/interaction_open_ui

CAPABILITIES(/obj/structure/dispenser)
	interface("TankDispenser", state = nameof(GLOB.tgui_physical_state))
	op("phoron", ui_act("phoron"), then(PROC_REF(ui_act_phoron)))
	op("oxygen", ui_act("oxygen"), then(PROC_REF(ui_act_oxygen)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))

/obj/structure/dispenser/ui_data(datum/act/eval/A)
	return list("oxygen" = oxygentanks, "phoron" = phorontanks)

/// Old attackby: store a tank, or take a hit on harm intent.
/datum/interaction/entry_item/dispenser_item
	id = "dispenser_item"
	name = "Use"
	effect = /obj/structure/dispenser/proc/interaction_item

/// Combat mode: tanks still go in; anything else is refused without a word.
/datum/interaction/entry_item/dispenser_item/harm
	id = "dispenser_item_harm"
	stance = I_HURT

/obj/structure/dispenser/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	var/full
	if(istype(I, /obj/item/tank/oxygen) || istype(I, /obj/item/tank/air) || istype(I, /obj/item/tank/anesthetic))
		if(oxygentanks < TANK_DISPENSER_CAPACITY)
			oxygentanks++
		else
			full = TRUE
	else if(istype(I, /obj/item/tank/phoron))
		if(phorontanks < TANK_DISPENSER_CAPACITY)
			phorontanks++
		else
			full = TRUE
	else if(interaction.stance != I_HURT)
		to_chat(user, span_notice("[I] does not fit into [src]."))
		return TRUE
	else
		return TRUE

	if(full)
		to_chat(user, span_notice("[src] can't hold any more of [I]."))
		return TRUE

	if(!user.unEquip(I, target = src))
		return TRUE
	to_chat(user, span_notice("You put [I] in [src]."))
	changed(src)
	return TRUE

/obj/structure/dispenser/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	set_anchored(!anchored)
	to_chat(user, span_notice("You [anchored ? "wrench [src] into place" : "lean down and unwrench [src]"]."))
	return OP_OK

#undef TANK_DISPENSER_CAPACITY

/obj/structure/dispenser/proc/ui_act_phoron(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tank/phoron/tank = locate_within(src, /obj/item/tank/phoron)
	if(tank && Adjacent(user))
		user.put_in_hands(tank)
		phorontanks--
	. = TRUE
	play_sfx(src, SFX_ITEMS_DROP_GASCAN)

/obj/structure/dispenser/proc/ui_act_oxygen(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tank/tank = null
	for(var/obj/item/tank/T in contents_of(src))
		if(istype(T, /obj/item/tank/oxygen) || istype(T, /obj/item/tank/air) || istype(T, /obj/item/tank/anesthetic))
			tank = T
			break
	if(tank && Adjacent(user))
		user.put_in_hands(tank)
		oxygentanks--
	. = TRUE
	play_sfx(src, SFX_ITEMS_DROP_GASCAN)
