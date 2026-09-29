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
	update_icon()

/obj/structure/dispenser/update_icon()
	cut_overlays()
	switch(oxygentanks)
		if(1 to 3)	add_overlay("oxygen-[oxygentanks]")
		if(4 to INFINITY) add_overlay("oxygen-4")
	switch(phorontanks)
		if(1 to 4)	add_overlay("phoron-[phorontanks]")
		if(5 to INFINITY) add_overlay("phoron-5")

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

DECLARE_UI_STATE(/obj/structure/dispenser, GLOB.tgui_physical_state)

DECLARE_UI(/obj/structure/dispenser, "TankDispenser")

UI_DATA_REPLACE(/obj/structure/dispenser, "oxygen=oxygentanks", "phoron=phorontanks")

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
	update_icon()
	return TRUE

/obj/structure/dispenser/wrench_act(mob/user, obj/item/I)
	set_anchored(!anchored)
	to_chat(user, span_notice("You [anchored ? "wrench [src] into place" : "lean down and unwrench [src]"]."))
	return TRUE

#undef TANK_DISPENSER_CAPACITY

UI_ACT(/obj/structure/dispenser, "phoron", ui_act_phoron)
UI_ACT_PROC(/obj/structure/dispenser, ui_act_phoron)
	var/obj/item/tank/phoron/tank = locate_within(src, /obj/item/tank/phoron)
	if(tank && Adjacent(ui.user))
		ui.user.put_in_hands(tank)
		phorontanks--
	. = TRUE
	play_sfx(src, SFX_ITEMS_DROP_GASCAN)
	update_icon()

UI_ACT(/obj/structure/dispenser, "oxygen", ui_act_oxygen)
UI_ACT_PROC(/obj/structure/dispenser, ui_act_oxygen)
	var/obj/item/tank/tank = null
	for(var/obj/item/tank/T in contents_of(src))
		if(istype(T, /obj/item/tank/oxygen) || istype(T, /obj/item/tank/air) || istype(T, /obj/item/tank/anesthetic))
			tank = T
			break
	if(tank && Adjacent(ui.user))
		ui.user.put_in_hands(tank)
		oxygentanks--
	. = TRUE
	play_sfx(src, SFX_ITEMS_DROP_GASCAN)
	update_icon()
