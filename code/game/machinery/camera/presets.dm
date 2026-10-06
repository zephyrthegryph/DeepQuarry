// PRESETS
/*
GLOBAL_LIST_INIT(station_networks, list(
//										NETWORK_CAFE_DOCK,
										NETWORK_CARGO,
										NETWORK_CIVILIAN,
//										NETWORK_CIVILIAN_EAST,
//										NETWORK_CIVILIAN_WEST,
										NETWORK_COMMAND,
										NETWORK_ENGINE,
										NETWORK_ENGINEERING,
										NETWORK_ENGINEERING_OUTPOST,
										NETWORK_DEFAULT,
										NETWORK_MEDICAL,
										NETWORK_MINE,
										NETWORK_NORTHERN_STAR,
										NETWORK_RESEARCH,
										NETWORK_RESEARCH_OUTPOST,
										NETWORK_ROBOTS,
										NETWORK_PRISON,
										NETWORK_SECURITY,
										NETWORK_INTERROGATION
										))
*/
GLOBAL_LIST_INIT(engineering_networks, list(
										NETWORK_ENGINE,
										NETWORK_SUBSTATIONS,
										NETWORK_ENGINEERING,
										// NETWORK_ENGINEERING_OUTPOST, // Tether has no Engineering Outpost,
										NETWORK_ALARM_ATMOS,
										NETWORK_ALARM_FIRE,
										NETWORK_ALARM_POWER))
/obj/machinery/camera/network/crescent
	network = list(NETWORK_CRESCENT)

/*
/obj/machinery/camera/network/cafe_dock
	network = list(NETWORK_CAFE_DOCK)
*/

/obj/machinery/camera/network/cargo
	network = list(NETWORK_CARGO)

/obj/machinery/camera/network/civilian
	network = list(NETWORK_CIVILIAN)

/obj/machinery/camera/network/circuits
	network = list(NETWORK_CIRCUITS)

/obj/machinery/camera/network/command
	network = list(NETWORK_COMMAND)

/obj/machinery/camera/network/engine
	network = list(NETWORK_ENGINE)

/obj/machinery/camera/network/engineering
	network = list(NETWORK_ENGINEERING)

/obj/machinery/camera/network/engineering_outpost
	network = list(NETWORK_ENGINEERING_OUTPOST)

/obj/machinery/camera/network/ert
	network = list(NETWORK_ERT)

/obj/machinery/camera/network/exodus
	network = list(NETWORK_DEFAULT)

/obj/machinery/camera/network/interrogation
	network = list(NETWORK_INTERROGATION)

/obj/machinery/camera/network/mining
	network = list(NETWORK_MINE)

/obj/machinery/camera/network/northern_star
	network = list(NETWORK_NORTHERN_STAR)

/obj/machinery/camera/network/prison
	network = list(NETWORK_PRISON)

/obj/machinery/camera/network/medbay
	network = list(NETWORK_MEDICAL)

/obj/machinery/camera/network/research
	network = list(NETWORK_RESEARCH)

/obj/machinery/camera/network/exploration
	network = list(NETWORK_EXPLORATION)

/obj/machinery/camera/network/research_outpost
	network = list(NETWORK_RESEARCH_OUTPOST)

/obj/machinery/camera/network/security
	network = list(NETWORK_SECURITY)

/obj/machinery/camera/network/substations
	network = list(NETWORK_SUBSTATIONS)

/obj/machinery/camera/network/telecom
	network = list(NETWORK_TCOMMS)

/obj/machinery/camera/network/exploration
	network = list(NETWORK_EXPLORATION)

/obj/machinery/camera/network/research/xenobio
	network = list(NETWORK_RESEARCH, NETWORK_XENOBIO)

/obj/machinery/camera/network/thunder
	network = list(NETWORK_THUNDER)
	invuln = 1
	always_visible = TRUE

// Bodycams
/obj/machinery/camera/network/bodycamera
	network = list(NETWORK_BODYCAM)
	invuln = 1
	always_visible = TRUE

// EMP

TYPE_TABLE(/obj/machinery/camera/emp_proof, camera_initial_emp_proof, TRUE)

// X-RAY

/obj/machinery/camera/xray
	icon_state = "camera" // Thanks to Krutchen for the icons. // no xraycam in vr icons

/obj/machinery/camera/xray/command
	network = list(NETWORK_COMMAND)

/obj/machinery/camera/xray/security
	network = list(NETWORK_SECURITY)

/obj/machinery/camera/xray/medbay
	network = list(NETWORK_MEDICAL)

/obj/machinery/camera/xray/research
	network = list(NETWORK_RESEARCH)

TYPE_TABLE(/obj/machinery/camera/xray, camera_initial_xray, TRUE)

// MOTION

TYPE_TABLE(/obj/machinery/camera/motion, camera_initial_motion, TRUE)

/obj/machinery/camera/motion/engineering_outpost
	network = list(NETWORK_ENGINEERING_OUTPOST)

/obj/machinery/camera/motion/security
	network = list(NETWORK_SECURITY)

/obj/machinery/camera/motion/command
	network = list(NETWORK_COMMAND)

/obj/machinery/camera/motion/telecom
	network = list(NETWORK_TCOMMS)

// ALL UPGRADES

/obj/machinery/camera/all/command
	network = list(NETWORK_COMMAND)

TYPE_TABLE(/obj/machinery/camera/all, camera_initial_emp_proof, TRUE)
TYPE_TABLE(/obj/machinery/camera/all, camera_initial_xray, TRUE)
TYPE_TABLE(/obj/machinery/camera/all, camera_initial_motion, TRUE)

// AUTONAME
/obj/machinery/camera/autoname
	/// Area name -> how many autonamed cameras have been numbered there (numbers only, no camera refs).
	var/static/list/by_area

// ALLOW(init/INSTANCE_STATE): its camera tag numbers it within the area it is placed in
/obj/machinery/camera/autoname/Initialize(mapload)
	. = ..()
	var/area/A = get_area(src)
	if(!A)
		return .
	if(!by_area)
		by_area = list()
	var/number = by_area[A.name] + 1
	by_area[A.name] = number

	c_tag = "[A.name] #[number]"

// CHECKS

/obj/machinery/camera/proc/isEmpProof()
	if(!assembly)
		return FALSE
	var/O = locate_in_list(assembly.upgrades, /obj/item/stack/material/osmium)
	return O

/obj/machinery/camera/proc/isXRay()
	if(!assembly)
		return FALSE
	var/obj/item/stock_parts/scanning_module/O = locate_in_list(assembly.upgrades, /obj/item/stock_parts/scanning_module)
	if (O && O.rating >= 2)
		return O
	return null

/obj/machinery/camera/proc/isMotion()
	if(!assembly)
		return FALSE
	var/O = locate_in_list(assembly.upgrades, /obj/item/assembly/prox_sensor)
	return O

// UPGRADE PROCS

/obj/machinery/camera/proc/upgradeEmpProof()
	rel_add(assembly, nameof(assembly.upgrades), new /obj/item/stack/material/osmium(assembly))
	setPowerUsage()
	update_coverage()

/obj/machinery/camera/proc/upgradeXRay()
	rel_add(assembly, nameof(assembly.upgrades), new /obj/item/stock_parts/scanning_module(assembly))
	setPowerUsage()
	update_coverage()

/obj/machinery/camera/proc/upgradeMotion()
	if(!isturf(loc))
		return //nooooo
	rel_add(assembly, nameof(assembly.upgrades), new /obj/item/assembly/prox_sensor(assembly))
	setPowerUsage()
	sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))
	update_coverage()

/obj/machinery/camera/proc/setPowerUsage()
	var/mult = 1
	if (isXRay())
		mult++
	if (isMotion())
		mult++
	update_active_power_usage(mult * initial(active_power_usage))
