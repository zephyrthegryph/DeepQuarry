// This is the base type that handles everything. Subtypes can be easily created by tweaking variables in this file to your liking.

/obj/item/modular_computer
	name = "Modular Computer"
	desc = "A modular computer. You shouldn't see this."

	var/screen_on = 1										// Whether the computer is active/opened/it's screen is on.
	var/device_theme = "ntos"								// Sets the theme for the main menu, hardware config, and file browser apps. Overridden by certain non-NT devices.
	var/tmp/datum/computer_file/program/active_program	// A currently active program running on the computer.
	var/hardware_flag = 0									// A flag that describes this device type
	var/last_power_usage = 0								// Last tick power usage of this computer
	var/last_battery_percent = 0							// Used for deciding if battery percentage has chandged
	var/last_world_time = "00:00"
	var/list/last_header_icons
	var/computer_emagged = FALSE							// Whether the computer is emagged.
	var/apc_powered = FALSE									// Set automatically. Whether the computer used APC power last tick.
	var/base_active_power_usage = 50						// Power usage when the computer is open (screen is active) and can be interacted with. Remember hardware can use power too.
	var/base_idle_power_usage = 5							// Power usage when the computer is idle and screen is off (currently only applies to laptops)
	var/bsod = FALSE										// Error screen displayed

	// Modular computers can run on various devices. Each DEVICE (Laptop, Console, Tablet,..)
	// must have it's own DMI file. Icon states must be called exactly the same in all files, but may look differently
	// If you create a program which is limited to Laptops and Consoles you don't have to add it's icon_state overlay for Tablets too, for example.

	icon = null												// This thing isn't meant to be used on it's own. Subtypes should supply their own icon.
	blocks_emissive = EMISSIVE_BLOCK_NONE
	var/overlay_icon = null									// Icon file used for overlays
	icon_state = null
	center_of_mass_x = 0
	center_of_mass_y = 0									// No pixelshifting by placing on tables, etc.
	randpixel = 0											// And no random pixelshifting on-creation either.
	var/icon_state_unpowered = null							// Icon state when the computer is turned off
	var/icon_state_menu = "menu"							// Icon state overlay when the computer is turned on, but no program is loaded that would override the screen.
	var/icon_state_screensaver = null
	var/max_hardware_size = 0								// Maximal hardware size. Currently, tablets have 1, laptops 2 and consoles 3. Limits what hardware types can be installed.
	var/steel_sheet_cost = 5								// Amount of steel sheets refunded when disassembling an empty frame of this computer.
	var/light_strength = 0									// Intensity of light this computer emits. Comparable to numbers light fixtures use.
	var/list/idle_threads							// Idle programs on background (a relation list: the hard drive owns them). They still receive process calls but can't be interacted with.

	// The chassis uses integrity. Below integrity_failure the computer ceases to
	// operate; at zero it breaks apart.
	max_integrity = 100
	integrity_failure = 0.5

	// Important hardware (must be installed for computer to work)
	var/obj/item/computer_hardware/processor_unit/processor_unit				// CPU. Without it the computer won't run. Better CPUs can run more programs at once.
	var/obj/item/computer_hardware/network_card/network_card					// Network Card component of this computer. Allows connection to NTNet
	var/obj/item/computer_hardware/hard_drive/hard_drive						// Hard Drive component of this computer. Stores programs and files.

	// Optional hardware (improves functionality, but is not critical for computer to work in most cases)
	var/obj/item/computer_hardware/battery_module/battery_module				// An internal power source for this computer. Can be recharged.
	var/obj/item/computer_hardware/card_slot/card_slot						// ID Card slot component of this computer. Mostly for HoP modification console that needs ID slot for modification.
	var/obj/item/computer_hardware/nano_printer/nano_printer					// Nano Printer component of this computer, for your everyday paperwork needs.
	var/obj/item/computer_hardware/hard_drive/portable/portable_drive	// Portable data storage
	var/tmp/datum/ai_slot	// AI slot, an intellicard housing that allows modifications of AIs.
	var/obj/item/computer_hardware/tesla_link/tesla_link						// Tesla Link, Allows remote charging from nearest APC.

	var/modifiable = TRUE	// can't be modified or damaged if false

	var/stores_pen = FALSE
	var/tmp/obj/item/pen/stored_pen

	var/interact_sounds
	var/interact_sound_volume = 40


/// A currently active program running on the computer. (a relation view: null once that is deleted).
/obj/item/modular_computer/proc/active_program() as /datum/computer_file/program
	return active_program

/// AI slot, an intellicard housing that allows modifications of AIs. (a relation view: null once that is deleted).
/obj/item/modular_computer/proc/ai_slot()
	return ai_slot

/// The stored_pen this refers to (a relation view: null once that is deleted).
/obj/item/modular_computer/proc/stored_pen() as /obj/item/pen
	return stored_pen

TRACKED(/obj/item/modular_computer, bsod)

MSG_DEF_SELF(modular_computer/already_on, "it is already on")

CAPABILITIES(/obj/item/modular_computer)
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0),
		asks(/datum/prompt/choice, fields = list("question" = "Which component do you want to uninstall?", "title" = "Computer maintenance", "choices" = computed(PROC_REF(component_names))), step = "component", when = PROC_REF(has_components)),
		then(PROC_REF(screwdriver_used)))
	ref_many(nameof(paired_uavs))
	owns_one(nameof(processor_unit), /obj/item/computer_hardware/processor_unit)
	owns_one(nameof(network_card), /obj/item/computer_hardware/network_card)
	owns_one(nameof(hard_drive), /obj/item/computer_hardware/hard_drive)
	owns_one(nameof(battery_module), /obj/item/computer_hardware/battery_module)
	owns_one(nameof(card_slot), /obj/item/computer_hardware/card_slot)
	owns_one(nameof(nano_printer), /obj/item/computer_hardware/nano_printer)
	owns_one(nameof(portable_drive), /obj/item/computer_hardware/hard_drive/portable)
	owns_one(nameof(tesla_link), /obj/item/computer_hardware/tesla_link)
	every(2 SECONDS, then(PROC_REF(modular_computer_step)), when = nameof(enabled))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	interface("NtosMain", autoupdate = TRUE)
	// A welder repairs the casing: as long as the damage says, for the fuel the damage says, both fixed when the weld starts.
	op("weld_repair", tool(TOOL_WELDER), label("Repair"), needs(req(PROC_REF(needs_repair), because = MSG(modular_computer/no_repairs))), begins(MSG(modular_computer/welding)), costs(RES_FUEL, PROC_REF(weld_fuel), locked = TRUE), wait(PROC_REF(weld_time)), says(MSG(modular_computer/welded)), then(PROC_REF(weld_repair_done)))
	without("ui_open")
	op("PC_exit", ui_act("PC_exit"), then(PROC_REF(ui_act_pc_exit)))
	op("PC_shutdown", ui_act("PC_shutdown"), then(PROC_REF(ui_act_pc_shutdown)))
	op("PC_minimize", ui_act("PC_minimize"), then(PROC_REF(ui_act_pc_minimize)))
	op("PC_killprogram", ui_act("PC_killprogram", arg("name", schema_text(4096))), then(PROC_REF(ui_act_pc_killprogram)))
	op("PC_runprogram", ui_act("PC_runprogram", arg("name", schema_text(4096))), then(PROC_REF(ui_act_pc_runprogram)))
	op("PC_setautorun", ui_act("PC_setautorun", arg("name", schema_text(4096))), then(PROC_REF(ui_act_pc_setautorun)))
	op("PC_Eject_Disk", ui_act("PC_Eject_Disk", arg("name", schema_text(4096))), then(PROC_REF(ui_act_pc_eject_disk)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(computer_blast_damage))))
	op("interaction_hand", hand(), priority(OP_PRIORITY_DEFAULT - 1), when(req_is(nameof(anchored))), then(PROC_REF(interaction_hand)))
	op("interaction_hand_pai", hand(), priority(OP_PRIORITY_DEFAULT - 2), when(req_actor_kind(/mob/living/silicon/pai)), then(PROC_REF(interaction_hand)))
	op("interaction_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_self)))
	op("interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_item)))
	op("modular_computer_silicon_use", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(modular_computer_silicon_use)))
	op("modular_computer_ghost_view", observer(), label("View"), when(req_is(nameof(enabled))), then(PROC_REF(modular_computer_ghost_view)))
	op("modular_computer_ghost_power", observer(), priority(OP_PRIORITY_NORMAL + 1), label("View"), needs(req_is(nameof(enabled), FALSE, because = MSG(modular_computer/already_on)), req_rights(R_ADMIN|R_EVENT|R_DEBUG)), asks(/datum/prompt/choice, fields = list("question" = "This computer is turned off. Would you like to turn it on?", "title" = "Admin Override", "choices" = list("Yes", "No"), "buttons" = TRUE, "timeout" = 0), step = "k98"), then(PROC_REF(modular_computer_ghost_power)))
	op("modular_computer_ghost_nothing", observer(), priority(OP_PRIORITY_DEFAULT - 1), then(TYPE_PROC_REF(/atom, op_swallow)))
	op("computer_emergency_shutdown", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Forced Shutdown"), needs(req_adjacent(), req(PROC_REF(pred_computer_hands_on))), then(PROC_REF(computer_emergency_shutdown)))
	op("computer_verb_eject_id", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Eject ID"), when(req(PROC_REF(pred_computer_has_card_slot))), needs(req_adjacent(), req(PROC_REF(pred_computer_hands_on))), then(PROC_REF(computer_verb_eject_id)))
	op("computer_verb_eject_usb", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Eject Portable Storage"), when(req(PROC_REF(pred_computer_has_drive))), needs(req_adjacent(), req(PROC_REF(pred_computer_hands_on))), then(PROC_REF(computer_verb_eject_usb)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(computer_emp_damage)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))


/// Whether the computer is turned on. its every() runs its programs while it is.
/obj/item/modular_computer/var/enabled = FALSE
TRACKED(/obj/item/modular_computer, enabled)
