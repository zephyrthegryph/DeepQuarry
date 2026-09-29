// Communicator peripheral devices
// Internal devices that attack() can be relayed to
// Additional UI menus for added functionality
/obj/item/commcard
	name = "generic commcard"
	desc = "A peripheral plug-in for personal communicators."
	icon = 'icons/obj/pda.dmi'
	icon_state = "cart"
	item_state = "electronic"
	w_class = ITEMSIZE_TINY

	var/list/internal_devices // Devices that can be toggled on to trigger on attack()
	var/list/active_devices   // Devices that will be triggered on attack()
	var/list/ui_templates     // List of ui templates the commcard can access
	// ALLOW(instance_list): d: per-card UI state keyed by dynamic strings; few communicators
	var/list/internal_data = list()	   // Data that shouldn't be updated every time nanoUI updates, or needs to persist between updates

/obj/item/commcard/proc/get_device_status()
	var/list/L = list()
	var/i = 1
	for(var/obj/I in internal_devices)
		if(I in active_devices)
			L[++L.len] = list("name" = "\proper[I.name]", "active" = 1, "index" = i++)
		else
			L[++L.len] = list("name" = I.name, "active" = 0, "index" = i++)
	return L

// cartridge.get_data() returns a list of tuples:
// The field element is the tag used to access the information by the template
// The value element is the actual data, and can take any form necessary for the template
/obj/item/commcard/proc/get_data()
	return list()

// Receives updates by external devices to the status displays
/obj/item/commcard/receive_signal(datum/signal/signal, receive_method, receive_param)
	internal_data["stat_display_special"] = signal.data["command"]
	switch(signal.data["command"])
		if("message")
			internal_data["stat_display_active1"] = signal.data["msg1"]
			internal_data["stat_display_active2"] = signal.data["msg2"]
		if("alert")
			internal_data["stat_display_special"] = signal.data["picture_state"]

///////////////////////////
// SUBTYPES
///////////////////////////

// Engineering Cartridge:
// Devices
//  *- Halogen Counter
// Templates
//  *- Power Monitor
/obj/item/commcard/engineering
	name = "\improper Power-ON cartridge"
	icon_state = "cart-e"
	ui_templates = list(list("name" = "Power Monitor", "template" = "comm_power_monitor.tmpl"))

/obj/item/commcard/engineering/Initialize(mapload)
	..()
	own_add(src, "internal_devices", new /obj/item/halogen_counter(src))
	return INITIALIZE_HINT_LATELOAD

/obj/item/commcard/engineering/LateInitialize()
	. = ..()
	internal_data["grid_sensors"] = find_powernet_sensors()
	internal_data["powernet_target"] = ""

/obj/item/commcard/engineering/get_data()
	return list(
			list("field" = "powernet_monitoring", "value" = get_powernet_monitoring_list()),
			list("field" = "powernet_target", "value" = get_powernet_target(internal_data["powernet_target"]))
		)

// Atmospherics Cartridge:
// Devices
//  *- Gas scanner
/obj/item/commcard/atmos
	name = "\improper BreatheDeep cartridge"
	icon_state = "cart-a"

/obj/item/commcard/atmos/Initialize(mapload)
	. = ..()
	own_add(src, "internal_devices", new /obj/item/analyzer(src))

// Medical Cartridge:
// Devices
//  *- Halogen Counter
//  *- Health Analyzer
// Templates
//  *- Medical Records
/obj/item/commcard/medical
	name = "\improper Med-U cartridge"
	icon_state = "cart-m"
	ui_templates = list(list("name" = "Medical Records", "template" = "med_records.tmpl"))

/obj/item/commcard/medical/Initialize(mapload)
	. = ..()
	own_add(src, "internal_devices", new /obj/item/healthanalyzer(src))
	own_add(src, "internal_devices", new /obj/item/halogen_counter(src))

/obj/item/commcard/medical/get_data()
	return list(list("field" = "med_records", "value" = get_med_records()))

// Chemistry Cartridge:
// Devices
//  *- Halogen Counter
//  *- Health Analyzer
//  *- Reagent Scanner
// Templates
//  *- Medical Records
/obj/item/commcard/medical/chemistry
	name = "\improper ChemWhiz cartridge"
	icon_state = "cart-chem"

/obj/item/commcard/medical/chemistry/Initialize(mapload)
	. = ..()
	own_add(src, "internal_devices", new /obj/item/reagent_scanner(src))

// Detective Cartridge:
// Devices
//  *- Halogen Counter
//  *- Health Analyzer
// Templates
//  *- Medical Records
//  *- Security Records
/obj/item/commcard/medical/detective
	name = "\improper D.E.T.E.C.T. cartridge"
	icon_state = "cart-s"
	ui_templates = list(
			list("name" = "Medical Records", "template" = "med_records.tmpl"),
			list("name" = "Security Records", "template" = "sec_records.tmpl")
		)

/obj/item/commcard/medical/detective/get_data()
	var/list/data = ..()
	data[++data.len] = list("field" = "sec_records", "value" = get_sec_records())
	return data

// Internal Affairs Cartridge:
// Templates
//  *- Security Records
//  *- Employment Records
/obj/item/commcard/int_aff
	name = "\improper P.R.O.V.E. cartridge"
	icon_state = "cart-s"
	ui_templates = list(
			list("name" = "Employment Records", "template" = "emp_records.tmpl"),
			list("name" = "Security Records", "template" = "sec_records.tmpl")
		)

/obj/item/commcard/int_aff/get_data()
	return list(
			list("field" = "emp_records", "value" = get_emp_records()),
			list("field" = "sec_records", "value" = get_sec_records())
		)

// Security Cartridge:
// Templates
//  *- Security Records
//  *- Security Bot Access
/obj/item/commcard/security
	name = "\improper R.O.B.U.S.T. cartridge"
	icon_state = "cart-s"
	ui_templates = list(
			list("name" = "Security Records", "template" = "sec_records.tmpl"),
			list("name" = "Security Bot Control", "template" = "sec_bot_access.tmpl")
		)

/obj/item/commcard/security/get_data()
	return list(
			list("field" = "sec_records", "value" = get_sec_records()),
			list("field" = "sec_bot_access", "value" = get_sec_bot_access())
		)

// Janitor Cartridge:
// Templates
//  *- Janitorial Locator Magicbox
/obj/item/commcard/janitor
	name = "\improper CustodiPRO cartridge"
	desc = "The ultimate in clean-room design."
	ui_templates = list(
			list("name" = "Janitorial Supply Locator", "template" = "janitorialLocator.tmpl")
		)

/obj/item/commcard/janitor/get_data()
	return list(
			list("field" = "janidata", "value" = get_janitorial_locations())
		)

// Signal Cartridge:
// Devices
//  *- Signaler
// Templates
//  *- Signaler Access
/obj/item/commcard/signal
	name = "generic signaler cartridge"
	desc = "A data cartridge with an integrated radio signaler module."
	ui_templates = list(
			list("name" = "Integrated Signaler Control", "template" = "signaler_access.tmpl")
		)

/obj/item/commcard/signal/Initialize(mapload)
	. = ..()
	own_add(src, "internal_devices", new /obj/item/assembly/signaler(src))

/obj/item/commcard/signal/get_data()
	return list(
			list("field" = "signaler_access", "value" = get_int_signalers())
		)

// Science Cartridge:
// Devices
//  *- Signaler
//  *- Reagent Scanner
//  *- Gas Scanner
// Templates
//  *- Signaler Access
/obj/item/commcard/signal/science
	name = "\improper Signal Ace 2 cartridge"
	desc = "Complete with integrated radio signaler!"
	icon_state = "cart-tox"
	// UI templates inherited

/obj/item/commcard/signal/science/Initialize(mapload)
	. = ..()
	own_add(src, "internal_devices", new /obj/item/reagent_scanner(src))
	own_add(src, "internal_devices", new /obj/item/analyzer(src))

// Supply Cartridge:
// Templates
//  *- Supply Records
/obj/item/commcard/supply
	name = "\improper Space Parts & Space Vendors cartridge"
	desc = "Perfect for the Quartermaster on the go!"
	icon_state = "cart-q"
	ui_templates = list(
			list("name" = "Supply Records", "template" = "supply_records.tmpl")
		)

/obj/item/commcard/supply/Initialize(mapload)
	. = ..()
	internal_data["supply_category"] = null
	internal_data["supply_controls"] = FALSE // Cannot control the supply shuttle, cannot accept orders
	internal_data["supply_pack_expanded"] = list()
	internal_data["supply_reqtime"] = -1

/obj/item/commcard/supply/get_data()
	// Supply records data
	var/list/shuttle_status = get_supply_shuttle_status()
	var/list/orders = get_supply_orders()
	var/list/receipts = get_supply_receipts()
	var/list/misc_supply_data = get_misc_supply_data() // Packaging this stuff externally so it's less hardcoded into the specific cartridge
	var/list/pack_list = list() // List of supply packs within the currently selected category

	if(internal_data["supply_category"])
		pack_list = get_supply_pack_list()

	return list(
			list("field" = "shuttle_auth",		"value" = misc_supply_data["shuttle_auth"]),
			list("field" = "order_auth", 		"value" = misc_supply_data["order_auth"]),
			list("field" = "supply_points",		"value" = misc_supply_data["supply_points"]),
			list("field" = "categories",		"value" = misc_supply_data["supply_categories"]),
			list("field" = "contraband",		"value" = misc_supply_data["contraband"]),
			list("field" = "active_category",	"value" = internal_data["supply_category"]),
			list("field" = "shuttle",			"value" = shuttle_status),
			list("field" = "orders",			"value" = orders),
			list("field" = "receipts",			"value" = receipts),
			list("field" = "supply_packs",		"value" = pack_list)
		)

// Command Cartridge:
// Templates
//  *- Status Display Access
//  *- Employment Records
/obj/item/commcard/head
	name = "\improper Easy-Record DELUXE"
	icon_state = "cart-h"
	ui_templates = list(
			list("name" = "Status Display Access", "template" = "stat_display_access.tmpl"),
			list("name" = "Employment Records", "template" = "emp_records.tmpl")
		)

/obj/item/commcard/head/Initialize(mapload)
	// Have to register the commcard with the Radio controller to receive updates to the status displays
	// ALLOW(decl): service call with a frequency argument
	GLOB.radio_service.add_object(src, 1435)
	. = ..()
	internal_data["stat_display_line1"] = null
	internal_data["stat_display_line2"] = null
	internal_data["stat_display_active1"] = null
	internal_data["stat_display_active2"] = null
	internal_data["stat_display_special"] = null

/obj/item/commcard/head/get_data()
	return list(
			list("field" = "emp_records", "value" = get_emp_records()),
			list("field" = "stat_display", "value" = get_status_display())
		)

// Head of Personnel Cartridge:
// Templates
//  *- Status Display Access
//  *- Employment Records
//  *- Security Records
//  *- Supply Records
//  ?- Supply Bot Access
//  *- Janitorial Locator Magicbox
/obj/item/commcard/head/hop
	name = "\improper HumanResources9001 cartridge"
	icon_state = "cart-h"
	ui_templates = list(
			list("name" = "Status Display Access", "template" = "stat_display_access.tmpl"),
			list("name" = "Employment Records", "template" = "emp_records.tmpl"),
			list("name" = "Security Records", "template" = "sec_records.tmpl"),
			list("name" = "Supply Records", "template" = "supply_records.tmpl"),
			list("name" = "Janitorial Supply Locator", "template" = "janitorialLocator.tmpl")
		)

/obj/item/commcard/head/hop/get_data()
	var/list/data = ..()

	// Sec records
	data[++data.len] = list("field" = "sec_records", "value" = get_sec_records())

	// Supply records data
	var/list/shuttle_status = get_supply_shuttle_status()
	var/list/orders = get_supply_orders()
	var/list/receipts = get_supply_receipts()
	var/list/misc_supply_data = get_misc_supply_data() // Packaging this stuff externally so it's less hardcoded into the specific cartridge
	var/list/pack_list = list() // List of supply packs within the currently selected category

	if(internal_data["supply_category"])
		pack_list = get_supply_pack_list()

	data[++data.len] = list("field" = "shuttle_auth",	 "value" = misc_supply_data["shuttle_auth"])
	data[++data.len] = list("field" = "order_auth",		 "value" = misc_supply_data["order_auth"])
	data[++data.len] = list("field" = "supply_points",	 "value" = misc_supply_data["supply_points"])
	data[++data.len] = list("field" = "categories",		 "value" = misc_supply_data["supply_categories"])
	data[++data.len] = list("field" = "contraband",		 "value" = misc_supply_data["contraband"])
	data[++data.len] = list("field" = "active_category", "value" = internal_data["supply_category"])
	data[++data.len] = list("field" = "shuttle",		 "value" = shuttle_status)
	data[++data.len] = list("field" = "orders",			 "value" = orders)
	data[++data.len] = list("field" = "receipts",		 "value" = receipts)
	data[++data.len] = list("field" = "supply_packs",	 "value" = pack_list)

	// Janitorial locator magicbox
	data[++data.len] = list("field" = "janidata", "value" = get_janitorial_locations())

	return data

// Head of Security Cartridge:
// Templates
//  *- Status Display Access
//  *- Employment Records
//  *- Security Records
//  *- Security Bot Access
/obj/item/commcard/head/hos
	name = "\improper R.O.B.U.S.T. DELUXE"
	icon_state = "cart-hos"
	ui_templates = list(
			list("name" = "Status Display Access", "template" = "stat_display_access.tmpl"),
			list("name" = "Employment Records", "template" = "emp_records.tmpl"),
			list("name" = "Security Records", "template" = "sec_records.tmpl"),
			list("name" = "Security Bot Control", "template" = "sec_bot_access.tmpl")
		)

/obj/item/commcard/head/hos/get_data()
	var/list/data = ..()
	// Sec records
	data[++data.len] = list("field" = "sec_records", "value" = get_sec_records())
	// Sec bot access
	data[++data.len] = list("field" = "sec_bot_access", "value" = get_sec_bot_access())
	return data

// Research Director Cartridge:
// Devices
//  *- Signaler
//  *- Gas Scanner
//  *- Reagent Scanner
// Templates
//  *- Status Display Access
//  *- Employment Records
//  *- Signaler Access
/obj/item/commcard/head/rd
	name = "\improper Signal Ace DELUXE"
	icon_state = "cart-rd"
	ui_templates = list(
			list("name" = "Status Display Access", "template" = "stat_display_access.tmpl"),
			list("name" = "Employment Records", "template" = "emp_records.tmpl"),
			list("name" = "Integrated Signaler Control", "template" = "signaler_access.tmpl")
		)

/obj/item/commcard/head/rd/Initialize(mapload)
	. = ..()
	own_add(src, "internal_devices", new /obj/item/analyzer(src))
	own_add(src, "internal_devices", new /obj/item/reagent_scanner(src))
	own_add(src, "internal_devices", new /obj/item/assembly/signaler(src))

/obj/item/commcard/head/rd/get_data()
	var/list/data = ..()
	// Signaler access
	data[++data.len] = list("field" = "signaler_access", "value" = get_int_signalers())
	return data

// Chief Medical Officer Cartridge:
// Devices
//  *- Health Analyzer
//  *- Reagent Scanner
//  *- Halogen Counter
// Templates
//  *- Status Display Access
//  *- Employment Records
//  *- Medical Records
/obj/item/commcard/head/cmo
	name = "\improper Med-U DELUXE"
	icon_state = "cart-cmo"
	ui_templates = list(
			list("name" = "Status Display Access", "template" = "stat_display_access.tmpl"),
			list("name" = "Employment Records", "template" = "emp_records.tmpl"),
			list("name" = "Medical Records", "template" = "med_records.tmpl")
		)

/obj/item/commcard/head/cmo/Initialize(mapload)
	. = ..()
	own_add(src, "internal_devices", new /obj/item/healthanalyzer(src))
	own_add(src, "internal_devices", new /obj/item/reagent_scanner(src))
	own_add(src, "internal_devices", new /obj/item/halogen_counter(src))

/obj/item/commcard/head/cmo/get_data()
	var/list/data = ..()
	// Med records
	data[++data.len] = list("field" = "med_records", "value" = get_med_records())
	return data

// Chief Engineer Cartridge:
// Devices
//  *- Gas Scanner
//  *- Halogen Counter
// Templates
//  *- Status Display Access
//  *- Employment Records
//  *- Power Monitoring
/obj/item/commcard/head/ce
	name = "\improper Power-On DELUXE"
	icon_state = "cart-ce"
	ui_templates = list(
			list("name" = "Status Display Access", "template" = "stat_display_access.tmpl"),
			list("name" = "Employment Records", "template" = "emp_records.tmpl"),
			list("name" = "Power Monitor", "template" = "comm_power_monitor.tmpl")
		)

/obj/item/commcard/head/ce/Initialize(mapload)
	..()
	own_add(src, "internal_devices", new /obj/item/analyzer(src))
	own_add(src, "internal_devices", new /obj/item/halogen_counter(src))
	return INITIALIZE_HINT_LATELOAD

/obj/item/commcard/head/ce/LateInitialize()
	. = ..()
	internal_data["grid_sensors"] = find_powernet_sensors()
	internal_data["powernet_target"] = ""

/obj/item/commcard/head/ce/get_data()
	var/list/data = ..()
	// Add power monitoring data
	data[++data.len] = list("field" = "powernet_monitoring", "value" = get_powernet_monitoring_list())
	data[++data.len] = list("field" = "powernet_target", "value" = get_powernet_target(internal_data["powernet_target"]))
	return data

// Captain Cartridge:
// Devices
//  *- Health analyzer
//  *- Gas Scanner
//  *- Reagent Scanner
//  *- Halogen Counter
//  X- GPS - Balance
//  *- Signaler
// Templates
//  *- Status Display Access
//  *- Employment Records
//  *- Medical Records
//  *- Security Records
//  *- Power Monitoring
//  *- Supply Records
//  X- Supply Bot Access - Mulebots usually break when used
//  *- Security Bot Access
//  *- Janitorial Locator Magicbox
//  X- GPS Access - Balance
//  *- Signaler Access
/obj/item/commcard/head/captain
	name = "\improper Value-PAK cartridge"
	desc = "Now with 200% more value!"
	icon_state = "cart-c"
	ui_templates = list(
			list("name" = "Status Display Access", "template" = "stat_display_access.tmpl"),
			list("name" = "Employment Records", "template" = "emp_records.tmpl"),
			list("name" = "Medical Records", "template" = "med_records.tmpl"),
			list("name" = "Security Records", "template" = "sec_records.tmpl"),
			list("name" = "Security Bot Control", "template" = "sec_bot_access.tmpl"),
			list("name" = "Power Monitor", "template" = "comm_power_monitor.tmpl"),
			list("name" = "Supply Records", "template" = "supply_records.tmpl"),
			list("name" = "Janitorial Supply Locator", "template" = "janitorialLocator.tmpl"),
			list("name" = "Integrated Signaler Control", "template" = "signaler_access.tmpl")
		)

/obj/item/commcard/head/captain/Initialize(mapload)
	. = ..()
	own_add(src, "internal_devices", new /obj/item/analyzer(src))
	own_add(src, "internal_devices", new /obj/item/healthanalyzer(src))
	own_add(src, "internal_devices", new /obj/item/reagent_scanner(src))
	own_add(src, "internal_devices", new /obj/item/halogen_counter(src))
	own_add(src, "internal_devices", new /obj/item/assembly/signaler(src))

/obj/item/commcard/head/captain/get_data()
	var/list/data = ..()
	//Med records
	data[++data.len] = list("field" = "med_records", "value" = get_med_records())

	// Sec records
	data[++data.len] = list("field" = "sec_records", "value" = get_sec_records())

	// Sec bot access
	data[++data.len] = list("field" = "sec_bot_access", "value" = get_sec_bot_access())

	// Power Monitoring
	data[++data.len] = list("field" = "powernet_monitoring", "value" = get_powernet_monitoring_list())
	data[++data.len] = list("field" = "powernet_target", "value" = get_powernet_target(internal_data["powernet_target"]))

	// Supply records data
	var/list/shuttle_status = get_supply_shuttle_status()
	var/list/orders = get_supply_orders()
	var/list/receipts = get_supply_receipts()
	var/list/misc_supply_data = get_misc_supply_data() // Packaging this stuff externally so it's less hardcoded into the specific cartridge
	var/list/pack_list = list() // List of supply packs within the currently selected category

	if(internal_data["supply_category"])
		pack_list = get_supply_pack_list()

	data[++data.len] = list("field" = "shuttle_auth",	 "value" = misc_supply_data["shuttle_auth"])
	data[++data.len] = list("field" = "order_auth",		 "value" = misc_supply_data["order_auth"])
	data[++data.len] = list("field" = "supply_points",	 "value" = misc_supply_data["supply_points"])
	data[++data.len] = list("field" = "categories",		 "value" = misc_supply_data["supply_categories"])
	data[++data.len] = list("field" = "contraband",		 "value" = misc_supply_data["contraband"])
	data[++data.len] = list("field" = "active_category", "value" = internal_data["supply_category"])
	data[++data.len] = list("field" = "shuttle",		 "value" = shuttle_status)
	data[++data.len] = list("field" = "orders",			 "value" = orders)
	data[++data.len] = list("field" = "receipts",		 "value" = receipts)
	data[++data.len] = list("field" = "supply_packs",	 "value" = pack_list)

	// Janitorial locator magicbox
	data[++data.len] = list("field" = "janidata", "value" = get_janitorial_locations())

	// Signaler access
	data[++data.len] = list("field" = "signaler_access", "value" = get_int_signalers())

	return data

// Mercenary Cartridge
// Templates
//  *- Merc Shuttle Door Controller
/obj/item/commcard/mercenary
	name = "\improper Detomatix cartridge"
	icon_state = "cart"
	ui_templates = list(
			list("name" = "Shuttle Blast Door Control", "template" = "merc_blast_door_control.tmpl")
		)

/obj/item/commcard/mercenary/Initialize(mapload)
	. = ..()
	internal_data["shuttle_door_code"] = "smindicate" // Copied from PDA code
	internal_data["shuttle_doors"] = find_blast_doors()

/obj/item/commcard/mercenary/get_data()
	var/door_status[0]
	for(var/obj/machinery/door/blast/B in internal_data["shuttle_doors"])
		door_status[++door_status.len] += list(
				"open" = B.density,
				"name" = B.name,
				"ref" = "\ref[B]"
			)

	return list(
			list("field" = "blast_door", "value" = door_status)
		)

// Explorer Cartridge
// Devices
//  *- GPS
// Templates
//  *- GPS Access

// IMPORTANT: NOT MAPPED IN DUE TO BALANCE CONCERNS RE: FINDING THE VICTIMS OF ANTAGS.
// See suit sensors, specifically ease of turning them off, and variable level of settings which may or may not give location
// A GPS in your phone that is either broadcasting position or totally off, and can be hidden in pockets, coats, bags, boxes, etc, is much harder to disable
/obj/item/commcard/explorer
	name = "\improper Explorator cartridge"
	icon_state = "cart-tox"
	ui_templates = list(
			list("name" = "Integrated GPS", "template" = "gps_access.tmpl")
		)

/obj/item/commcard/explorer/Initialize(mapload)
	. = ..()
	own_add(src, "internal_devices", new /obj/item/gps/explorer(src))

/obj/item/commcard/explorer/get_data()
	var/list/gps_lists = get_GPS_lists()

	return list(
			list("field" = "gps_access", "value" = gps_lists[1]),
			list("field" = "gps_signal", "value" = gps_lists[2]),
			list("field" = "gps_status", "value" = gps_lists[3])
		)
