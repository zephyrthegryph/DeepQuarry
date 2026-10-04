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
	swivel_sound = SFX_MACHINES_HISS

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

DECLARE_APPEARANCE_PROC(/obj/mecha/working/hoverpod/shuttlecraft, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/mecha/working/hoverpod/shuttlecraft/appearance_overlays()
	. = list()
	. += ..()

	if(base_paint)
		if(!base_paint_mask)
			base_paint_mask = image(icon, "[initial_icon]-mask+base", src.layer + 1)
		base_paint_mask.color = base_paint
		. += base_paint_mask
	if(front_paint)
		if(!front_paint_mask)
			front_paint_mask = image(icon, "[initial_icon]-mask+front", src.layer + 1)
		front_paint_mask.color = front_paint
		. += front_paint_mask
	if(engine_paint)
		if(!engine_paint_mask)
			engine_paint_mask = image(icon, "[initial_icon]-mask+engine", src.layer + 1)
		engine_paint_mask.color = engine_paint
		. += engine_paint_mask
	if(central_paint)
		if(!central_paint_mask)
			central_paint_mask = image(icon, "[initial_icon]-mask+central", src.layer + 2)
		central_paint_mask.color = central_paint
		. += central_paint_mask

CAPABILITIES(/obj/mecha/working/hoverpod/shuttlecraft)
	op("shuttlecraft_paint", item(/obj/item), label("Paint hull"), then(PROC_REF(interaction_shuttlecraft_paint)))

/// Old attackby: a multitool repaints the hull while the maintenance state is open.
/obj/mecha/working/hoverpod/shuttlecraft/proc/interaction_shuttlecraft_paint(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!istype(W,/obj/item/multitool) || state != 1)
		return OP_DECLINE
	open_request(src, /datum/prompt/choice, PROC_REF(ask_paint_color), answerer = user, subject = W, timeout = 0, choices = list("Central", "Engine", "Base", "Front", "CANCEL"), title = "Paint Zone", question = "Please select a target zone.", ask_flags = ASK_HELD | ASK_CAPABLE)
	return TRUE

/obj/mecha/working/hoverpod/shuttlecraft/proc/ask_paint_color(datum/act/request/context)
	if(!context.answer)
		return
	return ask_paint_color_apply(context)

/obj/mecha/working/hoverpod/shuttlecraft/proc/ask_paint_color_apply(datum/act/request/context)
	var/datum/prompt/choice/ask = context.answer
	if(ask.answer_value != "CANCEL")
		open_request(src, /datum/prompt/color/mech_paint, PROC_REF(hull_painted), answerer = ask.answerer, subject = ask.subject, zone = ask.answer_value)

/obj/mecha/working/hoverpod/shuttlecraft/proc/hull_painted(datum/act/request/context)
	if(!context.answer)
		return
	return hull_painted_apply(context)

/obj/mecha/working/hoverpod/shuttlecraft/proc/hull_painted_apply(datum/act/request/context)
	var/datum/prompt/color/mech_paint/ask = context.answer
	if(state != 1)
		return
	if(ask.answer_value)
		switch(ask.zone)
			if("Central")
				central_paint = ask.answer_value
			if("Engine")
				engine_paint = ask.answer_value
			if("Front")
				front_paint = ask.answer_value
			if("Base")
				base_paint = ask.answer_value
	update_icon()

