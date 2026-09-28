/obj/mecha/working/hoverpod/shuttlecraft
	desc = "A more advanced variant of the hoverpod."
	name = "Shuttle"
	catalogue_data = list(/datum/category_item/catalogue/technology/hoverpod)
	icon = 'icons/mecha/mecha64x64.dmi'
	icon_state = "shuttle_standard"
	initial_icon = "shuttle_standard"
	internal_damage_threshold = 60
	step_in = 2
	step_energy_drain = 5
	max_temperature = 20000
	max_integrity = 300
	infra_luminosity = 6
	wreckage = /obj/effect/decal/mecha_wreckage/shuttlecraft
	cargo_capacity = 3
	max_equip = 3

	opacity = FALSE

	stomp_sound = 'sound/machines/generator/generator_end.ogg'
	swivel_sound = 'sound/machines/hiss.ogg'

	// Paint colors! Null if not set.
	var/base_paint
	var/engine_paint
	var/central_paint
	var/front_paint

	var/image/base_paint_mask
	var/image/engine_paint_mask
	var/image/central_paint_mask
	var/image/front_paint_mask

	bound_height = 64
	bound_width = 64

	max_hull_equip = 2
	max_weapon_equip = 1
	max_utility_equip = 2
	max_universal_equip = 1
	max_special_equip = 1

/obj/mecha/working/hoverpod/shuttlecraft/update_icon()
	cut_overlays()
	..()

	if(base_paint)
		if(!base_paint_mask)
			base_paint_mask = image(icon, "[initial_icon]-mask+base", src.layer + 1)
		base_paint_mask.color = base_paint
		add_overlay(base_paint_mask)
	if(front_paint)
		if(!front_paint_mask)
			front_paint_mask = image(icon, "[initial_icon]-mask+front", src.layer + 1)
		front_paint_mask.color = front_paint
		add_overlay(front_paint_mask)
	if(engine_paint)
		if(!engine_paint_mask)
			engine_paint_mask = image(icon, "[initial_icon]-mask+engine", src.layer + 1)
		engine_paint_mask.color = engine_paint
		add_overlay(engine_paint_mask)
	if(central_paint)
		if(!central_paint_mask)
			central_paint_mask = image(icon, "[initial_icon]-mask+central", src.layer + 2)
		central_paint_mask.color = central_paint
		add_overlay(central_paint_mask)

/obj/mecha/working/hoverpod/shuttlecraft/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W,/obj/item/multitool) && state == 1)
		om_ask(user, /datum/om/prompt/choice, PROC_REF(ask_paint_color), subject = W, choices = list("Central", "Engine", "Base", "Front", "CANCEL"), title = "Paint Zone", message = "Please select a target zone.", ask_flags = ASK_HELD | ASK_CAPABLE)
	else ..()

/obj/mecha/working/hoverpod/shuttlecraft/proc/ask_paint_color(datum/om/prompt/choice/ask)
	if(ask.choice != "CANCEL")
		om_ask(ask.answerer, /datum/om/prompt/color/mech_paint, PROC_REF(hull_painted), subject = ask.subject, zone = ask.choice)

/obj/mecha/working/hoverpod/shuttlecraft/proc/hull_painted(datum/om/prompt/color/mech_paint/ask)
	if(state != 1)
		return
	if(ask.picked_color)
		switch(ask.zone)
			if("Central")
				central_paint = ask.picked_color
			if("Engine")
				engine_paint = ask.picked_color
			if("Front")
				front_paint = ask.picked_color
			if("Base")
				base_paint = ask.picked_color
	update_icon()

REF_OWNED(/obj/mecha/working/hoverpod/shuttlecraft, list("base_paint_mask", "engine_paint_mask", "central_paint_mask", "front_paint_mask"))
