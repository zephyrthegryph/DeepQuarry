/obj/mecha/working/ripley
	desc = "Autonomous Power Loader Unit. The workhorse of the exosuit world."
	name = "APLU \"Ripley\""
	icon_state = "ripley"
	initial_icon = "ripley"
	step_in = 5 // vorestation edit, was 6 but that's PAINFULLY slow
	step_energy_drain = 5 // vorestation edit because 10 drained a significant chunk of its cell before you even got out the airlock
	max_temperature = 20000
	max_integrity = 200		//Don't forget to update the /old variant if  you change this number.
	wreckage = /obj/effect/decal/mecha_wreckage/ripley
	cargo_capacity = 10
	var/obj/item/mining_scanner/orescanner // vorestation addition

	minimum_penetration = 10

	encumbrance_gap = 2


	icon_scale_x = 1.2
	icon_scale_y = 1.2

CAPABILITIES(/obj/mecha/working/ripley)
	op("ripley_detect_ore", menu(), label("Detect Ores"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(ripley_detect_ore)))
	owns_one(nameof(orescanner), /obj/item/mining_scanner, starts = /obj/item/mining_scanner, starts_args = NO_LOC)

TYPE_TABLE(/obj/mecha/working/ripley, mecha_starting_components, list( \
		/obj/item/mecha_parts/component/hull/durable, \
		/obj/item/mecha_parts/component/actuator, \
		/obj/item/mecha_parts/component/armor/mining, \
		/obj/item/mecha_parts/component/gas, \
		/obj/item/mecha_parts/component/electrical \
		))

/obj/mecha/working/ripley/Move()
	. = ..()
	if(.)
		collect_ore()

/obj/mecha/working/ripley/proc/collect_ore()
	if(locate_in_list(equipment, /obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp))
		var/obj/structure/ore_box/ore_box = locate_in_list(cargo, /obj/structure/ore_box)
		if(ore_box)
			for(var/obj/item/ore/ore in range(1, src))
				if(ore.Adjacent(src) && ((get_dir(src, ore) & dir) || ore.loc == loc)) //we can reach it and it's in front of us? grab it!
					ore_box.stored_ore[ore.material]++
					consumed(ore, src)


/obj/mecha/working/ripley/firefighter
	desc = "Standard APLU chassis was refitted with additional thermal protection and cistern."
	name = "APLU \"Firefighter\""
	icon_state = "firefighter"
	initial_icon = "firefighter"
	max_temperature = 65000
	max_integrity = 250
	lights_power = 8
	wreckage = /obj/effect/decal/mecha_wreckage/ripley/firefighter
	max_hull_equip = 2
	max_weapon_equip = 0
	max_utility_equip = 2
	max_universal_equip = 1
	max_special_equip = 1

/obj/mecha/working/ripley/deathripley
	desc = "OH SHIT IT'S THE DEATHSQUAD WE'RE ALL GONNA DIE"
	name = "DEATH-RIPLEY"
	icon_state = "deathripley"
	initial_icon = "deathripley"
	step_in = 2
	opacity=0
	lights_power = 60
	wreckage = /obj/effect/decal/mecha_wreckage/ripley/deathripley
	step_energy_drain = 0
	max_hull_equip = 1
	max_weapon_equip = 1
	max_utility_equip = 3
	max_universal_equip = 1
	max_special_equip = 1

TYPE_TABLE(/obj/mecha/working/ripley/deathripley, mecha_starting_equipment, list( \
		/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/safety \
		))

/obj/mecha/working/ripley/mining
	desc = "An old, dusty mining ripley."
	name = "APLU \"Miner\""

// ALLOW(init/INSTANCE_STATE): rolls a diamond drill one time in four and drops the tracking beacon
/obj/mecha/working/ripley/mining/Initialize(mapload)
	. = ..()
	//Attach drill
	if(prob(25)) //Possible diamond drill... Feeling lucky?
		var/obj/item/mecha_parts/mecha_equipment/tool/drill/diamonddrill/D = new /obj/item/mecha_parts/mecha_equipment/tool/drill/diamonddrill
		D.attach(src)
	else
		var/obj/item/mecha_parts/mecha_equipment/tool/drill/D = new /obj/item/mecha_parts/mecha_equipment/tool/drill
		D.attach(src)

	//Attach hydrolic clamp
	var/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/HC = new /obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp
	HC.attach(src)
	for(var/obj/item/mecha_parts/mecha_tracking/B in slot_contents())//Deletes the beacon so it can't be found easily
		spent(B)

/obj/mecha/working/ripley/antique
	name = "APLU \"Geiger\""
	desc = "You can't beat the classics."
	icon_state = "ripley-old"
	initial_icon = "ripley-old"

	show_pilot = TRUE
	pilot_lift = 5

	max_utility_equip = 1
	max_universal_equip = 3

	icon_scale_x = 1
	icon_scale_y = 1

/obj/mecha/working/ripley/Initialize(mapload)
	. = ..()

/// Old verb "Detect Ores".
/obj/mecha/working/ripley/proc/ripley_detect_ore(datum/act/op/A)
	orescanner.attack_self(A.actor)
	return OP_OK

//Meant for random spawns.
/obj/mecha/working/ripley/mining/old
	desc = "An old, dusty mining ripley."

// ALLOW(init/INSTANCE_STATE): an old exosuit starts worn, damaged and with a random charge
/obj/mecha/working/ripley/mining/old/Initialize(mapload)
	. = ..()
	max_integrity = 190	//Just slightly worse.
	update_integrity(25)
	cell.set_charge(rand(0, cell.charge))

/obj/mecha/working/ripley
	minimum_penetration = 0
