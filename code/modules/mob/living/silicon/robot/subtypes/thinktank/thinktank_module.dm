
/obj/item/robot_module/robot/platform

	hide_on_manifest = TRUE

	var/pupil_color =     COLOR_CYAN
	var/body_color =      COLOR_WHITE
	var/eye_color =       COLOR_BEIGE
	var/armor_color =    "#68a2f2"
	var/user_icon =       'icons/mob/robots_thinktank.dmi'
	var/user_icon_state = "tachi"

	var/list/decals
	var/static/list/available_decals = list(
		"Stripe" = "stripe",
		"Vertical Stripe" = "stripe_vertical"
	)
	idcard_type = /obj/item/card/id/platform

// Only show on manifest if they have a player.
/obj/item/robot_module/robot/platform/hide_on_manifest()
	if(isrobot(loc))
		var/mob/living/silicon/robot/R = loc
		return !R.key
	return ..()

/// A platform's own robot is the one that sets its eye colour: the robot carries the module.
/mob/living/silicon/robot/proc/has_platform_module(datum/act/op/A)
	return istype(module, /obj/item/robot_module/robot/platform)

/// A cancel (or an empty answer) is the default colour.
/mob/living/silicon/robot/proc/set_eye_colour_op(datum/act/op/A)
	var/obj/item/robot_module/robot/platform/platform = module
	if(!istype(platform))
		return
	platform.set_pupil_color(A.step_value("colour") || initial(platform.pupil_color))

/obj/item/robot_module/robot/platform/explorer
	armor_color = "#528052"
	eye_color =   "#7b7b46"
	decals = list(
		"stripe_vertical" = "#52b8b8",
		"stripe" =          "#52b8b8"
	)
	channels = list(
		CHANNEL_SCIENCE = 1,
		CHANNEL_EXPLORATION = 1
	)

/obj/item/robot_module/robot/platform/explorer/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/tool/wrench/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/weldingtool/electric/mounted/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/wirecutters/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/tool/screwdriver/cyborg(src))
	rel_add(src, nameof(modules), new /obj/item/pickaxe/plasmacutter(src))
	rel_add(src, nameof(modules), new /obj/item/material/knife/machete/cyborg(src))

	var/datum/matter_synth/medicine = new /datum/matter_synth/medicine(7500)
	var/obj/item/stack/medical/bruise_pack/bandaid = new(src)
	bandaid.set_uses_charge(1)
	bandaid.set_charge_costs(list(1000))
	bandaid.add_synth(medicine)
	rel_add(src, nameof(modules), bandaid)
	rel_add(src, nameof(synths), medicine)

	rel_add(src, nameof(modules), new /obj/item/gun/energy/robotic/phasegun(src))

	rel_add(src, nameof(emag), new /obj/item/chainsaw(src))

/obj/item/robot_module/robot/platform/explorer/respawn_consumable(mob/living/silicon/robot/R, rate)
	. = ..()
	for(var/obj/item/gun/energy/pew in modules)
		if(pew.power_supply && pew.power_supply.charge < pew.power_supply.maxcharge)
			pew.power_supply.give(pew.charge_cost * rate)
		else
			pew.charge_tick = 0

/obj/item/robot_module/robot/platform/cargo
	armor_color = "#d5b222"
	eye_color =   "#686846"
	decals = list(
		"stripe_vertical" = "#bfbfa1",
		"stripe" =          "#bfbfa1"
	)
	channels = list(CHANNEL_SUPPLY = 1)
	networks = list(NETWORK_MINE)

/obj/item/robot_module/robot/platform/cargo/create_equipment(mob/living/silicon/robot/robot)
	..()
	rel_add(src, nameof(modules), new /obj/item/packageWrap(src))
	rel_add(src, nameof(modules), new /obj/item/pen/multi(src))
	rel_add(src, nameof(modules), new /obj/item/destTagger(src))
	rel_add(src, nameof(emag), new /obj/item/stamp/denied)

/obj/item/robot_module/robot/platform/cargo/respawn_consumable(mob/living/silicon/robot/R, rate)
	. = ..()
	var/obj/item/packageWrap/wrapper = locate_in_list(modules, /obj/item/packageWrap)
	if(wrapper.amount < initial(wrapper.amount))
		wrapper.amount++
