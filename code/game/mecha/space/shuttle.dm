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
		look.overlay(look_appearance(icon, "[base]-mask+base", color = base_paint, layer = initial(layer) + 1))
	if(front_paint)
		look.overlay(look_appearance(icon, "[base]-mask+front", color = front_paint, layer = initial(layer) + 1))
	if(engine_paint)
		look.overlay(look_appearance(icon, "[base]-mask+engine", color = engine_paint, layer = initial(layer) + 1))
	if(central_paint)
		look.overlay(look_appearance(icon, "[base]-mask+central", color = central_paint, layer = initial(layer) + 2))


CAPABILITIES(/obj/mecha/working/hoverpod/shuttlecraft)
	op("shuttlecraft_paint", item(/obj/item), label("Paint hull"), when(PROC_REF(paintable_by_multitool)),
		asks(/datum/prompt/choice, fields = list("title" = "Paint Zone", "question" = "Please select a target zone.", "choices" = list("Central", "Engine", "Base", "Front", "CANCEL"), "subject" = computed(PROC_REF(paint_subject)), "ask_flags" = ASK_HELD | ASK_CAPABLE, "timeout" = 0), step = "zone"),
		asks(/datum/prompt/color/mech_paint, fields = list("subject" = computed(PROC_REF(paint_subject))), step = "color", when = PROC_REF(paint_zone_chosen)),
		then(PROC_REF(interaction_shuttlecraft_paint)))

/// A multitool repaints the hull while the maintenance state is open.
/obj/mecha/working/hoverpod/shuttlecraft/proc/paintable_by_multitool(datum/act/op/A)
	return istype(A.held, /obj/item/multitool) && state == 1

/// The question is about the multitool in the hand.
/obj/mecha/working/hoverpod/shuttlecraft/proc/paint_subject(datum/act/op/A)
	return A.held

/// A zone other than CANCEL was picked, so a colour is asked.
/obj/mecha/working/hoverpod/shuttlecraft/proc/paint_zone_chosen(datum/act/op/A)
	var/zone = A.step_value("zone")
	return !isnull(zone) && zone != "CANCEL"

/// Old attackby: the colour answered for the zone answered.
/obj/mecha/working/hoverpod/shuttlecraft/proc/interaction_shuttlecraft_paint(datum/act/op/A)
	if(state != 1)
		return TRUE
	var/color_value = A.step_value("color")
	if(color_value)
		switch(A.step_value("zone"))
			if("Central")
				set_central_paint(color_value)
			if("Engine")
				set_engine_paint(color_value)
			if("Front")
				set_front_paint(color_value)
			if("Base")
				set_base_paint(color_value)
	return TRUE

