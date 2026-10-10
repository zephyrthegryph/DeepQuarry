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

	bound_height = 64
	bound_width = 64

	max_hull_equip = 2
	max_weapon_equip = 1
	max_utility_equip = 2
	max_universal_equip = 1
	max_special_equip = 1

/// The hull's paint: a tinted mask over each painted zone.
/obj/mecha/working/hoverpod/shuttlecraft/draw(datum/look/look)
	..()
	var/base = mecha_base_state()
	if(base_paint)
		look.overlay(look_appearance(icon, "[base]-mask+base", color = base_paint, layer = layer + 1))
	if(front_paint)
		look.overlay(look_appearance(icon, "[base]-mask+front", color = front_paint, layer = layer + 1))
	if(engine_paint)
		look.overlay(look_appearance(icon, "[base]-mask+engine", color = engine_paint, layer = layer + 1))
	if(central_paint)
		look.overlay(look_appearance(icon, "[base]-mask+central", color = central_paint, layer = layer + 2))

TRACKED(/obj/mecha/working/hoverpod/shuttlecraft, base_paint)
TRACKED(/obj/mecha/working/hoverpod/shuttlecraft, engine_paint)
TRACKED(/obj/mecha/working/hoverpod/shuttlecraft, central_paint)
TRACKED(/obj/mecha/working/hoverpod/shuttlecraft, front_paint)

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
	if(ask.value != "CANCEL")
		open_request(src, /datum/prompt/color/mech_paint, PROC_REF(hull_painted), answerer = ask.answerer, subject = ask.subject, zone = ask.value)

/obj/mecha/working/hoverpod/shuttlecraft/proc/hull_painted(datum/act/request/context)
	if(!context.answer)
		return
	return hull_painted_apply(context)

/obj/mecha/working/hoverpod/shuttlecraft/proc/hull_painted_apply(datum/act/request/context)
	var/datum/prompt/color/mech_paint/ask = context.answer
	if(state != 1)
		return
	if(ask.value)
		switch(ask.zone)
			if("Central")
				set_central_paint(ask.value)
			if("Engine")
				set_engine_paint(ask.value)
			if("Front")
				set_front_paint(ask.value)
			if("Base")
				set_base_paint(ask.value)

