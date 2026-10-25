/obj/machinery/porta_turret/obelisk
	name = "defense obelisk"
	catalogue_data = list(/datum/category_item/catalogue/technology/turret)
	anchored = TRUE

	circuit = /obj/item/circuitboard/defenseonelisk

	catalogue_data = null

	turret_type = "obelisk"
	icon_color = "obelisk_blue"
	lethal_icon_color = "oblisk_blue"

	icon = 'icons/obj/machines/defense.dmi'
	icon_state = "obelisk"

	density = TRUE
	use_power = TRUE				//this turret uses and requires power
	req_one_access = list(ACCESS_HEADS)
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE

	max_integrity = 300			//turrets maximal health.
	auto_repair = TRUE		//if 1 the turret slowly repairs itself.

	installation = /obj/item/gun/energy/pulse_rifle
	reqpower = 50000
	turret_type = "normal"
	icon_color = "blue"
	lethal_icon_color = "blue"

	shot_delay = 0.5 SECONDS	//This will delete foes

	targetting_is_configurable = FALSE
	check_arrest = TRUE
	check_records = TRUE
	check_weapons = FALSE
	check_access = FALSE
	check_anomalies = TRUE
	check_synth	 = FALSE
	check_all = FALSE
	ailock = TRUE

	lethal_is_configurable = FALSE // if false, its lethal setting cannot be changed

	timeout = 1		// When a turret pops up, then finds nothing to shoot at, this number decrements until 0, when it pops down.
	can_salvage = FALSE

CAPABILITIES(/obj/machinery/porta_turret/obelisk)
	configure(uses_power(idle = 50000, active = 150000, channel = EQUIP))

/obj/item/circuitboard/defenseonelisk
	name = "defense obelisk circuit"
	build_path = /obj/machinery/porta_turret/obelisk
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
							/obj/item/stack/cable_coil = 30)
	hidden = TRUE // POI machine, not station made
