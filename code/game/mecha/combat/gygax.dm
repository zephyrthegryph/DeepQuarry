/obj/mecha/combat/gygax
	desc = "A lightweight, security exosuit. Popular among private and corporate security."
	name = "Gygax"
	icon_state = "gygax"
	initial_icon = "gygax"
	step_in = 3
	dir_in = 1 //Facing North.
	max_integrity = 250			//Don't forget to update the /old variant if  you change this number.
	max_temperature = 25000
	infra_luminosity = 6
	wreckage = /obj/effect/decal/mecha_wreckage/gygax
	internal_damage_threshold = 35
	max_equip = 3

	max_hull_equip = 1
	max_weapon_equip = 2
	max_utility_equip = 2
	max_universal_equip = 1
	max_special_equip = 1


	overload_possible = 1

	icon_scale_x = 1.35
	icon_scale_y = 1.35

//Not quite sure how to move those yet.

TYPE_TABLE(/obj/mecha/combat/gygax, mecha_starting_components, list( \
		/obj/item/mecha_parts/component/hull/lightweight, \
		/obj/item/mecha_parts/component/actuator, \
		/obj/item/mecha_parts/component/armor/marshal, \
		/obj/item/mecha_parts/component/gas, \
		/obj/item/mecha_parts/component/electrical \
		))
/obj/mecha/combat/gygax/get_commands()
	var/output = {"<div class='wr'>
						<div class='header'>Special</div>
						<div class='links'>
						<a href='byond://?src=\ref[src];toggle_leg_overload=1'>Toggle leg actuators overload</a>
						</div>
						</div>
						"}
	output += ..()
	return output


/obj/mecha/combat/gygax/dark
	desc = "A lightweight exosuit used by Heavy Asset Protection. A significantly upgraded Gygax security mech."
	name = "Dark Gygax"
	icon_state = "darkgygax"
	initial_icon = "darkgygax"
	max_integrity = 400
	max_temperature = 45000
	overload_coeff = 1
	wreckage = /obj/effect/decal/mecha_wreckage/gygax/dark
	max_equip = 4
	step_energy_drain = 5
	mech_faction = MECH_FACTION_SYNDI

	max_hull_equip = 1
	max_weapon_equip = 2
	max_utility_equip = 2
	max_universal_equip = 1
	max_special_equip = 2


/obj/mecha/combat/gygax/dark/add_cell(obj/item/cell/C=null)
	if(C)
		move_into(src, nameof(src.cell), C)
		return
	rel_set(src, nameof(cell), new /obj/item/cell/hyper(src))

/obj/mecha/combat/gygax/serenity
	desc = "A lightweight exosuit made from a modified Gygax chassis combined with proprietary VeyMed medical tech. It's faster and sturdier than most medical mechs, but much of the armor plating has been stripped out, leaving it more vulnerable than a regular Gygax."
	name = "Serenity"
	icon_state = "medgax"
	initial_icon = "medgax"
	max_integrity = 150
	step_in = 2
	max_temperature = 20000
	overload_coeff = 1
	wreckage = /obj/effect/decal/mecha_wreckage/gygax/serenity
	max_equip = 3
	step_energy_drain = 8
	cargo_capacity = 2
	max_hull_equip = 1
	max_weapon_equip = 1
	max_utility_equip = 2
	max_universal_equip = 1
	max_special_equip = 1


	var/obj/item/clothing/glasses/hud/health/mech/hud

TYPE_TABLE(/obj/mecha/combat/gygax/serenity, mecha_starting_components, list( \
		/obj/item/mecha_parts/component/hull, \
		/obj/item/mecha_parts/component/actuator, \
		/obj/item/mecha_parts/component/armor/lightweight, \
		/obj/item/mecha_parts/component/gas, \
		/obj/item/mecha_parts/component/electrical \
		))

CAPABILITIES(/obj/mecha/combat/gygax/serenity)
	owns_one(nameof(hud), starts = /obj/item/clothing/glasses/hud/health/mech)

/obj/mecha/combat/gygax/serenity/moved_inside(mob/living/carbon/human/H as mob)
	if(..())
		if(H.get_equipped_item(SLOT_ID_EYES))
			occupant_message(span_red("[H.get_equipped_item(SLOT_ID_EYES)] prevent you from using [src] [hud]!"))
		else if(move_into(H, SLOT_ID_EYES, hud, H))
			H.recalculate_vis()
		return 1
	else
		return 0

/obj/mecha/combat/gygax/serenity/go_out()
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(ishuman(occupant))
		var/mob/living/carbon/human/H = occupant
		if(H.get_equipped_item(SLOT_ID_EYES) == hud)
			H.slot_remove(hud, src, H)
			H.recalculate_vis()
	..()
	return

//Meant for random spawns.
/obj/mecha/combat/gygax/old
	desc = "A lightweight, security exosuit. Popular among private and corporate security. This one is particularly worn looking and likely isn't as sturdy."

// ALLOW(init/INSTANCE_STATE): an old exosuit starts worn, damaged and with a random charge
/obj/mecha/combat/gygax/old/Initialize(mapload)
	. = ..()
	max_integrity = 250	//Just slightly worse.
	update_integrity(25)
	cell.set_charge(rand(0, (cell.charge/2)))

/obj/mecha/combat/gygax/serenity/ownership()
	. = ..()
	. += owns(nameof(hud), policy = OWN_CONTAINED)

TYPE_TABLE(/obj/mecha/combat/gygax/dark, mecha_starting_equipment, list( \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/scattershot, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/missile_rack/grenade/clusterbang, \
		/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay, \
		/obj/item/mecha_parts/mecha_equipment/teleporter \
		))
