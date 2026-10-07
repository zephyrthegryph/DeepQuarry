/obj/mecha/working/hoverpod
	desc = "Stubby and round, this space-capable craft is an ancient favorite."
	name = "Hover Pod"
	catalogue_data = list(/datum/category_item/catalogue/technology/hoverpod)
	icon_state = "engineering_pod"
	initial_icon = "engineering_pod"
	internal_damage_threshold = 80
	step_in = 4
	step_energy_drain = 10
	max_temperature = 20000
	max_integrity = 150
	infra_luminosity = 6
	wreckage = /obj/effect/decal/mecha_wreckage/hoverpod
	cargo_capacity = 5
	max_equip = 3
	var/datum/effect/effect/system/ion_trail_follow/ion_trail
	var/stabilization_enabled = 1

	stomp_sound = 'sound/machines/hiss.ogg'
	swivel_sound = null

	max_hull_equip = 2
	max_weapon_equip = 0
	max_utility_equip = 2
	max_universal_equip = 1
	max_special_equip = 1

CAPABILITIES(/obj/mecha/working/hoverpod)
	owns_one(nameof(ion_trail), /datum/effect/effect/system/ion_trail_follow, starts = /datum/effect/effect/system/ion_trail_follow)
	op("toggle_stabilization", topic("toggle_stabilization"), then(PROC_REF(topic_toggle_stabilization)))

/obj/mecha/working/hoverpod/Initialize(mapload)
	. = ..()
	ion_trail.set_up(src)


/obj/mecha/working/hoverpod/moved_inside(mob/living/carbon/human/H as mob)
	. = ..(H)
	if(.)
		ion_trail.start()

/obj/mecha/working/hoverpod/go_out()
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	. = ..()
	if(!occupant)
		ion_trail.stop()

//Modified phazon code

/obj/mecha/working/hoverpod/proc/topic_toggle_stabilization(datum/act/op/A)
	stabilization_enabled = !stabilization_enabled
	send_byjax(src?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","stabilization_command","[stabilization_enabled?"Dis":"En"]able thruster stabilization")
	src.occupant_message(span_notice("Thruster stabilization [stabilization_enabled? "enabled" : "disabled"]."))
	return

/obj/mecha/working/hoverpod/get_commands()
	var/output = {"<div class='wr'>
						<div class='header'>Special</div>
						<div class='links'>
						<a href='byond://?src=\ref[src];toggle_stabilization=1'><span id="stabilization_command">[stabilization_enabled?"Dis":"En"]able thruster stabilization</span></a><br>
						</div>
						</div>
						"}
	output += ..()
	return output

/obj/mecha/working/hoverpod/can_ztravel()
	return (stabilization_enabled && has_charge(step_energy_drain))

// No space drifting
/obj/mecha/working/hoverpod/check_for_support()
	//does the hoverpod have enough charge left to stabilize itself?
	if (!has_charge(step_energy_drain))
		ion_trail.stop()
	else
		if (!ion_trail.on)
			ion_trail.start()
		if (stabilization_enabled)
			return 1

	return ..()

// No falling if we've got our boosters on
/obj/mecha/working/hoverpod/can_fall()
	return (stabilization_enabled && has_charge(step_energy_drain))

//Hoverpod variants
/obj/mecha/working/hoverpod/combatpod
	desc = "An ancient, run-down combat spacecraft." // Ideally would have a seperate icon.
	name = "Combat Hoverpod"
	max_integrity = 200
	internal_damage_threshold = 35
	cargo_capacity = 2
	max_equip = 2
	max_hull_equip = 2
	max_weapon_equip = 2
	max_utility_equip = 2
	max_universal_equip = 1
	max_special_equip = 1

TYPE_TABLE(/obj/mecha/working/hoverpod/combatpod, mecha_starting_equipment, list( \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/missile_rack/explosive \
		))

/obj/mecha/working/hoverpod/shuttlepod
	desc = "Who knew a tiny ball could fit three people?"

TYPE_TABLE(/obj/mecha/working/hoverpod/shuttlepod, mecha_starting_equipment, list( \
		/obj/item/mecha_parts/mecha_equipment/tool/passenger, \
		/obj/item/mecha_parts/mecha_equipment/tool/passenger \
		))
