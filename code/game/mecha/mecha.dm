/obj/mecha
	name = "Mecha"
	desc = "Exosuit"
	icon = 'icons/mecha/mecha.dmi'
	density = TRUE							//Dense. To raise the heat.
	opacity = 1							//Opaque. Menacing.
	anchored = TRUE						//No pulling around.
	unacidable = TRUE						//And no deleting hoomans inside
	layer = MOB_LAYER					//Icon draw layer
	infra_luminosity = 15				//Byond implementation is bugged.
	var/initial_icon = null				//Mech type for resetting icon. Only used for reskinning kits (see custom items)
	var/can_move = 1

	var/step_in = 10					//Make a step in step_in/10 sec.
	var/encumbrance_gap = 1			//How many points of slowdown are negated from equipment? Added to the mech's base step_in.

	var/dir_in = 2						//What direction will the mech face when entered/powered on? Defaults to South.
	var/step_energy_drain = 10
	max_integrity = 300 				//Chassis HP, backed by the TG atom_integrity system.

	var/damage_minimum = 10				//Incoming damage lower than this won't actually deal damage. Scrapes shouldn't be a real thing.
	var/minimum_penetration = 15		//Incoming damage won't be fully applied if you don't have at least 20. Almost all AP clears this.
	var/fail_penetration_value = 0.66	//By how much failing to penetrate reduces your shit. 66% by default. 100dmg = 66dmg if failed pen

	var/obj/item/cell/cell
	var/state = MECHA_OPERATING
	/// Passengers in the compartments, kept by the compartments' slot changes (mecha_passenger_changed()); the tracked mirror a requirement reads.
	var/passenger_count = 0
	var/list/log = list() // ALLOW(instance_list): d: mech log (generic name, too many ambiguous call sites)
	EXPIRY_DECLARE(last_message)
	var/add_req_access = 1
	var/maint_access = 1
	var/dna								//Dna-locking the mech
	/// The active ion jetpack; when set, movement goes through its dyndomove().
	var/obj/item/mecha_parts/mecha_equipment/tool/jetpack/active_jetpack
	/// The attached energy relay; when set, charge reads go through its dyngetcharge().
	var/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/energy_relay
	var/lights = 0
	var/lights_power = 6
	var/force = 0
	/// INJURY_* kind this mecha's melee strikes inflict on living targets (fists = BLUNT, torch = BURN, needle = TOXIN, phase stun = PAIN).
	var/melee_injury_kind = INJURY_BLUNT

	var/mech_faction = null
	var/firstactivation = 0 			//It's simple. If it's 0, no one entered it yet. Otherwise someone entered it at least once.

	var/stomp_sound = 'sound/mecha/mechstep.ogg'
	var/stomp_sound_2 = 'sound/mecha/mechstep.ogg' // Used for 1-2 step patterns instead of random choice.
	var/swivel_sound = SFX_MECHA_MECHTURN
	var/reps = 0 // Used for 1-2 step patterns.

	//inner atmos
	var/use_internal_tank = 0
	var/internal_tank_valve = ONE_ATMOSPHERE
	// was ZAS portable canister; now a regular oxygen tank since the
	// ZAS portable machinery was deleted.
	var/obj/item/tank/internal_tank
	var/datum/gas_mixture/cabin_air
	var/obj/machinery/atmospherics/portables_connector/connected_port = null

	var/obj/item/radio/radio = null

	var/max_temperature = 25000			//Kelvin values.
	var/internal_damage_threshold = 33	//Health percentage below which internal damage is possible
	var/internal_damage_minimum = 15	//At least this much damage to trigger some real bad hurt.
	/// Active afflictions (/datum/mech_affliction flyweights), managed by mech_body_plan().
	var/list/afflictions

	// ALLOW(instance_list): d: access list passed to check_access(); an empty list and null differ for some checks
	var/list/operation_req_access = list()								//Required access level for mecha operation
	var/static/list/internals_req_access = list(ACCESS_ENGINE,ACCESS_ROBOTICS)	//Required access level to open cell compartment

	var/wreckage
	/// Set when the mech is destroyed in play (integrity ran out), not merely deleted: only then
	/// does on_destroy() leave `wreckage`.
	var/tmp/wrecked = FALSE
	/// The wreckage a mech destroyed in play leaves (made in on_destroy()): where its cell and tank are handed over.
	var/tmp/obj/effect/decal/mecha_wreckage/wreck

	// ALLOW(instance_list): d: mech equipment list; many call sites index and edit it directly
	var/list/equipment = list()		//This lists holds what stuff you bolted onto your baby ride
	var/obj/item/mecha_parts/mecha_equipment/selected
	var/max_equip = 2

	// What direction to float in, if inertial movement is active.
	var/float_direction = 0
	// Process() iterator count.
	var/process_ticks = 0

//mechaequipt2 stuffs
	var/list/hull_equipment
	var/list/weapon_equipment
	var/list/utility_equipment
	var/list/universal_equipment
	var/list/special_equipment
	var/max_hull_equip = 2
	var/max_weapon_equip = 2
	var/max_utility_equip = 2
	var/max_universal_equip = 2
	var/max_special_equip = 1


// Mech Components, similar to Cyborg, but Bigger.
	var/list/internal_components = list( // ALLOW(instance_list): d: edited in place per instance (2 writers)
		MECH_HULL = null,
		MECH_ACTUATOR = null,
		MECH_ARMOR = null,
		MECH_GAS = null,
		MECH_ELECTRIC = null
		)

//Working exosuit vars
	var/list/cargo
	var/cargo_capacity = 3

	var/static/image/radial_image_eject = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_eject")
	var/static/image/radial_image_airtoggle = image(icon= 'icons/mob/radial.dmi', icon_state = "radial_airtank")
	var/static/image/radial_image_lighttoggle = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_light")
	var/static/image/radial_image_statpanel = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_examine2")

//Mech actions
	var/datum/mini_hud/mech/minihud
	var/strafing = 0 				//Are we strafing or not?

	var/defence_mode_possible = 0 	//Can we even use defence mode? This is used to assign it to mechs and check for verbs.
	var/defence_mode = 0 			//Are we in defence mode

	var/overload_possible = 0 		//Same as above. Don't forget to GRANT the verb&actions if you want everything to work proper.
	var/overload = 0 				//Are our legs overloaded
	var/overload_coeff = 1			//How much extra energy you use when use the L E G

	var/zoom = 0
	var/zoom_possible = 0

	var/thrusters = 0
	var/thrusters_possible = 0

	var/phasing = 0					//Are we currently phasing
	var/phasing_possible = 0		//This is to allow phasing.
	var/can_phase = TRUE			//This is an internal check during the relevant procs.
	var/phasing_energy_drain = 200

	var/switch_dmg_type_possible = 0	//Can you switch damage type? It is mostly for the Phazon and its children.

	var/smoke_possible = 0
	var/smoke_reserve = 5			//How many shots you have. Might make a reload later on. MIGHT.
	COOLDOWN_DECLARE(smoke_cooldown_end)
	var/smoke_cooldown = 100		//How long you have between uses.
	var/datum/effect/effect/system/smoke_spread/smoke_system

	var/cloak_possible = FALSE		// Can this exosuit innately cloak?

////All of those are for the HUD buttons in the top left. See Grant and Remove procs in mecha_actions.

	var/datum/action/innate/mecha/mech_eject/eject_action
	var/datum/action/innate/mecha/mech_toggle_internals/internals_action
	var/datum/action/innate/mecha/mech_toggle_lights/lights_action
	var/datum/action/innate/mecha/mech_view_stats/stats_action
	var/datum/action/innate/mecha/strafe/strafing_action

	var/datum/action/innate/mecha/mech_defence_mode/defence_action
	var/datum/action/innate/mecha/mech_overload_mode/overload_action
	var/datum/action/innate/mecha/mech_smoke/smoke_action
	var/datum/action/innate/mecha/mech_zoom/zoom_action
	var/datum/action/innate/mecha/mech_toggle_thrusters/thrusters_action
	var/datum/action/innate/mecha/mech_cycle_equip/cycle_action
	var/datum/action/innate/mecha/mech_switch_damtype/switch_damtype_action
	var/datum/action/innate/mecha/mech_toggle_phasing/phasing_action
	var/datum/action/innate/mecha/mech_toggle_cloaking/cloak_action

	var/weapons_only_cycle = FALSE	//So combat mechs don't switch to their equipment at times.

	//Micro Mech Code
	/// TRUE while temperature control runs: the cabin's heat pump exists exactly while this is set.
	var/cabin_regulating = FALSE
	var/max_micro_utility_equip = 0
	var/max_micro_weapon_equip = 0
	var/list/micro_utility_equipment
	var/list/micro_weapon_equipment

/// Electrical rating of the cabin's temperature control, W: about 10 K per 2 s on a 200 L cabin, as the old normaliser.
#define MECHA_CABIN_REGULATOR_WATTS 1000

TRACKED(/obj/mecha, cabin_regulating)
TRACKED(/obj/mecha, state)
TRACKED(/obj/mecha, passenger_count)

MSG_DEF_SELF(mecha_passenger/none, "There are no passengers to remove.")

CAPABILITIES(/obj/mecha)
	// The climb in and the brain install are the actor's four seconds; the held item may change (IGNORE_HELD_ITEM).
	op("climb_in", ai(), wait(4 SECONDS, keeps = ADJACENT | TARGET_PRESENT | ALIVE | STAY), on_interrupt(PROC_REF(climb_in_interrupted)), then(PROC_REF(climb_in_done)))
	op("mmi_install", ai(), takes("mmi"), wait(4 SECONDS, keeps = ADJACENT | TARGET_PRESENT | ALIVE | STAY), on_interrupt(PROC_REF(mmi_install_interrupted)), then(PROC_REF(mmi_install_done)))
	// Temperature control: a heat pump between the cabin air and the air outside, toward 20 C, paid from the cell (process_preserve_temp()).
	when(nameof(cabin_regulating), heat_pump(nameof(cabin_air), HEAT_AIR, MECHA_CABIN_REGULATOR_WATTS, T20C, HEAT_PUMP_BOTH, TRUE, power_draw = FALSE))
	owns_one(nameof(cabin_air), on_destroy = ON_DESTROY_PRIVATE_COPY)
	// A mech destroyed in play leaves wreckage (on_destroy() makes it): its cell and tank become the wreckage's salvage. A plain qdel leaves none, and they are
	// deleted with the mech. (The components detach from the mech as they go, so on_destroy() hands those over itself.)
	owns_one(nameof(cell), /obj/item/cell, on_destroy = ON_DESTROY_HAND_OVER, successor = nameof(wreck), successor_var = nameof(wreck.crowbar_salvage))
	owns_one(nameof(internal_tank), /obj/item/tank, on_destroy = ON_DESTROY_HAND_OVER, successor = nameof(wreck), successor_var = nameof(wreck.crowbar_salvage))
	// The equipment lists are views of what is bolted on: they are cleared with the mech (the equipment itself is handled in on_destroy()).
	ref_many(nameof(equipment), /obj/item/mecha_parts/mecha_equipment)
	ref_many(nameof(hull_equipment), /obj/item/mecha_parts/mecha_equipment)
	ref_many(nameof(weapon_equipment), /obj/item/mecha_parts/mecha_equipment)
	ref_many(nameof(utility_equipment), /obj/item/mecha_parts/mecha_equipment)
	ref_many(nameof(universal_equipment), /obj/item/mecha_parts/mecha_equipment)
	ref_many(nameof(special_equipment), /obj/item/mecha_parts/mecha_equipment)
	owns_one(nameof(minihud), /datum/mini_hud/mech)
	owns_many(nameof(internal_components))
	owns_one(nameof(radio), /obj/item/radio)
	owns_one(nameof(eject_action), /datum/action/innate/mecha/mech_eject, starts = /datum/action/innate/mecha/mech_eject)
	owns_one(nameof(internals_action), /datum/action/innate/mecha/mech_toggle_internals, starts = /datum/action/innate/mecha/mech_toggle_internals)
	owns_one(nameof(lights_action), /datum/action/innate/mecha/mech_toggle_lights, starts = /datum/action/innate/mecha/mech_toggle_lights)
	owns_one(nameof(stats_action), /datum/action/innate/mecha/mech_view_stats, starts = /datum/action/innate/mecha/mech_view_stats)
	every(2 SECONDS, then(PROC_REF(mecha_step)), when = PROC_REF(cabin_gate))
	owns_one(nameof(strafing_action), /datum/action/innate/mecha/strafe, starts = /datum/action/innate/mecha/strafe)
	owns_one(nameof(defence_action), /datum/action/innate/mecha/mech_defence_mode, starts = /datum/action/innate/mecha/mech_defence_mode)
	owns_one(nameof(overload_action), /datum/action/innate/mecha/mech_overload_mode, starts = /datum/action/innate/mecha/mech_overload_mode)
	owns_one(nameof(smoke_action), /datum/action/innate/mecha/mech_smoke, starts = /datum/action/innate/mecha/mech_smoke)
	owns_one(nameof(zoom_action), /datum/action/innate/mecha/mech_zoom, starts = /datum/action/innate/mecha/mech_zoom)
	owns_one(nameof(thrusters_action), /datum/action/innate/mecha/mech_toggle_thrusters, starts = /datum/action/innate/mecha/mech_toggle_thrusters)
	owns_one(nameof(cycle_action), /datum/action/innate/mecha/mech_cycle_equip, starts = /datum/action/innate/mecha/mech_cycle_equip)
	owns_one(nameof(switch_damtype_action), /datum/action/innate/mecha/mech_switch_damtype, starts = /datum/action/innate/mecha/mech_switch_damtype)
	owns_one(nameof(phasing_action), /datum/action/innate/mecha/mech_toggle_phasing, starts = /datum/action/innate/mecha/mech_toggle_phasing)
	owns_one(nameof(cloak_action), /datum/action/innate/mecha/mech_toggle_cloaking, starts = /datum/action/innate/mecha/mech_toggle_cloaking)
	owns_one(nameof(smoke_system), /datum/effect/effect/system/smoke_spread, starts = /datum/effect/effect/system/smoke_spread)
	interface("MechaInterface", autoupdate = TRUE)
	without("ui_open")
	op("rfreq", ui_act("rfreq", arg("delta", num())), then(PROC_REF(ui_act_rfreq)))
	op("drop_from_cargo", ui_act("drop_from_cargo", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_drop_from_cargo)))
	op("detach_equipment", ui_act("detach_equipment", arg("ref", schema_ref(/obj/item/mecha_parts/mecha_equipment))), then(PROC_REF(ui_act_detach_equipment)))
	op("equip_interact", ui_act("equip_interact", arg("ref", schema_ref(/obj/item/mecha_parts/mecha_equipment))), then(PROC_REF(ui_act_equip_interact)))
	op("view_main", ui_act("view_main"), then(PROC_REF(ui_act_view_main)))
	op("ai_use_equipment", ui_act("ai_use_equipment", arg("ref", schema_ref(/obj/item/mecha_parts/mecha_equipment))), then(PROC_REF(ui_act_ai_use_equipment)))
	op("access_add", ui_act("access_add", arg("id", num())), then(PROC_REF(ui_act_access_add)))
	op("access_del", ui_act("access_del", arg("id", num())), then(PROC_REF(ui_act_access_del)))
	op("access_finish", ui_act("access_finish"), then(PROC_REF(ui_act_access_finish)))
	op("maint_req_access", ui_act("maint_req_access"), then(PROC_REF(ui_act_maint_req_access)))
	op("maint_protocol", ui_act("maint_protocol"), then(PROC_REF(ui_act_maint_protocol)))
	op("maint_set_air", ui_act("maint_set_air"), then(PROC_REF(ui_act_maint_set_air)))
	op("maint_remove_passenger", ui_act("maint_remove_passenger"), then(PROC_REF(ui_act_maint_remove_passenger)))
	op("update_content", topic("update_content"), then(PROC_REF(topic_update_content)))
	op("close", topic("close"), then(PROC_REF(topic_close)))
	op("select_equip", topic("select_equip", arg("select_equip", schema_ref(/obj/item/mecha_parts/mecha_equipment), optional = TRUE, among = PROC_REF(topic_equipment_pool))), then(PROC_REF(topic_select_equip)))
	op("eject", topic("eject"), then(PROC_REF(topic_eject)))
	op("toggle_lights", topic("toggle_lights"), then(PROC_REF(topic_toggle_lights)))
	op("toggle_airtank", topic("toggle_airtank"), then(PROC_REF(topic_toggle_airtank)))
	op("toggle_thrusters", topic("toggle_thrusters"), then(PROC_REF(topic_toggle_thrusters)))
	op("smoke", topic("smoke"), then(PROC_REF(topic_smoke)))
	op("toggle_zoom", topic("toggle_zoom"), then(PROC_REF(topic_toggle_zoom)))
	op("toggle_defence_mode", topic("toggle_defence_mode"), then(PROC_REF(topic_toggle_defence_mode)))
	op("switch_damtype", topic("switch_damtype"), then(PROC_REF(topic_switch_damtype)))
	op("phasing", topic("phasing"), then(PROC_REF(topic_phasing)))
	op("rmictoggle", topic("rmictoggle"), then(PROC_REF(topic_rmictoggle)))
	op("rspktoggle", topic("rspktoggle"), then(PROC_REF(topic_rspktoggle)))
	op("topic_rfreq", topic("rfreq", arg("rfreq", num(), optional = TRUE)), then(PROC_REF(topic_rfreq)))
	op("port_disconnect", topic("port_disconnect"), then(PROC_REF(topic_port_disconnect)))
	op("port_connect", topic("port_connect"), then(PROC_REF(topic_port_connect)))
	op("view_log", topic("view_log"), then(PROC_REF(topic_view_log)))
	op("change_name", topic("change_name"), asks(/datum/prompt/text, fields = list("title" = "Rename exosuit", "question" = "Choose new exosuit name", "default" = computed(PROC_REF(exosuit_default_name)), "max_len" = MAX_NAME_LEN, "encode" = FALSE, "ask_flags" = ASK_INSIDE, "name_text" = TRUE, "timeout" = 0), step = "name"), then(PROC_REF(topic_change_name)))
	op("toggle_id_upload", topic("toggle_id_upload"), then(PROC_REF(topic_toggle_id_upload)))
	op("toggle_maint_access", topic("toggle_maint_access"), then(PROC_REF(topic_toggle_maint_access)))
	op("maint_access", topic("maint_access"), then(PROC_REF(topic_maint_access)))
	op("set_internal_tank_valve", topic("set_internal_tank_valve"), needs(req(PROC_REF(bolts_exposed), silent = TRUE), req_adjacent()), asks(/datum/prompt/number/mecha_tank_valve, fields = list("subject" = computed(PROC_REF(valve_subject)), "default" = computed(PROC_REF(valve_default))), step = "pressure"), then(PROC_REF(topic_set_internal_tank_valve)))
	op("remove_passenger", topic("remove_passenger"), needs(req(PROC_REF(bolts_exposed), silent = TRUE), req_adjacent(), req(PROC_REF(has_passengers))), asks(/datum/prompt/choice/mecha_remove_passenger, fields = list("choices" = computed(PROC_REF(passenger_choices))), step = "passenger"), begins(PROC_REF(remove_passenger_begins)), wait(4 SECONDS), then(PROC_REF(topic_remove_passenger)))
	op("finish_req_access", topic("finish_req_access"), then(PROC_REF(topic_finish_req_access)))
	op("dna_lock", topic("dna_lock"), then(PROC_REF(topic_dna_lock)))
	op("reset_dna", topic("reset_dna"), then(PROC_REF(topic_reset_dna)))
	op("repair_int_control_lost", topic("repair_int_control_lost"), when(PROC_REF(control_lost)), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot_recalibrate))), then(PROC_REF(start_recalibration)))
	mecha_maintenance()
	op("topic_drop_from_cargo", topic("drop_from_cargo", arg("drop_from_cargo", schema_ref(/obj), optional = TRUE, among = PROC_REF(topic_cargo_pool))), then(PROC_REF(topic_drop_from_cargo)))
	op("mecha_paint_kit", item(/obj/item/kit/paint), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(mecha_paint_kit_op)))
	op("mecha_weld_help", item(/obj/item), stance(I_HELP), priority(OP_PRIORITY_DEFAULT - 1), label("Weld repairs"), then(PROC_REF(interaction_mecha_welder)))
	op("mecha_weld_disarm", item(/obj/item), stance(I_DISARM), priority(OP_PRIORITY_DEFAULT - 2), label("Weld repairs"), then(PROC_REF(interaction_mecha_welder)))
	op("mecha_weld_grab", item(/obj/item), stance(I_GRAB), priority(OP_PRIORITY_DEFAULT - 3), label("Weld repairs"), then(PROC_REF(interaction_mecha_welder)))
	op("mecha_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 4), label("Use"), then(PROC_REF(interaction_mecha_item)))
	op("mecha_hand", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_mecha_hand)))
	op("mecha_drag", item(/atom/movable), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Enter exosuit"), then(PROC_REF(interaction_mecha_drag)))
	op("mecha_alt", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle strafing"), then(PROC_REF(interaction_mecha_alt)))
	op("mecha_enter", menu(), label("Enter Exosuit"), then(PROC_REF(mecha_enter_op)))
	op("mecha_enter_passenger", menu(), label("Enter Passenger Compartment"), then(PROC_REF(mecha_enter_passenger_op)))
	op("mecha_eject", menu(), label("Eject"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_eject_op)))
	op("mecha_stats", menu(), label("View Stats"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_stats_op)))
	op("mecha_lights", menu(), label("Toggle Lights"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_lights_op)))
	op("mecha_strafing", menu(), label("Toggle strafing"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_strafing_op)))
	op("mecha_airtank", menu(), label("Toggle internal airtank usage"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_airtank_op)))
	op("mecha_connect", menu(), label("Connect to port"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_connect_op)))
	op("mecha_disconnect", menu(), label("Disconnect from port"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_disconnect_op)))
	op("mecha_defence", menu(), label("Toggle defence mode"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_defence_op)))
	op("mecha_overload", menu(), label("Toggle leg actuators overload"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_overload_op)))
	op("mecha_smoke", menu(), label("Activate Smoke"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_smoke_op)))
	op("mecha_zoom", menu(), label("Zoom"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_zoom_op)))
	op("mecha_thrusters", menu(), label("Toggle thrusters"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_thrusters_op)))
	op("mecha_damtype", menu(), label("Change melee damage type"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_damtype_op)))
	op("mecha_phasing", menu(), label("Toggle phasing"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_phasing_op)))
	op("mecha_cloak", menu(), label("Toggle cloaking"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_cloak_op)))
	op("mecha_weapons_cycle", menu(), label("Toggle weapons only cycling"), needs(req(PROC_REF(pilot_only), because = MSG(mecha/not_pilot))), then(PROC_REF(mecha_weapons_cycle_op)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(mecha_blast))))
	on_notice(/datum/notice/hit/explosion, then(PROC_REF(mecha_blast_afflictions)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(mecha_emp)))

TYPE_TABLE_DECLARE(/obj/mecha, mecha_starting_equipment, null)

TYPE_TABLE_DECLARE(/obj/mecha, mecha_starting_components, list( \
		/obj/item/mecha_parts/component/hull, \
		/obj/item/mecha_parts/component/actuator, \
		/obj/item/mecha_parts/component/armor, \
		/obj/item/mecha_parts/component/gas, \
		/obj/item/mecha_parts/component/electrical \
		))

REGISTRY_MEMBERSHIP(/obj/mecha, REGISTRY_MECHAS)

// Actions and effect systems: declared children (new type(src)); an action's target is the mecha.


/obj/mecha/Initialize(mapload)
	. = ..()

	for(var/path in TYPE_TABLE_GET(src, mecha_starting_components))
		var/obj/item/mecha_parts/component/C = new path(src)
		C.attach(src)

	var/list/starting_equipment_types = TYPE_TABLE_GET(src, mecha_starting_equipment)
	if(starting_equipment_types && LAZYLEN(starting_equipment_types))
		for(var/path in starting_equipment_types)
			var/obj/item/mecha_parts/mecha_equipment/ME = new path(src)
			ME.attach(src)

	update_transform()

	icon_state += "-open"
	add_radio()
	add_cabin()
	add_airtank() // without an internal tank the port/airtank Menu entries are not offered (pred_mecha_has_airtank)

	if(smoke_possible)//I am pretty sure that's needed here.
		src.smoke_system.set_up(3, 0, src)
		src.smoke_system.attach(src)

	add_cell()
	src.mecha_log_message("[src.name] created.")
	loc.Entered(src)

/obj/mecha/drain_power(drain_check)

	if(drain_check)
		return 1

	if(!cell)
		return 0

	return cell.drain_power(drain_check)

/obj/mecha/Exit(atom/movable/O)
	if(O in cargo)
		return 0
	return ..()

// C8a: pilot, equipment and cargo are slots (containment.md §10), so the
// three roles that used to share raw contents each get their own ledger
// entry. Equipment and cargo keep their own capacity checks (max_equip,
// cargo_capacity) and their own component-tier bookkeeping -- the slots only
// carry the move through the ledger so paths, drop policy and the future body
// host interface (C8b) see them; nothing here changes what a hit does today
// (/obj/mecha/receive_damage doesn't call propagate_damage).
/// Sealed: the cabin is the pilot's environment (cabin_air, life support),
/// same as before the ledger tracked the move.
///
/// L1 audit (doc/rewrite/lifecycle.md §3, following the same finding the
/// ledger-joint J1 audit made): HOLDER, not the SLOT_DROP_SPILL default,
/// because go_out() -- called from /obj/mecha/Destroy() -- does the real
/// ejection (mob state cleanup, UI close, verbs, messages), gated on its own
/// slot_remove() reporting a move. The destroy transaction's contents phase
/// now runs *before* any Destroy() code at all, so a generic phase-3 spill
/// would eject the pilot first, and go_out()'s slot_remove() would then find
/// the slot already empty and silently skip all of that cleanup. Turning
/// this into a proper TRANSFER(eject_to_turf) belongs with migrating that
/// cleanup into an on_unslotted() hook (J6) -- domain work, not this pass.
/datum/om/relation/slot/occupant/mecha_pilot
	holder = /obj/mecha
	slot_id = MECHA_SLOT_PILOT
	name = "pilot"
	drop_policy = SLOT_DROP_HOLDER
	// The slot IS the occupant: read it with holder?.slot_item(slot_id).

/// External: equipment is bolted to the hull's hardpoints, not inside it.
/// Capacity stays with mecha_equipment.dm's per-category limits.
///
/// J3 (doc/rewrite/lifecycle.md §3, §8 L1): TRANSFER, not the removed
/// SLOT_DROP_HOLDER -- unlike the pilot slot above, Destroy()'s own
/// equipment loop doesn't gate its wreckage-salvage/detach handling on a
/// move having just succeeded (it walks the `equipment` list by ref and
/// forceMoves unconditionally), so resolving this slot's own move first, in
/// phase 3, is a safe no-op from that loop's point of view -- same
/// destination either way, so the second move it makes is idempotent.
/datum/om/relation/slot/mecha_equipment_hardpoint
	holder = /obj/mecha
	slot_id = MECHA_SLOT_EQUIPMENT
	name = "hardpoint"
	exposure = SLOT_EXPOSURE_EXTERNAL
	capacity_model = SLOT_CAPACITY_NONE
	drop_policy = SLOT_DROP_TRANSFER

/datum/om/relation/slot/mecha_equipment_hardpoint/drop_resolver(atom/holder, atom/movable/thing, atom/drop)
	return get_turf(holder)

/// Internal: the cargo compartment. Capacity stays with cargo_capacity.
/// J3: TRANSFER, same reasoning as mecha_equipment_hardpoint above --
/// Destroy()'s own cargo loop forceMoves to get_turf(src) unconditionally,
/// so this slot resolving to the same turf first is a harmless no-op second
/// move from that loop's point of view.
/datum/om/relation/slot/mecha_cargo
	holder = /obj/mecha
	slot_id = MECHA_SLOT_CARGO
	name = "cargo"
	exposure = SLOT_EXPOSURE_INTERNAL
	capacity_model = SLOT_CAPACITY_NONE
	drop_policy = SLOT_DROP_TRANSFER

/datum/om/relation/slot/mecha_cargo/drop_resolver(atom/holder, atom/movable/thing, atom/drop)
	return get_turf(holder)


// the mech leaves wreckage with salvage, or drops its equipment; pilot slot is holder-resolved.
/obj/mecha/atom_destruction(damage_flag)
	wrecked = TRUE
	return ..()

/obj/mecha/on_destroy(force)
	src.go_out()
	for(var/mob/M in slot_contents()) //Be Extra Sure
		M.forceMove(get_turf(src))
		M.loc.Entered(M)
		if(M != src?.slot_item(MECHA_SLOT_PILOT))
			step_rand(M)
	// The cargo slot (SLOT_DROP_TRANSFER) already put the cargo on the turf in phase 3;
	// it only scatters here.
	for(var/atom/movable/A in src.cargo)
		if(isturf(A.loc))
			step_rand(A)
	LAZYCLEARLIST(cargo)

	if(loc)
		loc.Exited(src)

	// Wreckage (and the chance of a blast) is what a mech destroyed in play leaves.
	// A plain qdel (admin delete, cleanup, a test) takes everything with it.
	if(wrecked && prob(30))
		explosion(get_turf(loc), 0, 0, 1, 3)

	if(wrecked && wreckage)
		var/obj/effect/decal/mecha_wreckage/WR = new wreckage(loc)
		wreck = WR // ALLOW(ownership): names the successor the declared hand-over below uses; a dying holder takes no new relation and the wreckage owns itself
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			if(E.salvageable && prob(30))
				rel_add(WR, nameof(WR.crowbar_salvage), E)
				E.forceMove(WR)
				E.equip_ready = TRUE
			else
				E.forceMove(loc)
				E.destroy()

		for(var/slot in internal_components)
			var/obj/item/mecha_parts/component/C = internal_components[slot]
			if(istype(C))
				C.damage_part(rand(10, 20))
				C.detach()
				rel_add(WR, nameof(WR.crowbar_salvage), C)
				C.forceMove(WR)

		// the cell and tank are handed to `wreck` by their declared policy (CAPABILITIES): the cell comes out part spent.
		if(cell)
			cell.set_charge(rand(0, cell.charge))
	else
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			E.detach(loc)
			E.destroy()
		for(var/slot in internal_components)
			var/obj/item/mecha_parts/component/C = internal_components[slot]
			if(istype(C))
				C.detach()
				ended_with(C, src)

	GLOB.mech_destroyed_roundstat++

	..()

/// These control what toggleable processes are executed within periodic_step() (MECHA_PROC_*).
/obj/mecha/var/current_processes = MECHA_PROC_INT_TEMP
TRACKED(/obj/mecha, current_processes)
/// Derived field: the cabin simulation has something to advance -- a pilot, or inertial movement /
/// internal damage. An empty parked mech with neither does not tick. Pilot entry/exit raise the
/// relation channels (the pilot slot's link).
/// The every() gate: the cabin simulation has something to advance.
/obj/mecha/proc/cabin_gate(datum/act/A)
	return pilot_of() || (current_processes & (MECHA_PROC_MOVEMENT | MECHA_PROC_DAMAGE))

// The main process loop to replace the ancient global iterators.
// It's a bit hardcoded but I don't see anyone else adding stuff to
// mechas, and it's easy enough to modify.
/obj/mecha/proc/mecha_step(datum/act/timer/A)
	var/static/max_ticks = 16

	if (current_processes & MECHA_PROC_MOVEMENT)
		process_inertial_movement()

	if ((current_processes & MECHA_PROC_DAMAGE) && !(process_ticks % 2))
		process_internal_damage()

	if ((current_processes & MECHA_PROC_INT_TEMP) && !(process_ticks % 4))
		process_preserve_temp()

	if (!(process_ticks % 3))
		process_tank_give_air()

	// Max value is 16. So we let it run between [0, 16] with this.
	process_ticks = (process_ticks + 1) % 17

// Cabin temperature control: its heat pump (CAPABILITIES) works in Rust while it runs; this pays its work from the cell.
// Called every fourth process() tick (20 deciseconds).
/obj/mecha/proc/process_preserve_temp()
	set_cabin_regulating(TRUE)
	var/drawn = heat_entries_bill(src)
	if(drawn > 0)
		cell?.use(drawn * CELLRATE)

// Handles internal air tank action.
// Called every third process() tick (15 deciseconds).
/obj/mecha/proc/process_tank_give_air()
	if(internal_tank)
		var/datum/gas_mixture/tank_air = internal_tank.return_air()

		var/release_pressure = internal_tank_valve
		var/cabin_pressure = cabin_air.return_pressure()
		var/pressure_delta = min(release_pressure - cabin_pressure, (tank_air.return_pressure() - cabin_pressure)/2)
		var/transfer_moles = 0

		if(pressure_delta > 0) //cabin pressure lower than release pressure
			if(tank_air.return_temperature() > 0)
				transfer_moles = pressure_delta*cabin_air.return_volume()/(cabin_air.return_temperature() * R_IDEAL_GAS_EQUATION)
				var/datum/gas_mixture/removed = tank_air.remove(transfer_moles)
				cabin_air.merge(removed)

		else if(pressure_delta < 0) //cabin pressure higher than release pressure
			var/datum/gas_mixture/t_air = get_turf_air()
			pressure_delta = cabin_pressure - release_pressure

			if(t_air)
				pressure_delta = min(cabin_pressure - t_air.return_pressure(), pressure_delta)
			if(pressure_delta > 0) //if location pressure is lower than cabin pressure
				transfer_moles = pressure_delta*cabin_air.return_volume()/(cabin_air.return_temperature() * R_IDEAL_GAS_EQUATION)

				var/datum/gas_mixture/removed = cabin_air.remove(transfer_moles)
				if(t_air)
					t_air.merge(removed)
				else //just delete the cabin gas, we're in space or some shit
					spent(removed)

// Inertial movement in space.
// Called every process() tick (5 deciseconds).
/obj/mecha/proc/process_inertial_movement()
	if(float_direction)
		if(!step(src, float_direction) || check_for_support())
			stop_process(MECHA_PROC_MOVEMENT)
	else
		stop_process(MECHA_PROC_MOVEMENT)
	return

// Processes internal damage: each active affliction's tick() (mech_body.dm).
// Called every other process() tick (10 deciseconds).
/obj/mecha/proc/process_internal_damage()
	mech_body_plan().tick(src)

////////////////////////
////// Helpers /////////
////////////////////////

/obj/mecha/proc/add_airtank()
	// the ZAS portable canister type was deleted in the LINDA migration.
	// Mech internal tank now uses /obj/item/tank/air (regular oxygen tank) which
	// has return_air() and persists in the mech's contents.
	rel_set(src, nameof(internal_tank), new /obj/item/tank/air(src))
	return internal_tank

/obj/mecha/proc/add_cell(obj/item/cell/C=null)
	if(C)
		move_into(src, nameof(src.cell), C)
		return
	rel_set(src, nameof(cell), new /obj/item/cell/mech(src))

/obj/mecha/get_cell()
	return cell

/obj/mecha/proc/add_cabin()
	proto_set(src, nameof(cabin_air), new /datum/gas_mixture) // a private mixture the mech owns
	heat_set(cabin_air, T20C)
	cabin_air.set_volume(200)
	// adjust_multi was XGM; LINDA's gas_mixture has adjust_gas per-call.
	var/cabin_volume = cabin_air.return_volume()
	var/cabin_temperature = cabin_air.return_temperature()
	var/moles_o2 = O2STANDARD * cabin_volume / (R_IDEAL_GAS_EQUATION * cabin_temperature)
	var/moles_n2 = N2STANDARD * cabin_volume / (R_IDEAL_GAS_EQUATION * cabin_temperature)
	cabin_air.adjust_gas(GAS_O2, moles_o2)
	cabin_air.adjust_gas(GAS_N2, moles_n2)
	return cabin_air

/obj/mecha/proc/add_radio()
	rel_set(src, nameof(radio), new /obj/item/radio(src))
	radio.name = "[src] radio"
	radio.icon = icon
	radio.icon_state = icon_state
	radio.subspace_transmission = 1

/obj/mecha/proc/recalibration_done(T)
	if(T == src.loc)
		mech_body_plan().cure(src, MECHA_INT_CONTROL_LOST)
		src.occupant_message(span_blue("Recalibration successful."))
		src.mecha_log_message("Recalibration of coordination system finished with 0 errors.")
	else
		src.occupant_message(span_red("Recalibration failed."))
		src.mecha_log_message("Recalibration of coordination system failed with 1 error.",1)

/obj/mecha/proc/check_for_support()
	var/list/things = orange(1, src)

	if(locate_in_list(things, /obj/structure/grille) || locate_in_list(things, /obj/structure/lattice) || locate_in_list(things, /turf/simulated) || locate_in_list(things, /turf/unsimulated))
		return 1
	else
		return 0

/obj/mecha/examine(mob/user)
	. = ..()

	var/obj/item/mecha_parts/component/armor/AC = internal_components[MECH_ARMOR]

	var/obj/item/mecha_parts/component/hull/HC = internal_components[MECH_HULL]

	if(AC)
		. += "It has [AC] attached. [AC.get_efficiency()<0.5?"It is severely damaged.":""]"
	else
		. += "It has no armor plating."

	if(HC)
		if(!AC || AC.get_efficiency() < 0.7)
			. += "It has [HC] attached. [HC.get_efficiency()<0.5?"It is severely damaged.":""]"
		else
			. += "You cannot tell what type of hull it has."

	else
		. += "It does not seem to have a completed hull."

	var/integrity = get_integrity()/max_integrity*100
	switch(integrity)
		if(85 to 100)
			. += "It's fully intact."
		if(65 to 85)
			. += "It's slightly damaged."
		if(45 to 65)
			. += span_notice("It's badly damaged.")
		if(25 to 45)
			. += span_warning("It's heavily damaged.")
		else
			. += span_warning(span_bold(" It's falling apart.") + " ")
	if(equipment?.len)
		. += "It's equipped with:"
		for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
			. += "[icon2html(ME,user.client)] [ME]"

/obj/mecha/proc/drop_item()//Derpfix, but may be useful in future for engineering exosuits.
	return

/obj/mecha/hear_talk(mob/M, list/message_pieces, verb)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(M == occupant && radio.broadcasting)
		radio.talk_into(M, message_pieces)

/obj/mecha/proc/check_occupant_radial(mob/user)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(!user)
		return FALSE
	if(user.stat)
		return FALSE
	if(user != occupant)
		return FALSE
	if(user.incapacitated())
		return FALSE

	return TRUE

/obj/mecha/proc/show_radial_occupant(mob/user)
	var/list/choices = list(
		"Toggle Airtank" = radial_image_airtoggle,
		"Toggle Light" = radial_image_lighttoggle,
		"View Stats" = radial_image_statpanel
	)

	open_request(src, /datum/prompt/choice, PROC_REF(occupant_option_chosen), answerer = user, choices = choices, anchor = src, require_near = TRUE, tooltips = TRUE, radial = TRUE, autopick_single_option = TRUE, timeout = 0)

/obj/mecha/proc/occupant_option_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	var/choice = A.answer.value
	if(!check_occupant_radial(user))
		return
	if(!choice)
		return
	switch(choice)
		if("Toggle Airtank")
			use_internal_tank = !use_internal_tank
			occupant_message("Now taking air from [use_internal_tank?"internal airtank":"environment"].")
			src.mecha_log_message("Now taking air from [use_internal_tank?"internal airtank":"environment"].")
		if("Toggle Light")
			lights = !lights
			if(lights)
				set_light(light_range + lights_power)
			else
				set_light(light_range - lights_power)
			occupant_message("Toggled lights [lights?"on":"off"].")
			src.mecha_log_message("Toggled lights [lights?"on":"off"].")
			play_sfx(src, SFX_MECHA_HEAVYLIGHTSWITCH)
		if("View Stats")
			// TGUI: open MechaInterface.tsx instead of browse().
			tgui_subview = "main"
			tgui_interact(occupant)

////////////////////////////
///// Action processing ////
////////////////////////////

/obj/mecha/proc/click_action(atom/target,mob/user, params)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(!src?.slot_item(MECHA_SLOT_PILOT) || src?.slot_item(MECHA_SLOT_PILOT) != user ) return
	if(user.stat) return
	if(target == src && user == occupant)
		show_radial_occupant(user)
		return
	if(state)
		occupant_message(span_warning("Maintenance protocols in effect"))
		return

	if(phasing)//Phazon and other mechs with phasing.
		src.occupant_message("Unable to interact with objects while phasing")//Haha dumbass.
		return

	if(!get_charge()) return
	if(src == target) return
	var/dir_to_target = get_dir(src,target)
	if(dir_to_target && !(dir_to_target & src.dir))//wrong direction
		return
	if(mech_body_plan().has_affliction(src, MECHA_INT_CONTROL_LOST))
		target = safepick(view(3,target))
		if(!target)
			return
	if(istype(target, /obj/machinery))
		if (src.interface_action(target))
			return
	if(!target.Adjacent(src))
		if(selected && selected.is_ranged())
			selected.action(target, null, user)
	else if(selected && selected.is_melee())
		selected.action(target, params, user)
	else
		src.melee_action(target)
	return

/obj/mecha/proc/interface_action(obj/machinery/target)
	if(istype(target, /obj/machinery/access_button))
		src.occupant_message(span_notice("Interfacing with [target]."))
		src.mecha_log_message("Interfaced with [target].")
		target.attack_hand(src?.slot_item(MECHA_SLOT_PILOT))
		return 1
	if(istype(target, /obj/machinery/embedded_controller))
		target.tgui_interact(src?.slot_item(MECHA_SLOT_PILOT))
		return 1
	return 0

/obj/mecha/contents_tgui_distance(src_object, mob/living/user)
	. = user.shared_living_tgui_distance(src_object) //allow them to interact with anything they can interact with normally.
	if(. != STATUS_INTERACTIVE)
		//Allow interaction with the mecha or anything that is part of the mecha
		if(src_object == src || (src_object in slot_contents()))
			return STATUS_INTERACTIVE
		if(src.Adjacent(src_object))
			src.occupant_message(span_notice("Interfacing with [src_object]..."))
			src.mecha_log_message("Interfaced with [src_object].")
			return STATUS_INTERACTIVE
		if(src_object in view(2, src))
			return STATUS_UPDATE //if they're close enough, allow the occupant to see the screen through the viewport or whatever.

/obj/mecha/proc/melee_action(atom/target)
	return

/obj/mecha/proc/range_action(atom/target)
	return

//////////////////////////////////
////////  Movement procs  ////////
//////////////////////////////////

/obj/mecha/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	MoveAction()

/obj/mecha/proc/MoveAction() //Allows mech equipment to do an action once the mech moves
	if(!equipment.len)
		return

	for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
		ME.MoveAction()

/obj/mecha/relaymove(mob/user,direction)
	if(user != src?.slot_item(MECHA_SLOT_PILOT)) //While not "realistic", this piece is player friendly.
		if(istype(user,/mob/living/carbon/brain))
			if(ELAPSED(src, last_message, CLOCK_WORLD) > 2 SECONDS)
				to_chat(user, span_warning("You try to move, but you are not the pilot! The exosuit doesn't respond."))
				EXPIRY_STAMP(src, last_message, CLOCK_WORLD)
			return 0
		user.forceMove(get_turf(src))
		to_chat(user, "You climb out from [src]")
		return 0

	var/obj/item/mecha_parts/component/hull/HC = internal_components[MECH_HULL]
	if(!HC)
		if(ELAPSED(src, last_message, CLOCK_WORLD) > 2 SECONDS)
			occupant_message(span_notice("You can't operate an exosuit that doesn't have a hull!"))
			EXPIRY_STAMP(src, last_message, CLOCK_WORLD)
		return

	if(connected_port)
		if(ELAPSED(src, last_message, CLOCK_WORLD) > 2 SECONDS)
			src.occupant_message(span_warning("Unable to move while connected to the air system port"))
			EXPIRY_STAMP(src, last_message, CLOCK_WORLD)
		return 0
	if(state)
		if(ELAPSED(src, last_message, CLOCK_WORLD) > 2 SECONDS)
			occupant_message(span_warning("Unable to move whilst in maintenance mode"))
			EXPIRY_STAMP(src, last_message, CLOCK_WORLD)
		return 0
/*
	if(zoom)
		if(ELAPSED(src, last_message, CLOCK_WORLD) > 2 SECONDS)
			src.occupant_message("Unable to move while in zoom mode.")
			EXPIRY_STAMP(src, last_message, CLOCK_WORLD)
		return 0
*/
	return domove(direction)

/obj/mecha/proc/can_ztravel()
	for(var/obj/item/mecha_parts/mecha_equipment/tool/jetpack/jp in equipment)
		return jp.equip_ready
	return FALSE

/obj/mecha/proc/domove(direction)

	if(active_jetpack)
		return active_jetpack.dyndomove(direction)
	return dyndomove(direction)

/obj/mecha/proc/get_step_delay()
	var/tally = 0

	if(LAZYLEN(equipment))
		for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
			if(ME.get_step_delay())
				tally += ME.get_step_delay()

		if(tally <= encumbrance_gap)	// If the total is less than our encumbrance gap, ignore equipment weight.
			tally = 0
		else	// Otherwise, start the tally after cutting that gap out.
			tally -= encumbrance_gap

	for(var/slot in internal_components)
		var/obj/item/mecha_parts/component/C = internal_components[slot]
		if(C && C.get_step_delay())
			tally += C.get_step_delay()

	var/obj/item/mecha_parts/component/actuator/actuator = internal_components[MECH_ACTUATOR]

	if(!actuator)	// Relying purely on hydraulic pumps. You're going nowhere fast.
		tally = 2 SECONDS

		return tally

	tally += 0.5 SECONDS * (1 - actuator.get_efficiency())	// Damaged actuators run slower, slowing as damage increases beyond its threshold.

	if(strafing)
		tally = round(tally * actuator.strafing_multiplier)

	for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
		if(istype(ME, /obj/item/mecha_parts/mecha_equipment/speedboost))
			var/obj/item/mecha_parts/mecha_equipment/speedboost/SB = ME
			for(var/path in ME.required_type)
				if(istype(src, path))
					tally = round(tally * SB.slowdown_multiplier)
					break
			break

	if(overload)	// At the end, because this would normally just make the mech *slower* since tally wasn't starting at 0.
		tally = min(1, round(tally/2))

	return max(1, round(tally, 0.1))	// Round the total to the nearest 10th. Can't go lower than 1 tick. Even humans have a delay longer than that.

/obj/mecha/proc/dyndomove(direction)
	if(!can_move)
		return 0
	if(current_processes & MECHA_PROC_MOVEMENT)
		return 0
	if(!has_charge(step_energy_drain))
		return 0

	//Can we even move, below is if yes.

	if(defence_mode)//Check if we are currently locked down
		if(ELAPSED(src, last_message, CLOCK_WORLD) > 2 SECONDS)
			src.occupant_message(span_red("Unable to move while in defence mode"))
			EXPIRY_STAMP(src, last_message, CLOCK_WORLD)
		return 0

	if(zoom)//:eyes:
		if(ELAPSED(src, last_message, CLOCK_WORLD) > 2 SECONDS)
			src.occupant_message("Unable to move while in zoom mode.")
			EXPIRY_STAMP(src, last_message, CLOCK_WORLD)
		return 0

	if(!thrusters && (current_processes & MECHA_PROC_MOVEMENT)) //I think this mean 'if you try to move in space without thruster, u no move'
		return 0

	if(overload)//Check if you have leg overload
		update_integrity(get_integrity() - 1)
		if(get_integrity() < max_integrity - max_integrity/3)
			overload = 0
			step_energy_drain = initial(step_energy_drain)
			src.occupant_message(span_red("Leg actuators damage threshold exceded. Disabling overload."))

	var/move_result = 0

	if(mech_body_plan().has_affliction(src, MECHA_INT_CONTROL_LOST))
		move_result = mechsteprand()
	//Up/down zmove
	else if(direction == UP || direction == DOWN)
		if(!can_ztravel())
			occupant_message(span_warning("Your vehicle lacks the capacity to move in that direction!"))
			return FALSE

		//We're using locs because some mecha are 2x2 turfs. So thicc!
		var/result = TRUE

		for(var/turf/T in locs)
			if(!T.CanZPass(src,direction))
				occupant_message(span_warning("You can't move that direction from here!"))
				result = FALSE
				break
			var/turf/dest = (direction == UP) ? GetAbove(src) : GetBelow(src)
			if(!dest)
				occupant_message(span_notice("There is nothing of interest in this direction."))
				result = FALSE
				break
			if(!dest.CanZPass(src,direction))
				occupant_message(span_warning("There's something blocking your movement in that direction!"))
				result = FALSE
				break
		if(result)
			move_result = mechstep(direction)

	//Turning

	else if(src.dir != direction)

		if(strafing)
			move_result = mechstep(direction)
		else
			move_result = mechturn(direction)

	//Stepping
	else
		move_result	= mechstep(direction)

	if(move_result)
		can_move = 0
		use_power(step_energy_drain)
		if(istype(src.loc, /turf/space))
			if(!src.check_for_support())
				float_direction = direction
				start_process(MECHA_PROC_MOVEMENT)
				src.mecha_log_message(span_warning("Movement control lost. Inertial movement started."))
		after(src, get_step_delay(), PROC_REF(reset_can_move))
		return 1
	return 0

/obj/mecha/proc/handle_equipment_movement()
	for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
		if(ME.chassis == src) //Sanity
			ME.handle_movement_action()
	return

/obj/mecha/proc/mechturn(direction)
	set_dir(direction)
	if(swivel_sound)
		playsound(src,swivel_sound,40,1)
	return 1

/obj/mecha/proc/mechstep(direction)
	var/current_dir = dir	//For strafing
	var/result = get_step(src,direction)
	if(result && Move(result))
		if(stomp_sound)
			playsound(src, reps ? stomp_sound : stomp_sound_2,50,0) // 1-2 step sequence.
			reps = (reps+1)%2 // 1-2 step sequence.
		handle_equipment_movement()
	if(strafing)	//Also for strafing
		set_dir(current_dir)
	return result

/obj/mecha/proc/mechsteprand()
	var/result = get_step_rand(src)
	if(result && Move(result))
		if(stomp_sound)
			playsound(src, reps ? stomp_sound : stomp_sound_2,50,0) // 1-2 step sequence.
			reps = (reps+1)%2 // 1-2 step sequence.
		handle_equipment_movement()
	return result

/obj/mecha/Bump(atom/obstacle)
	if(istype(obstacle, /mob))//First we check if it is a mob. Mechs mostly shouln't go through them, even while phasing.
		var/mob/M = obstacle
		M.Move(get_step(obstacle,src.dir))
	else if(phasing && get_charge()>=phasing_energy_drain)//Phazon check. This could use an improvement elsewhere.
		src.use_power(phasing_energy_drain)
		phase()
		. = ..(obstacle)
		return
	else if(istype(obstacle, /obj))//Then we check for regular obstacles.
		var/obj/O = obstacle
		if(istype(O, /obj/effect/portal))	//derpfix
			set_anchored(0) // Portals can only move unanchored objects.
			O.Crossed(src)
			after(src, 0, TYPE_PROC_REF(/atom/movable, set_anchored), with = list(TRUE)) //countering the portal's deferred teleport
		if(O.anchored)
			bump_into(obstacle)
		else
			step(obstacle,src.dir)

	else//No idea when this triggers, so i won't touch it.
		. = ..(obstacle)
	return

/obj/mecha/proc/phase()	// Force the mecha to move forward by phasing.
	if(can_phase)
		can_phase = FALSE
		flick("[mecha_base_state()]-phase", src)
		forceMove(get_step(src,src.dir))
		after(src, get_step_delay() * 3, PROC_REF(phase_ready))
		return TRUE	// In the event this is sequenced
	return FALSE

/obj/mecha/proc/phase_ready()
	can_phase = TRUE
	occupant_message("Phazed.")

///////////////////////////////////
////////  Internal damage  ////////
///////////////////////////////////

////////////////////////////////////////
////////  Health related procs  ////////
////////////////////////////////////////

/// Legacy integrity-style damage call. Everything lands through the machine body plan
/// (code/modules/body/mech_body.dm): armour plates, hull, then internal parts.
/obj/mecha/take_damage(amount, type=BRUTE)
	mech_body_plan().injure(src, amount, type)

/// The mech's injure(): a hit of `amount` keyed by armour key, through the body plan.
/// Returns the chassis integrity lost.
/obj/mecha/proc/injure_mech(amount, armor_key = MELEE)
	return mech_body_plan().injure(src, amount, armor_key)

/obj/mecha/airlock_crush(crush_damage)
	..()
	take_damage(crush_damage)
	if(prob(50))	//Try to avoid that.
		mech_body_plan().roll_affliction(src, list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
	return 1

/obj/mecha/proc/update_health()
	if(get_integrity() > 0)
		fx_sparks(src, 2, FALSE)
	else
		wrecked = TRUE
		destroyed(src)
	return

// Pilot Menu entries (old "Exosuit Interface" verbs): the pilot is inside the mech, which
// counts as reach (movable/Adjacent: neighbor == loc); pred_mecha_pilot keeps them pilot-only.
MSG_DEF_SELF(mecha/not_pilot, "Only the pilot can do that.")
MSG_DEF_SELF(mecha/not_pilot_recalibrate, "Only the pilot can recalibrate.")

/// The mech's pilot, or null: the pilot ledger slot, which publishes OCCUPANT_KEY when someone gets in or out.
/obj/mecha/proc/pilot_of()
	return slot_item(MECHA_SLOT_PILOT)

READS_AS(/obj/mecha/proc/pilot_of, OCCUPANT_KEY)

/// Requirement: the actor is this mech's pilot (old `set src = usr.loc` + pilot checks).
/obj/mecha/proc/pilot_only(datum/act/op/A)
	return A.actor && A.actor == pilot_of() ? null : MSG(mecha/not_pilot)

/// A paint kit customises the mech (the handler is declared with the kit's code, paintkit.dm).
/obj/mecha/proc/mecha_paint_kit_op(datum/act/op/A)
	interaction_mecha_paint_kit(A.actor, A.held)
	return OP_OK

/// The Enter Exosuit menu entry (old set src in oview(1)).
/obj/mecha/proc/mecha_enter_op(datum/act/op/A)
	if(A.actor.loc == src)
		return OP_DECLINE
	mecha_verb_enter(A.actor)
	return OP_OK

/// The Enter Passenger Compartment menu entry.
/obj/mecha/proc/mecha_enter_passenger_op(datum/act/op/A)
	if(A.actor.loc == src || !pred_mecha_has_passenger_bay(A.actor, src, null) || can_enter_passenger(A.actor, src, null) != TRUE)
		return OP_DECLINE
	move_inside_passenger(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_eject_op(datum/act/op/A)
	mecha_verb_eject(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_stats_op(datum/act/op/A)
	view_stats(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_lights_op(datum/act/op/A)
	mecha_verb_toggle_lights(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_strafing_op(datum/act/op/A)
	mecha_verb_toggle_strafing(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_airtank_op(datum/act/op/A)
	if(!pred_mecha_has_airtank(A.actor, src, null))
		return OP_DECLINE
	toggle_internal_tank(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_connect_op(datum/act/op/A)
	if(!pred_mecha_port_connectable(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_connect_to_port(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_disconnect_op(datum/act/op/A)
	if(!pred_mecha_port_connected(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_disconnect_from_port(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_defence_op(datum/act/op/A)
	if(!pred_mecha_can_defence_mode(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_toggle_defence_mode(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_overload_op(datum/act/op/A)
	if(!pred_mecha_can_overload(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_toggle_overload(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_smoke_op(datum/act/op/A)
	if(!pred_mecha_can_smoke(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_toggle_smoke(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_zoom_op(datum/act/op/A)
	if(!pred_mecha_can_zoom(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_toggle_zoom(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_thrusters_op(datum/act/op/A)
	if(!pred_mecha_can_thrusters(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_toggle_thrusters(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_damtype_op(datum/act/op/A)
	if(!pred_mecha_can_switch_damtype(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_switch_damtype(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_phasing_op(datum/act/op/A)
	if(!pred_mecha_can_phasing(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_toggle_phasing(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_cloak_op(datum/act/op/A)
	if(!pred_mecha_can_cloak(A.actor, src, null))
		return OP_DECLINE
	mecha_verb_toggle_cloak(A.actor)
	return OP_OK

/obj/mecha/proc/mecha_weapons_cycle_op(datum/act/op/A)
	mecha_verb_toggle_weapons_only_cycle(A.actor)
	return OP_OK

/// Old attack_hand.
/obj/mecha/proc/interaction_mecha_hand(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(user == occupant)
		show_radial_occupant(user)
		return OP_OK

	user.setClickCooldown(user.get_attack_speed())
	src.mecha_log_message("Attack by hand/paw. Attacker - [user].",1)

	var/datum/mech_body_plan/plan = mech_body_plan()
	var/lands = plan.strike_lands(src)

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/shreddamage = H.species.can_shred(user, FALSE, 13)
		if(shreddamage)
			if(lands)
				plan.injure(src, shreddamage, MELEE)
				if(prob(shreddamage))	//Why would they get free internal damage. At least make it a bit RNG.
					mech_body_plan().roll_affliction(src, list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
				play_sfx(src, SFX_WEAPONS_SLASH, extrarange = -1)
				to_chat(user, span_danger("You attack the armored suit!"))
				act_message(user, null, others = span_danger("%U% attacks [src.name]'s armor!"))
			else
				src.log_append_to_last("Armor saved.")
				play_sfx(src, SFX_WEAPONS_SLASH, extrarange = -1)
				to_chat(user, span_danger("Your attack had no effect!"))
				src.occupant_message(span_notice("\The [user]'s attack is stopped by the armor."))
				act_message(user, null, others = span_warning("%U% rebounds off [src.name]'s armor!"))
		else
			act_message(user, src, MSG_SELF(span_danger("You hit %T% with no visible effect.")), MSG_OTHERS(span_danger("%U% hits %T%. Nothing happens.")))
			src.log_append_to_last("Armor saved.")
		return OP_OK
	else if (user.has_mutation(HULK) && lands)
		plan.injure(src, 15, MELEE)
		if(prob(25))	//Hulks punch hard but lets not give them consistent internal damage.
			mech_body_plan().roll_affliction(src, list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
		act_message(user, null, MSG_SELF(span_warning(span_red(span_bold("You hit [src.name] with all your might. The metal creaks and bends.")))), \
			MSG_OTHERS(span_warning(span_red(span_bold("%U% hits [src.name], doing some damage.")))))
	else
		act_message(user, null, MSG_SELF(span_infoplain(span_red(span_bold("You hit [src.name] with no visible effect.")))), \
			MSG_OTHERS(span_infoplain((span_red(span_bold("%U% hits [src.name]. Nothing happens."))))))
		src.log_append_to_last("Armor saved.")
	return OP_OK

/// The mech's packet sink. Each kind lands through the machine body plan
/// (mech_body_plan().injure), keyed by the kind's armour key. Projectiles and throws
/// come in through their own body entry points (receive_projectile, receive_thrown),
/// which apply deflection and penetration first.
/obj/mecha/damage_sink(datum/damage_packet/packet)
	if(QDELETED(src))
		return 0
	var/list/amounts = packet.amounts
	var/datum/mech_body_plan/plan = mech_body_plan()
	. = 0
	for(var/kind in 1 to DAMAGE_KIND_COUNT)
		var/amount = amounts[kind]
		if(amount <= 0)
			continue
		var/armor_key = damage_kind_obj_damage_type(kind)
		if(!armor_key)
			continue
		if(kind == DAMAGE_IONIC)
			amount *= emp_integrity_factor
			if(amount <= 0)
				continue
		var/before = get_integrity()
		plan.injure(src, amount, armor_key)
		if(QDELETED(src))
			return . + before
		. += before - get_integrity()

/// bullet_act() already applied the round through the body plan (receive_projectile).
/obj/mecha/projectile_damage(obj/item/projectile/P, def_zone)
	return 0

/// hitby() already applied the throw through the body plan (receive_thrown).
/obj/mecha/thrown_damage(atom/movable/source, datum/thrownthing/throwingdatum)
	return 0

/obj/mecha/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	..()
	src.mecha_log_message("Hit by [source].",1)
	mech_body_plan().receive_thrown(src, source)
	return

/obj/mecha/bullet_act(obj/item/projectile/Proj)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(istype(Proj, /obj/item/projectile/test))
		var/obj/item/projectile/test/Test = Proj
		rel_add(Test, nameof(Test.hit), occupant) // Register a hit on the occupant, for things like turrets, or in simple-mob cases stopping friendly fire in firing line mode.
		return

	src.mecha_log_message("Hit by projectile. Type: [Proj.name]([armor_kind_name(Proj.injury_kind)]).",1)
	if(!negate_projectile(Proj))
		mech_body_plan().receive_projectile(src, Proj)
	..()
	return

/// Chassis-specific chance to negate a round before it reaches the body (phase armour).
/// Return TRUE when the round is negated.
/obj/mecha/proc/negate_projectile(obj/item/projectile/Proj)
	return FALSE

//This refer to whenever you are caught in an explosion.
/// The armour may soften a blast by a severity step: the packet is rescaled to the new severity.
/obj/mecha/proc/mecha_blast(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	src.mecha_log_message("Affected by explosion of severity: [packet.severity].",1)
	var/severity = mech_body_plan().blast_severity(src, packet.severity)
	if(severity != packet.severity)
		var/old_fraction = explosion_blast_fraction(packet.severity)
		packet.scale(old_fraction ? explosion_blast_fraction(severity) / old_fraction : 0)
		packet.severity = severity
	return HOOK_DECLINE

/// A blast that got through the armour risks internal damage.
/obj/mecha/proc/mecha_blast_afflictions(datum/act/A)
	var/datum/notice/hit/explosion/N = A
	var/datum/damage_packet/packet = N.packet
	if(packet.severity <= 3)
		mech_body_plan().roll_affliction(src, list(MECHA_INT_FIRE,MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST,MECHA_INT_SHORT_CIRCUIT),1)

/// An EMP drains the cell, burns the hull and risks internal damage.
/obj/mecha/proc/mecha_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/datum/damage_packet/packet = N.packet
	if(get_charge())
		use_power((cell.charge/2)/packet.severity)
		take_damage(50 / packet.severity,"energy")
	src.mecha_log_message("EMP detected",1)
	if(prob(80))
		mech_body_plan().roll_affliction(src, list(MECHA_INT_FIRE,MECHA_INT_TEMP_CONTROL,MECHA_INT_CONTROL_LOST,MECHA_INT_SHORT_CIRCUIT),1)

/// Hull past max_temperature (the overheating rule): log it and risk internal damage.
/obj/mecha/on_overheat()
	mecha_log_message("Exposed to dangerous temperature.", 1)
	mech_body_plan().roll_affliction(src, list(MECHA_INT_FIRE, MECHA_INT_TEMP_CONTROL))

/obj/mecha/proc/dynattackby(obj/item/W as obj, mob/user as mob)
	user.setClickCooldown(user.get_attack_speed(W))
	src.mecha_log_message("Attacked by [W]. Attacker - [user]")
	mech_body_plan().receive_melee(src, W, user)
	return

//////////////////////
////// AttackBy //////
//////////////////////

// Maintenance steps and weld repairs: mecha_maintenance.dm.

/// Outside combat mode a welder never strikes the exosuit (weld repairs are its tool interaction).
/obj/mecha/proc/interaction_mecha_welder(datum/act/op/A)
	var/obj/item/W = A.held
	return W.has_tool_quality(TOOL_WELDER) ? OP_OK : OP_DECLINE

/// Old attackby: every item is handled here.
/obj/mecha/proc/interaction_mecha_item(datum/act/op/A)
	mecha_item_use(A.actor, A.held)
	return OP_OK

/// Maintenance, parts, else dynattackby.
/obj/mecha/proc/mecha_item_use(mob/user, obj/item/W)

	if(istype(W, /obj/item/mmi))
		if(mmi_move_inside(W,user))
			to_chat(user, "[src]-MMI interface initialized successfuly")
		else
			to_chat(user, "[src]-MMI interface initialization failed.")
		return TRUE

	if(istype(W, /obj/item/robotanalyzer))
		var/obj/item/robotanalyzer/RA = W
		RA.do_scan(src, user)
		return TRUE

	if(istype(W, /obj/item/mecha_parts/mecha_equipment))
		var/obj/item/mecha_parts/mecha_equipment/E = W
		if(E.can_attach(src))
			user.drop_item()
			E.attach(src)
			act_message(user, src, MSG_SELF("You attach [W] to %T%"), MSG_OTHERS("%U% attaches [W] to %T%"))
		else
			to_chat(user, "You were unable to attach [W] to [src]")
		return TRUE

	if(istype(W, /obj/item/mecha_parts/component) && state == MECHA_CELL_OUT)
		var/obj/item/mecha_parts/component/MC = W
		if(MC.attach(src))
			user.drop_item()
			MC.forceMove(src)
			act_message(user, src, MSG_SELF("You install %I% in %T%."), MSG_OTHERS("%U% installs %I% in %T%"), item = W)
		return TRUE

	if(istype(W, /obj/item/card/robot))
		var/obj/item/card/robot/RoC = W
		return mecha_item_use(user, RoC.dummy_card)

	if(istype(W, /obj/item/card/id)||istype(W, /obj/item/pda))
		if(add_req_access || maint_access)
			if(internals_access_allowed(user))
				var/obj/item/card/id/id_card
				if(istype(W, /obj/item/card/id))
					id_card = W
				else
					var/obj/item/pda/pda = W
					id_card = pda.id
				output_maintenance_dialog(id_card, user)
				return TRUE
			else
				to_chat(user, span_warning("Invalid ID: Access denied."))
		else
			to_chat(user, span_warning("Maintenance protocols disabled by operator."))
	// Tool steps are the maintenance graph (mecha_maintenance.dm); a tool it has no step for does nothing.
	else if(W.has_tool_quality(TOOL_WRENCH) || W.has_tool_quality(TOOL_CROWBAR) || W.has_tool_quality(TOOL_SCREWDRIVER))
		return TRUE
	else if(istype(W, /obj/item/multitool))
		if(state>=MECHA_CELL_OPEN && src?.slot_item(MECHA_SLOT_PILOT))
			to_chat(user, "You attempt to eject the pilot using the maintenance controls.")
			var/mob/living/_tmp_occ_5 = src?.slot_item(MECHA_SLOT_PILOT)
			if(_tmp_occ_5.stat)
				src.go_out()
				src.mecha_log_message("[src?.slot_item(MECHA_SLOT_PILOT)] was ejected using the maintenance controls.")
			else
				to_chat(user, span_warning("Your attempt is rejected."))
				src.occupant_message(span_warning("An attempt to eject you was made using the maintenance controls."))
				src.mecha_log_message("Eject attempt made using maintenance controls - rejected.")
		return TRUE

	else if(istype(W, /obj/item/cell))
		if(state==MECHA_CELL_OUT)
			if(!src.cell)
				to_chat(user, "You install the powercell")
				if(!move_into(src, nameof(src.cell), W, user))
					return TRUE
				src.mecha_log_message("Powercell installed")
			else
				to_chat(user, "There's already a powercell installed.")
		return TRUE

	else if(istype(W, /obj/item/mecha_parts/mecha_tracking))
		user.drop_from_inventory(W)
		W.forceMove(src)
		act_message(user, src, MSG_SELF("You attach [W] to %T%"), MSG_OTHERS("%U% attaches [W] to %T%."))
		return TRUE

	else
		dynattackby(W, user)
	return TRUE


///////////////////////////////
////////  Brain Stuff  ////////
///////////////////////////////

/obj/mecha/proc/mmi_move_inside(obj/item/mmi/mmi_as_oc as obj,mob/user as mob)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	var/mob/living/carbon/brain/mmi_occupant = mmi_as_oc.get_occupant()
	if(!mmi_occupant?.client)
		to_chat(user, "Consciousness matrix not detected.")
		return 0
	else if(mmi_occupant.stat)
		to_chat(user, "Brain activity below acceptable level.")
		return 0
	else if(occupant)
		to_chat(user, "Occupant detected.")
		return 0
	else if(dna && dna != mmi_occupant.identity().get_dna()?.unique_enzymes)
		to_chat(user, "Genetic sequence or serial number incompatible with locking mechanism.")
		return 0
	//Added a message here since people assume their first click failed or something./N
//	to_chat(user, "Installing MMI, please stand by.")

	act_message(user, null, others = span_notice("%U% starts to insert a brain into [src.name]"))

	var/datum/op_result/started = perform_op(user, src, "mmi_install", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("mmi" = mmi_as_oc))
	return started?.outcome != ACT_REFUSED

/obj/mecha/proc/mmi_install_interrupted(datum/act/op/A)
	to_chat(A.actor, "You stop attempting to install the brain.")

/obj/mecha/proc/mmi_install_done(datum/act/op/A)
	var/obj/item/mmi/mmi_as_oc = A.arg("mmi")
	var/mob/user = A.actor
	if(!src?.slot_item(MECHA_SLOT_PILOT))
		mmi_moved_inside(mmi_as_oc,user)
	else
		to_chat(user, "Occupant detected.")
	return OP_OK

/obj/mecha/proc/mmi_moved_inside(obj/item/mmi/mmi_as_oc as obj,mob/user as mob)
	if(mmi_as_oc && (user in range(1)))
		var/mob/living/carbon/brain/mmi_occupant = mmi_as_oc.get_occupant()
		if(!mmi_occupant?.client)
			to_chat(user, "Consciousness matrix not detected.")
			return 0
		else if(mmi_occupant.stat)
			to_chat(user, "Beta-rhythm below acceptable level.")
			return 0
		user.drop_from_inventory(mmi_as_oc)
		var/mob/brainmob = mmi_occupant
		// Through the pilot slot (C8 step 2), so it gets the automatic
		// om_link (occupant, etc.) the same way a human pilot does.
		if(!move_into(src, MECHA_SLOT_PILOT, brainmob))
			return 0
		brainmob.canmove = 1 //should allow relaymove
		mmi_as_oc.forceMove(src)
		rel_set(mmi_as_oc, nameof(mmi_as_oc.mecha), src)
		src.Entered(mmi_as_oc)
		src.Move(src.loc)
		set_dir(dir_in)
		src.mecha_log_message("[mmi_as_oc] moved in as pilot.")
		if(!mech_body_plan().has_affliction(src))
			src?.slot_item(MECHA_SLOT_PILOT) << sound('sound/mecha/nominal.ogg',volume=50)
		return 1
	else
		return 0

/////////////////////////////////////
////////  Atmospheric stuff  ////////
/////////////////////////////////////

/obj/mecha/proc/get_turf_air()
	var/turf/T = get_turf(src)
	if(T)
		. = T.return_air()
	return

/obj/mecha/remove_air(amount)
	if(use_internal_tank)
		return cabin_air.remove(amount)
	else
		var/turf/T = get_turf(src)
		if(T)
			return T.remove_air(amount)
	return

/obj/mecha/return_air()
	var/obj/item/mecha_parts/component/gas/GC = internal_components[MECH_GAS]
	if(use_internal_tank && (GC && prob(GC.get_efficiency() * 100)))
		return cabin_air
	return get_turf_air()

/obj/mecha/proc/return_pressure()
	. = 0
	var/obj/item/mecha_parts/component/gas/GC = internal_components[MECH_GAS]
	if(use_internal_tank && (GC && prob(GC.get_efficiency() * 100)))
		. =  cabin_air.return_pressure()
	else
		var/datum/gas_mixture/t_air = get_turf_air()
		if(t_air)
			. = t_air.return_pressure()
	return

/// The pilot sees the cabin air on the internal tank, else the air outside.
/obj/mecha/get_interior_temperature()
	var/obj/item/mecha_parts/component/gas/GC = internal_components[MECH_GAS]
	if(use_internal_tank && (GC && prob(GC.get_efficiency() * 100)))
		return cabin_air.return_temperature()
	var/datum/gas_mixture/t_air = get_turf_air()
	if(t_air)
		return t_air.return_temperature()
	return ..()

// connect/disconnect plumb the mecha cabin atmosphere into a LINDA
// portables_connector's pipe network, mirroring the canonical portable
// atmospherics device (code/game/machinery/atmoalter/portable_atmospherics.dm).
/obj/mecha/port_network_air()
	return cabin_air

/obj/mecha/set_port_network_air(datum/gas_mixture/new_air)
	atmos_air_set(src, nameof(cabin_air), new_air) // a network's air is referenced, a private mixture owned
	return TRUE

/obj/mecha/proc/connect(obj/machinery/atmospherics/portables_connector/new_port)
	// Already connected, or the port is missing/occupied.
	if(connected_port || !new_port || new_port.connected_device)
		return 0
	// Must share a tile with the port, and have a cabin atmosphere to share.
	if(!(new_port.loc in locs) || !cabin_air)
		return 0

	rel_set(src, nameof(connected_port), new_port)
	rel_set(connected_port, nameof(connected_port.connected_device), src)
	connected_port.set_on(1)

	// Inject cabin_air into the port's pipe network so an external supply can
	// equalise with it. connected_device is set first so return_network()
	// recognises src as the reference.
	connected_port.rust_attach_external_device(src)

	play_sfx(src, SFX_MECHA_GASCONNECTED)
	mecha_log_message("Connected to gas port.")
	return 1

/obj/mecha/proc/disconnect()
	if(!connected_port)
		return 0

	connected_port.rust_detach_external_device()

	rel_clear(connected_port, nameof(connected_port.connected_device))
	rel_clear(src, nameof(connected_port))

	play_sfx(src, SFX_MECHA_GASDISCONNECTED)
	mecha_log_message("Disconnected from gas port.")
	return 1

/////////////////////////
////////  Verbs  ////////
/////////////////////////

/// Requirement: the actor is this mech's pilot (old `set src = usr.loc` + pilot checks).
/obj/mecha/proc/pred_mecha_pilot(mob/actor, atom/target, obj/item/held)
	return actor && actor == slot_item(MECHA_SLOT_PILOT)

/// Requirement: the actor is outside this mech (old `set src in oview(1)`).
/obj/mecha/proc/pred_mecha_outside(mob/actor, atom/target, obj/item/held)
	return actor && actor.loc != src

/// Requirement: the mech has an internal airtank (old removeVerb on Initialize without one).
/obj/mecha/proc/pred_mecha_has_airtank(mob/actor, atom/target, obj/item/held)
	return !!internal_tank

/// Requirement: port connection state (old connect/disconnect verb toggling).
/obj/mecha/proc/pred_mecha_port_connectable(mob/actor, atom/target, obj/item/held)
	return internal_tank && !connected_port

/obj/mecha/proc/pred_mecha_port_connected(mob/actor, atom/target, obj/item/held)
	return !!connected_port

/// Old verb "Connect to port".
/obj/mecha/proc/mecha_verb_connect_to_port(mob/user, obj/item/held)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(!occupant)
		return

	if(user != occupant)
		return

	var/obj/item/mecha_parts/component/gas/GC = internal_components[MECH_GAS]
	if(!GC)
		return

	for(var/turf/T in locs)
		var/obj/machinery/atmospherics/portables_connector/possible_port = locate_on(T, /obj/machinery/atmospherics/portables_connector)
		if(possible_port)
			if(connect(possible_port))
				occupant_message(span_notice("\The [name] connects to the port."))
				return
			else
				occupant_message(span_danger("\The [name] failed to connect to the port."))
				return
		else
			occupant_message("Nothing happens")

/// Old verb "Disconnect from port".
/obj/mecha/proc/mecha_verb_disconnect_from_port(mob/user, obj/item/held)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(!occupant)
		return

	if(user != occupant)
		return

	if(disconnect())
		occupant_message(span_notice("[name] disconnects from the port."))
	else
		occupant_message(span_danger("[name] is not connected to the port at the moment."))

/// Old verb "Toggle Lights".
/obj/mecha/proc/mecha_verb_toggle_lights(mob/user, obj/item/held)
	lights(user)

/obj/mecha/proc/lights(mob/user)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(user!=occupant)	return
	lights = !lights
	if(lights)	set_light(light_range + lights_power)
	else		set_light(light_range - lights_power)
	src.occupant_message("Toggled lights [lights?"on":"off"].")
	src.mecha_log_message("Toggled lights [lights?"on":"off"].")
	play_sfx(src, SFX_MECHA_HEAVYLIGHTSWITCH)
	return

/// Old verb "Toggle internal airtank usage". The mech minihud calls it with no user after
/// checking the clicker is the pilot, so a null user means the pilot.
/obj/mecha/proc/toggle_internal_tank(mob/user, obj/item/held)
	internal_tank(user || slot_item(MECHA_SLOT_PILOT))

/obj/mecha/proc/internal_tank(mob/user)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(!user || user!=occupant)
		return

	var/obj/item/mecha_parts/component/gas/GC = internal_components[MECH_GAS]
	if(!GC)
		to_chat(occupant, span_warning("The life support systems don't seem to respond."))
		return

	if(!prob(GC.get_efficiency() * 100))
		to_chat(occupant, span_warning("\The [GC] shudders and barks, before returning to how it was before."))
		return

	use_internal_tank = !use_internal_tank
	src.occupant_message("Now taking air from [use_internal_tank?"internal airtank":"environment"].")
	src.mecha_log_message("Now taking air from [use_internal_tank?"internal airtank":"environment"].")
	play_sfx(src, SFX_MECHA_GASDISCONNECTED, 0.6)
	return

/// Old verb "Toggle strafing".
/obj/mecha/proc/mecha_verb_toggle_strafing(mob/user, obj/item/held)
	strafing(user)

/obj/mecha/proc/strafing(mob/user)
	if(!user || user!=src?.slot_item(MECHA_SLOT_PILOT))
		return
	strafing = !strafing
	src.occupant_message("Toggled strafing mode [strafing?"on":"off"].")
	src.mecha_log_message("Toggled strafing mode [strafing?"on":"off"].")
	return

/// Old MouseDrop_T: drag yourself onto the mech to climb in.
/obj/mecha/proc/interaction_mecha_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/O = A.held
	//Humans can pilot mechs.
	if(!ishuman(O))
		return OP_OK

	//Can't put other people into mechs (can comment this out if you want that to be possible)
	if(O != user)
		return OP_OK

	move_inside(user)
	return OP_OK

/// Old verb "Enter Exosuit".
/obj/mecha/proc/mecha_verb_enter(mob/user, obj/item/held)
	move_inside(user)

//returns an equipment object if we have one of that type, useful since is_type_in_list won't return the object
//since is_type_in_list uses caching, this is a slower operation, so only use it if needed
/obj/mecha/proc/get_equipment(equip_type)
	for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
		if(istype(ME,equip_type))
			return ME
	return null

/obj/mecha/proc/move_inside(mob/user)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if (user.stat || !ishuman(user) || user.is_incorporeal())
		return

	if (user?.buckled_to())
		to_chat(user, span_warning("You can't climb into the exosuit while buckled!"))
		return

	src.mecha_log_message("[user] tries to move in.")
	if(iscarbon(user))
		var/mob/living/carbon/C = user
		if(C.get_equipped_item(SLOT_ID_HANDCUFFED))
			to_chat(user, span_danger("Kinda hard to climb in while handcuffed don't you think?"))
			return
	if (src?.slot_item(MECHA_SLOT_PILOT))
		to_chat(user, span_danger("The [src.name] is already occupied!"))
		src.log_append_to_last("Permission denied.")
		return
/*
	if (user.abiotic())
		to_chat(user, span_notice("Subject cannot have abiotic items on."))
		return
*/
	var/passed
	if(src.dna)
		if(user.dna.unique_enzymes==src.dna)
			passed = 1
	else if(src.operation_allowed(user))
		passed = 1
	if(!passed)
		to_chat(user, span_warning("Access denied"))
		src.log_append_to_last("Permission denied.")
		return
	if(isliving(user))
		var/mob/living/L = user
		if(L.has_buckled_mobs())
			to_chat(L, span_warning("You have other entities attached to yourself. Remove them first."))
			return

	if(get_equipment(/obj/item/mecha_parts/mecha_equipment/runningboard))
		act_message(user, null, others = span_notice("%U% is instantly lifted into [src.name] by the running board!"))
		moved_inside(user)
		if(ishuman(occupant))
			GrantActions(occupant, 1)
	else
		act_message(user, null, others = span_infoplain(span_bold("%U%") + " starts to climb into [src.name]"))
		perform_op(user, src, "climb_in", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)
	return

/obj/mecha/proc/climb_in_interrupted(datum/act/op/A)
	to_chat(A.actor, "You stop entering the exosuit.")

/obj/mecha/proc/climb_in_done(datum/act/op/A)
	var/mob/user = A.actor
	if(!src?.slot_item(MECHA_SLOT_PILOT))
		moved_inside(user)
		if(ishuman(src?.slot_item(MECHA_SLOT_PILOT))) //Aeiou
			GrantActions(src?.slot_item(MECHA_SLOT_PILOT), 1)
	else if(src?.slot_item(MECHA_SLOT_PILOT) != user)
		to_chat(user, "[src?.slot_item(MECHA_SLOT_PILOT)] was faster. Try better next time, loser.")
	return OP_OK

/obj/mecha/proc/reset_can_move()
	can_move = 1

/obj/mecha/proc/moved_inside(mob/living/carbon/human/H)
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(H && H.client && (H in range(1)))
		H.stop_pulling()
		if(!move_into(src, MECHA_SLOT_PILOT, H))
			return
		src.add_fingerprint(H)
		src.log_append_to_last("[H] moved in as pilot.")
		if(occupant.hud_used)
			rel_set(src, nameof(minihud), new /datum/mini_hud/mech (occupant.hud_used, src))

		// The *_possible capability vars gate the pilot's Menu entries (pred_mecha_can_* in mecha_actions.dm).

		update_cell_alerts()
		update_damage_alerts()
		set_dir(dir_in)
		play_sfx(src, SFX_MACHINES_DOOR_WINDOWDOOR, 0.5)
		if(occupant.client && dq_get_cloaked_selfimage(src))
			occupant.client.images += dq_get_cloaked_selfimage(src)
		play_entered_noise(occupant)
		return 1
	else
		return 0

/obj/mecha/proc/play_entered_noise(mob/who)
	if(!mech_body_plan().has_affliction(src)) //Otherwise it's not nominal!
		switch(mech_faction)
			if(MECH_FACTION_NT)//The good guys category
				if(firstactivation)//First time = long activation sound
					firstactivation = 1
					who << sound('sound/mecha/longnanoactivation.ogg',volume=50)
				else
					who << sound('sound/mecha/nominalnano.ogg',volume=50)
			if(MECH_FACTION_SYNDI)//Bad guys
				if(firstactivation)
					firstactivation = 1
					who << sound('sound/mecha/longsyndiactivation.ogg',volume=50)
				else
					who << sound('sound/mecha/nominalsyndi.ogg',volume=50)
			else//Everyone else gets the normal noise
				who << sound('sound/mecha/nominal.ogg',volume=50)

/// Old click_alt: the pilot toggles strafing.
/obj/mecha/proc/interaction_mecha_alt(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(user == occupant)
		strafing(user)
	return OP_OK

/// Old verb "View Stats".
/obj/mecha/proc/view_stats(mob/user, obj/item/held)
	if(!user || user != src?.slot_item(MECHA_SLOT_PILOT))
		return
	// The structured TGUI interface replaces the old browser window.
	tgui_subview = "main"
	tgui_interact(src?.slot_item(MECHA_SLOT_PILOT))
	return


/// Old verb "Eject".
/obj/mecha/proc/mecha_verb_eject(mob/user, obj/item/held)
	if(!user || user!=src?.slot_item(MECHA_SLOT_PILOT))
		return
	src.go_out()
	add_fingerprint(user)
	return

/obj/mecha/proc/go_out() //Eject/Exit the mech. Yes this is for easier searching.
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(!src?.slot_item(MECHA_SLOT_PILOT)) return
	var/atom/movable/mob_container
	rel_clear(src, nameof(minihud))
	if(ishuman(occupant))
		mob_container = src?.slot_item(MECHA_SLOT_PILOT)
		RemoveActions(occupant, human_occupant=1)//AEIOU
	else if(istype(occupant, /mob/living/carbon/brain))
		var/mob/living/carbon/brain/brain = occupant
		mob_container = brain.container
	else
		return
	// The pilot slot (C8 step 2) tracks `occupant` either way (a brain pilot
	// is moved into it too, mmi_moved_inside()), so this is what leaves it
	// and unlinks it, automatically, for both a human and an MMI/brain pilot.
	var/moved = slot_remove(occupant, src.loc)
	if(moved)//ejecting occupant
		src.mecha_log_message("[mob_container] moved out.")
		// TGUI: close the exosuit interface on eject.
		SStgui.close_uis(src)
		if(occupant.client && dq_get_cloaked_selfimage(src))
			occupant.client.images -= dq_get_cloaked_selfimage(src)
		if(istype(mob_container, /obj/item/mmi))
			var/obj/item/mmi/mmi = mob_container
			mmi.forceMove(src.loc)
			if(mmi.get_occupant())
				occupant.forceMove(mmi)
			rel_clear(mmi, nameof(mmi.mecha))
			occupant.canmove = 0
		occupant.clear_alert("charge")
		occupant.clear_alert("mech damage")
		set_dir(dir_in)


		// Doesn't seem needed.
		var/mob/living/_tmp_occ_6 = src?.slot_item(MECHA_SLOT_PILOT)
		if(src?.slot_item(MECHA_SLOT_PILOT) && _tmp_occ_6.client)
			var/mob/living/_tmp_occ_7 = src?.slot_item(MECHA_SLOT_PILOT)
			_tmp_occ_7.client.view = world.view
			src.zoom = 0

		strafing = 0
	return

/////////////////////////
////// Access stuff /////
/////////////////////////

/obj/mecha/proc/operation_allowed(mob/living/carbon/human/H)
	for(var/ID in list(H.get_active_hand(), H.get_equipped_item(SLOT_ID_ID), H.get_equipped_item(SLOT_ID_BELT)))
		if(src.check_access(ID,src.operation_req_access))
			return 1
	return 0

/obj/mecha/proc/internals_access_allowed(mob/living/carbon/human/H)
	if(istype(H))
		for(var/atom/ID in list(H.get_active_hand(), H.get_equipped_item(SLOT_ID_ID), H.get_equipped_item(SLOT_ID_BELT)))
			if(src.check_access(ID,src.internals_req_access))
				return 1
	else if(isrobot(H))
		var/mob/living/silicon/robot/R = H
		if(src.check_access(R.idcard,src.internals_req_access))
			return 1
	return 0

/obj/mecha/check_access(obj/item/card/id/I, list/access_list)
	if(!istype(access_list))
		return 1
	if(!access_list.len) //no requirements
		return 1
	if(istype(I, /obj/item/pda))
		var/obj/item/pda/pda = I
		I = pda.id
	if(!istype(I) || !I.GetAccess()) //not ID or no access
		return 0
	if(access_list==src.operation_req_access)
		for(var/req in access_list)
			if(!(req in I.GetAccess())) //doesn't have this access
				return 0
	else if(access_list==src.internals_req_access)
		for(var/req in access_list)
			if(req in I.GetAccess())
				return 1
	return 1

////////////////////////////////////
///// Rendering stats window ///////
////////////////////////////////////

// fully-structured TGUI for all five views (main + log +
// attack_ai + access + maint). One MechaInterface.tsx renders all five
// via the `view` data field; the legacy four browse() sub-UIs are gone.
/obj/mecha
	var/tgui_subview = "main"
	// Refs kept alive across sub-view interactions so tgui_data can
	// re-render structured data on update without losing the caller/card.
	/// Relation view: the id card the open access/maintenance dialog acts for.
	var/obj/item/card/id/active_id_card
	var/atom/active_caller
	var/active_attack_target_name = ""

/obj/mecha/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["view"] = tgui_subview
	data["smoke_reserve"] = smoke_reserve
	var/list/merged_1 = ui_data_obj_mecha(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/mecha's window data.
/obj/mecha/proc/ui_data_obj_mecha(mob/user, datum/tgui/_ui, datum/tgui_state/_state)
	var/list/data = list()
	data["title"] = "[name]"
	switch(tgui_subview)
		if("log")
			data["log_entries"] = get_log_tgui()
			return data
		if("attack_ai")
			data["ai_target_name"] = active_attack_target_name || ""
			var/list/targets = list()
			for(var/obj/item/mecha_parts/mecha_equipment/W in equipment)
				targets += list(list(
					"ref" = "\ref[W]",
					"name" = W.name,
					"kind" = "",
					"info_lines" = list(),
				))
			data["ai_targets"] = targets
			return data
		if("access")
			var/obj/item/card/id/id_card = active_id_card
			var/list/cur = list()
			for(var/a in operation_req_access)
				cur += list(list("id" = a, "name" = SSaccess.get_access_desc(a)))
			data["access_current"] = cur
			var/list/avail = list()
			if(id_card)
				for(var/a in id_card.GetAccess())
					if(a in operation_req_access)
						continue
					var/aname = SSaccess.get_access_desc(a)
					if(!aname)
						continue
					avail += list(list("id" = a, "name" = aname))
			data["access_available"] = avail
			return data
		if("maint")
			data["maint_can_req_access"] = !!add_req_access
			data["maint_can_maint_access"] = !!maint_access
			data["maint_can_set_air"] = (state > 0)
			data["maint_can_remove_passenger"] = (state > 0) && !!locate_within(src, /obj/item/mecha_parts/mecha_equipment/tool/passenger)
			return data
	// Damage banner.
	var/list/dam = list()
	for(var/datum/mech_affliction/A as anything in mech_body_plan().active_afflictions(src))
		dam += list(list(
			"key" = A.cockpit_repair || "damage_[A.flag]",
			"label" = A.alarm,
			"has_repair" = !!A.cockpit_repair,
		))
	data["damage_reports"] = dam
	data["high_pressure"] = return_pressure() > WARNING_HIGH_PRESSURE
	// Integrity.
	var/obj/item/mecha_parts/component/hull/HC = internal_components[MECH_HULL]
	var/obj/item/mecha_parts/component/armor/AC = internal_components[MECH_ARMOR]
	data["has_armor"] = !!AC
	data["armor_percent"] = AC ? round(AC.get_integrity() / AC.max_integrity * 100, 0.1) : 0
	data["has_hull"] = !!HC
	data["hull_percent"] = HC ? round(HC.get_integrity() / HC.max_integrity * 100, 0.1) : 0
	data["integrity_percent"] = round(get_integrity() / max_integrity * 100, 0.1)
	// Power.
	var/cell_charge = get_charge()
	data["cell_percent"] = isnull(cell_charge) ? null : cell.percent()
	// Atmos.
	data["use_internal_tank"] = !!use_internal_tank
	data["tank_pressure"] = internal_tank ? round(internal_tank.return_pressure(), 0.01) : "None"
	var/tt = internal_tank?.air_contents?.return_temperature()
	data["tank_temp_k"] = tt == null ? "Unknown" : round(tt, 0.1)
	data["tank_temp_c"] = tt == null ? "Unknown" : round(tt - T0C, 0.1)
	data["cabin_pressure"] = round(return_pressure(), 0.01)
	data["cabin_temp_k"] = round(get_interior_temperature(), 0.1)
	data["cabin_temp_c"] = round(get_interior_temperature() - T0C, 0.1)
	data["lights"] = !!lights
	data["dna_lock"] = dna || ""
	data["defence_mode_possible"] = !!defence_mode_possible
	data["defence_mode"] = !!defence_mode
	data["overload_possible"] = !!overload_possible
	data["overload"] = !!overload
	data["smoke_possible"] = !!smoke_possible
	data["thrusters_possible"] = !!thrusters_possible
	data["thrusters"] = !!thrusters
	// Cargo.
	var/list/cargo_list = list()
	for(var/obj/O in cargo)
		cargo_list += list(list("ref" = "\ref[O]", "name" = "[O]"))
	data["cargo"] = cargo_list
	// Radio / airtank.
	data["radio_mic"] = !!radio.broadcasting
	data["radio_spk"] = !!radio.listening
	data["radio_freq"] = format_frequency(radio.frequency)
	data["airtank_disconnect"] = !!connected_port
	data["airtank_connect"] = !!(internal_tank && !connected_port)
	// Permissions.
	data["id_upload_locked"] = !!add_req_access
	data["maint_access"] = !!maint_access
	// Equipment.
	var/list/equip = list()
	var/static/list/equip_kinds = list(
		list("hull_equipment", "Hull"),
		list("weapon_equipment", "Weapon"),
		list("utility_equipment", "Utility"),
		list("universal_equipment", "Universal"),
		list("special_equipment", "Special"),
		list("micro_utility_equipment", "Micro Utility"),
		list("micro_weapon_equipment", "Micro Weapon"),
	)
	for(var/list/k in equip_kinds)
		var/list/L = vars[k[1]]
		for(var/obj/item/mecha_parts/mecha_equipment/W as anything in L)
			equip += list(list(
				"ref" = "\ref[W]",
				"name" = W.name,
				"kind" = k[2],
				"info_lines" = list(),
			))
	data["equipment"] = equip
	// Slot capacity.
	data["slots"] = list(
		list("label" = "Hull",          "used" = length(hull_equipment),          "max" = max_hull_equip),
		list("label" = "Weapon",        "used" = length(weapon_equipment),        "max" = max_weapon_equip),
		list("label" = "Micro Weapon",  "used" = length(micro_weapon_equipment),  "max" = max_micro_weapon_equip),
		list("label" = "Utility",       "used" = length(utility_equipment),       "max" = max_utility_equip),
		list("label" = "Micro Utility", "used" = length(micro_utility_equipment), "max" = max_micro_utility_equip),
		list("label" = "Universal",     "used" = length(universal_equipment),     "max" = max_universal_equip),
		list("label" = "Special",       "used" = length(special_equipment),       "max" = max_special_equip),
	)
	data["can_eject"] = !!slot_item_real(MECHA_SLOT_PILOT)
	return data

/obj/mecha/proc/ui_gate(datum/act/op/A)
	var/action = A.window_action()
	var/static/list/static_routes = list(
		"toggle_lights" = "toggle_lights",
		"rmictoggle" = "rmictoggle",
		"rspktoggle" = "rspktoggle",
		"toggle_airtank" = "toggle_airtank",
		"port_disconnect" = "port_disconnect",
		"port_connect" = "port_connect",
		"toggle_id_upload" = "toggle_id_upload",
		"toggle_maint_access" = "toggle_maint_access",
		"dna_lock" = "dna_lock",
		"view_log" = "view_log",
		"change_name" = "change_name",
		"reset_dna" = "reset_dna",
		"repair_int_control_lost" = "repair_int_control_lost",
		"eject" = "eject",
	)
	if(action in static_routes)
		Topic(null, list("[static_routes[action]]" = "1"))
		return FALSE
	return TRUE

/obj/mecha/proc/ui_act_rfreq(datum/act/op/A, delta)
	if(!ui_gate(A))
		return FALSE
	Topic(null, list("rfreq" = delta))
	return TRUE

/obj/mecha/proc/ui_act_drop_from_cargo(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	Topic(null, list("drop_from_cargo" = ref))
	return TRUE

/obj/mecha/proc/ui_act_detach_equipment(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	if(isnull(ref))
		return FALSE
	var/obj/item/mecha_parts/mecha_equipment/W = ref
	if(W in equipment)
		W.detach()
	return TRUE

/obj/mecha/proc/ui_act_equip_interact(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	var/obj/item/mecha_parts/mecha_equipment/W = ref
	if(W && (W in equipment))
		if(istype(W, /obj/item/mecha_parts/mecha_equipment/tool/sleeper))
			W.Topic(null, list("view_stats" = "1"))
		else if(istype(W, /obj/item/mecha_parts/mecha_equipment/tool/syringe_gun))
			W.Topic(null, list("show_reagents" = "1"))
	return TRUE

/obj/mecha/proc/ui_act_view_main(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	tgui_subview = "main"
	return TRUE
// Attack-AI sub-view

/obj/mecha/proc/ui_act_ai_use_equipment(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(isnull(ref))
		return FALSE
	var/obj/item/mecha_parts/mecha_equipment/W = ref
	var/atom/target = active_caller
	if(W && (W in equipment))
		W.action(target, null, user)
	tgui_subview = "main"
	return TRUE
// Access sub-view

/obj/mecha/proc/ui_act_access_add(datum/act/op/A, id)
	if(!ui_gate(A))
		return FALSE
	var/a = id
	var/obj/item/card/id/id_card = active_id_card
	if(id_card && (a in id_card.GetAccess()) && !(a in operation_req_access))
		operation_req_access += a
	return TRUE

/obj/mecha/proc/ui_act_access_del(datum/act/op/A, id)
	if(!ui_gate(A))
		return FALSE
	var/a = id
	if(a in operation_req_access)
		operation_req_access -= a
	return TRUE

/obj/mecha/proc/ui_act_access_finish(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	add_req_access = 0
	tgui_subview = "main"
	return TRUE
// Maint sub-view

/obj/mecha/proc/ui_act_maint_req_access(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/obj/item/card/id/id_card = active_id_card
	if(id_card)
		tgui_subview = "access"
	return TRUE

/obj/mecha/proc/ui_act_maint_protocol(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	Topic(null, list("maint_access" = "1"))
	return TRUE

/obj/mecha/proc/ui_act_maint_set_air(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	Topic(null, list("set_internal_tank_valve" = "1"))
	return TRUE

/obj/mecha/proc/ui_act_maint_remove_passenger(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	Topic(null, list("remove_passenger" = "1"))
	return TRUE

/obj/mecha/proc/report_internal_damage()
	var/output = null
	for(var/datum/mech_affliction/A as anything in mech_body_plan().active_afflictions(src))
		output += span_red(span_bold(A.alarm))
		if(A.cockpit_repair)
			output += " - <a href='byond://?src=\ref[src];[A.cockpit_repair]=1'>Recalibrate</a>"
		output += "<br />"
	if(return_pressure() > WARNING_HIGH_PRESSURE)
		output += span_red(span_bold("DANGEROUSLY HIGH CABIN PRESSURE")) + "<br />"
	return output

/obj/mecha/proc/get_stats_part()
	var/integrity = get_integrity()/max_integrity*100
	var/cell_charge = get_charge()
	// internal_tank is now /obj/item/tank, no return_pressure/return_temperature
	// procs on it; read through air_contents (a /datum/gas_mixture).
	var/datum/gas_mixture/tank_air = internal_tank?.return_air()
	var/tank_pressure = tank_air ? round(tank_air.return_pressure(), 0.01) : "None"
	var/tank_temperature = tank_air ? tank_air.return_temperature() : "Unknown"
	var/cabin_pressure = round(return_pressure(),0.01)

	var/obj/item/mecha_parts/component/hull/HC = internal_components[MECH_HULL]
	var/obj/item/mecha_parts/component/armor/AC = internal_components[MECH_ARMOR]

	var/output = {"[report_internal_damage()]
						<b>Armor Integrity: </b>[AC?"[round(AC.get_integrity() / AC.max_integrity * 100, 0.1)]%":span_warning("ARMOR MISSING")]<br>
						<b>Hull Integrity: </b>[HC?"[round(HC.get_integrity() / HC.max_integrity * 100, 0.1)]%":span_warning("HULL MISSING")]<br>
						[integrity<30? span_red(span_bold("DAMAGE LEVEL CRITICAL")) + "<br>":null]
						<b>Chassis Integrity: </b> [integrity]%<br>
						<b>Powercell charge: </b>[isnull(cell_charge)?"No powercell installed":"[cell.percent()]%"]<br>
						<b>Air source: </b>[use_internal_tank?"Internal Airtank":"Environment"]<br>
						<b>Airtank pressure: </b>[tank_pressure]kPa<br>
						<b>Airtank temperature: </b>[tank_temperature]K|[tank_temperature - T0C]&deg;C<br>
						<b>Cabin pressure: </b>[cabin_pressure>WARNING_HIGH_PRESSURE ? span_red("[cabin_pressure]"): cabin_pressure]kPa<br>
						<b>Cabin temperature: </b> [get_interior_temperature()]K|[get_interior_temperature() - T0C]&deg;C<br>
						<b>Lights: </b>[lights?"on":"off"]<br>
						[src.dna?"<b>DNA-locked:</b><br> <span style='font-size:10px;letter-spacing:-1px;'>[src.dna]</span> \[<a href='byond://?src=\ref[src];reset_dna=1'>Reset</a>\]<br>":null]
					"}

	if(defence_mode_possible)
		output += span_bold("Defence mode: [defence_mode?"on":"off"]") + "<br>"
	if(overload_possible)
		output += span_bold("Leg actuators overload: [overload?"on":"off"]") + "<br>"
	if(smoke_possible)
		output += span_bold("Smoke:") + " [smoke_reserve]<br>"
	if(thrusters_possible)
		output += span_bold("Thrusters:") + " [thrusters?"on":"off"]<br>"

//Cargo components. Keep this last otherwise it does weird alignment issues.
	output += span_bold("Cargo Compartment Contents:") + "<div style=\"margin-left: 15px;\">"
	if(length(src.cargo))
		for(var/obj/O in src.cargo)
			output += "<a href='byond://?src=\ref[src];drop_from_cargo=\ref[O]'>Unload</a> : [O]<br>"
	else
		output += "Nothing"
	output += "</div>"
	return output

/obj/mecha/proc/get_commands()
	var/output = {"<div class='wr'>
						<div class='header'>Electronics</div>
						<div class='links'>
						<a href='byond://?src=\ref[src];toggle_lights=1'>Toggle Lights</a><br>
						<b>Radio settings:</b><br>
						Microphone: <a href='byond://?src=\ref[src];rmictoggle=1'><span id="rmicstate">[radio.broadcasting?"Engaged":"Disengaged"]</span></a><br>
						Speaker: <a href='byond://?src=\ref[src];rspktoggle=1'><span id="rspkstate">[radio.listening?"Engaged":"Disengaged"]</span></a><br>
						Frequency:
						<a href='byond://?src=\ref[src];rfreq=-10'>-</a>
						<a href='byond://?src=\ref[src];rfreq=-2'>-</a>
						<span id="rfreq">[format_frequency(radio.frequency)]</span>
						<a href='byond://?src=\ref[src];rfreq=2'>+</a>
						<a href='byond://?src=\ref[src];rfreq=10'>+</a><br>
						</div>
						</div>
						<div class='wr'>
						<div class='header'>Airtank</div>
						<div class='links'>
						<a href='byond://?src=\ref[src];toggle_airtank=1'>Toggle Internal Airtank Usage</a><br>
						[connected_port?"<a href='byond://?src=\ref[src];port_disconnect=1'>Disconnect from port</a><br>":null]
						[(internal_tank && !connected_port)?"<a href='byond://?src=\ref[src];port_connect=1'>Connect to port</a><br>":null]
						</div>
						</div>
						<div class='wr'>
						<div class='header'>Permissions & Logging</div>
						<div class='links'>
						<a href='byond://?src=\ref[src];toggle_id_upload=1'><span id='t_id_upload'>[add_req_access?"L":"Unl"]ock ID upload panel</span></a><br>
						<a href='byond://?src=\ref[src];toggle_maint_access=1'><span id='t_maint_access'>[maint_access?"Forbid":"Permit"] maintenance protocols</span></a><br>
						<a href='byond://?src=\ref[src];dna_lock=1'>DNA-lock</a><br>
						<a href='byond://?src=\ref[src];view_log=1'>View internal log</a><br>
						<a href='byond://?src=\ref[src];change_name=1'>Change exosuit name</a><br>
						</div>
						</div>
						<div id='equipment_menu'>[get_equipment_menu()]</div>
						<hr>
						[slot_item(MECHA_SLOT_PILOT)?"<a href='byond://?src=\ref[src];eject=1'>Eject</a><br>":null]
						"}
	return output

/obj/mecha/proc/get_equipment_menu() //outputs mecha html equipment menu
	var/output
	if(equipment.len)
		output += {"<div class='wr'>
						<div class='header'>Equipment</div>
						<div class='links'>"}
		for(var/obj/item/mecha_parts/mecha_equipment/W in hull_equipment)
			output += "Hull Module: [W.name] <a href='byond://?src=\ref[W];detach=1'>Detach</a><br>"
		for(var/obj/item/mecha_parts/mecha_equipment/W in weapon_equipment)
			output += "Weapon Module: [W.name] <a href='byond://?src=\ref[W];detach=1'>Detach</a><br>"
		for(var/obj/item/mecha_parts/mecha_equipment/W in utility_equipment)
			output += "Utility Module: [W.name] <a href='byond://?src=\ref[W];detach=1'>Detach</a><br>"
		for(var/obj/item/mecha_parts/mecha_equipment/W in universal_equipment)
			output += "Universal Module: [W.name] <a href='byond://?src=\ref[W];detach=1'>Detach</a><br>"
		for(var/obj/item/mecha_parts/mecha_equipment/W in special_equipment)
			output += "Special Module: [W.name] <a href='byond://?src=\ref[W];detach=1'>Detach</a><br>"
		for(var/obj/item/mecha_parts/mecha_equipment/W in micro_utility_equipment) // Adds micro equipent to the menu
			output += "Micro Utility Module: [W.name] <a href='byond://?src=\ref[W];detach=1'>Detach</a><br>"
		for(var/obj/item/mecha_parts/mecha_equipment/W in micro_weapon_equipment)
			output += "Micro Weapon Module: [W.name] <a href='byond://?src=\ref[W];detach=1'>Detach</a><br>"
	output += {"<b>Available hull slots:</b> [max_hull_equip-length(hull_equipment)]<br>
		<b>Available weapon slots:</b> [max_weapon_equip-length(weapon_equipment)]<br>
		<b>Available micro weapon slots:</b> [max_micro_weapon_equip-length(micro_weapon_equipment)]<br>
		<b>Available utility slots:</b> [max_utility_equip-length(utility_equipment)]<br>
		<b>Available micro utility slots:</b> [max_micro_utility_equip-length(micro_utility_equipment)]<br>
		<b>Available universal slots:</b> [max_universal_equip-length(universal_equipment)]<br>
		<b>Available special slots:</b> [max_special_equip-length(special_equipment)]<br>
		</div></div>
	"}
	return output

/obj/mecha/proc/get_equipment_list() //outputs mecha equipment list in html
	if(!equipment.len)
		return
	var/output = span_bold("Equipment:") + "<div style=\"margin-left: 15px;\">"
	for(var/obj/item/mecha_parts/mecha_equipment/MT in equipment)
		output += "<div id='\ref[MT]'>[MT.get_equip_info()]</div>"
	output += "</div>"
	return output

/obj/mecha/proc/get_log_tgui()
	var/list/data = list()
	for(var/list/entry in log)
		data.Add(list(list(
			"time" = time2text(entry["time"], "DDD MMM DD hh:mm:ss"),
			"year" = GLOB.game_year,
			"message" = entry["message"],
		)))
	return data

// fully-structured TGUI access dialog. The id_card is cached
// as a relation view so tgui_data can rebuild the available-keycode list each
// refresh.
/obj/mecha/proc/output_access_dialog(obj/item/card/id/id_card, mob/user)
	if(!id_card || !user)
		return
	rel_set(src, nameof(active_id_card), id_card)
	tgui_subview = "access"
	tgui_interact(user)
	return

// fully-structured TGUI maintenance console. Action availability
// is computed in tgui_data from current state.
/obj/mecha/proc/output_maintenance_dialog(obj/item/card/id/id_card, mob/user)
	if(!id_card || !user)
		return
	rel_set(src, nameof(active_id_card), id_card)
	tgui_subview = "maint"
	tgui_interact(user)
	return

////////////////////////////////
/////// Messages and Log ///////
////////////////////////////////

/obj/mecha/proc/occupant_message(message as text)
	if(message)
		var/mob/living/_tmp_occ_8 = src?.slot_item(MECHA_SLOT_PILOT)
		if(src?.slot_item(MECHA_SLOT_PILOT) && _tmp_occ_8.client)
			var/mob/living/_tmp_occ_9 = src?.slot_item(MECHA_SLOT_PILOT)
			to_chat(src?.slot_item(MECHA_SLOT_PILOT), "[icon2html(src, _tmp_occ_9.client)] [message]")
	return

/obj/mecha/proc/mecha_log_message(message as text,red=null)
	log.len++
	if(red)
		message = span_red(message)
	log[log.len] = list("time"=world.timeofday,"message"=message)
	return log.len

/obj/mecha/proc/log_append_to_last(message as text,red=null)
	var/list/last_entry = src.log[src.log.len]
	if(red)
		message = span_red(message)
	last_entry["message"] += "<br>" + message
	return

/////////////////
///// Topic /////
/////////////////

// Href actions (topic ops). Pilot-only ones check topic_is_pilot(); the maintenance
// ones are for someone standing next to the exosuit.

// A conscious clicker; the pilot always reaches the controls, anyone else needs the usual obj reach.
/obj/mecha/topic_usable(datum/act/op/A)
	if(!A.actor || A.actor.stat)
		return FALSE
	if(topic_is_pilot(A.actor))
		return TRUE
	return ..()

/obj/mecha/proc/topic_is_pilot(mob/user)
	return user && user == slot_item(MECHA_SLOT_PILOT)

/// TOPIC_REF source: the equipment mounted on this exosuit.
/obj/mecha/proc/topic_equipment_pool()
	return equipment

/// TOPIC_REF source: the cargo compartment.
/obj/mecha/proc/topic_cargo_pool()
	return cargo

/obj/mecha/proc/topic_update_content(datum/act/op/A)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	send_byjax(user, "exosuit.browser", "content", get_stats_part())

/obj/mecha/proc/topic_close(datum/act/op/A)
	return

/obj/mecha/proc/topic_select_equip(datum/act/op/A, href_select_equip)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	var/obj/item/mecha_parts/mecha_equipment/equip = href_select_equip
	if(!equip)
		return
	rel_set(src, nameof(selected), equip)
	occupant_message("You switch to [equip].")
	visible_message("[src] raises [equip].")
	send_byjax(user, "exosuit.browser", "eq_list", get_equipment_list())

/obj/mecha/proc/topic_eject(datum/act/op/A)
	var/mob/user = A.actor
	if(topic_is_pilot(user))
		mecha_verb_eject(user)

/obj/mecha/proc/topic_toggle_lights(datum/act/op/A)
	var/mob/user = A.actor
	if(topic_is_pilot(user))
		lights(user)

/obj/mecha/proc/topic_toggle_airtank(datum/act/op/A)
	var/mob/user = A.actor
	if(topic_is_pilot(user))
		internal_tank(user)

/obj/mecha/proc/topic_toggle_thrusters(datum/act/op/A)
	var/mob/user = A.actor
	thrusters(user)

/obj/mecha/proc/topic_smoke(datum/act/op/A)
	var/mob/user = A.actor
	smoke(user)

/obj/mecha/proc/topic_toggle_zoom(datum/act/op/A)
	var/mob/user = A.actor
	zoom(user)

/obj/mecha/proc/topic_toggle_defence_mode(datum/act/op/A)
	var/mob/user = A.actor
	defence_mode(user)

/obj/mecha/proc/topic_switch_damtype(datum/act/op/A)
	var/mob/user = A.actor
	query_damtype(user)

/obj/mecha/proc/topic_phasing(datum/act/op/A)
	var/mob/user = A.actor
	phasing(user)

/obj/mecha/proc/topic_rmictoggle(datum/act/op/A)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	radio.broadcasting = !radio.broadcasting
	send_byjax(user, "exosuit.browser", "rmicstate", (radio.broadcasting ? "Engaged" : "Disengaged"))

/obj/mecha/proc/topic_rspktoggle(datum/act/op/A)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	radio.listening = !radio.listening
	send_byjax(user, "exosuit.browser", "rspkstate", (radio.listening ? "Engaged" : "Disengaged"))

/obj/mecha/proc/topic_rfreq(datum/act/op/A, href_rfreq)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	var/delta = href_rfreq
	if(!isnum(delta))
		return
	var/new_frequency = radio.frequency + delta
	if((radio.frequency < PUBLIC_LOW_FREQ || radio.frequency > PUBLIC_HIGH_FREQ))
		new_frequency = sanitize_frequency(new_frequency)
	radio.set_frequency(new_frequency)
	send_byjax(user, "exosuit.browser", "rfreq", "[format_frequency(radio.frequency)]")

/obj/mecha/proc/topic_port_disconnect(datum/act/op/A)
	var/mob/user = A.actor
	if(topic_is_pilot(user))
		mecha_verb_disconnect_from_port(user)

/obj/mecha/proc/topic_port_connect(datum/act/op/A)
	var/mob/user = A.actor
	if(topic_is_pilot(user))
		mecha_verb_connect_to_port(user)

/obj/mecha/proc/topic_view_log(datum/act/op/A)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	// fully-structured TGUI log sub-view.
	tgui_subview = "log"
	tgui_interact(user)

/obj/mecha/proc/exosuit_default_name(datum/act/op/A)
	return initial(name)

/obj/mecha/proc/topic_change_name(datum/act/op/A)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	var/newname = sanitizeSafe(A.step_value("name"), MAX_NAME_LEN)
	if(newname)
		name = newname
	else
		tgui_alert_async(user, "nope.avi")

/obj/mecha/proc/topic_toggle_id_upload(datum/act/op/A)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	add_req_access = !add_req_access
	send_byjax(user, "exosuit.browser", "t_id_upload", "[add_req_access ? "L" : "Unl"]ock ID upload panel")

/obj/mecha/proc/topic_toggle_maint_access(datum/act/op/A)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	if(state)
		occupant_message(span_warning("Maintenance protocols in effect"))
		return
	maint_access = !maint_access
	send_byjax(user, "exosuit.browser", "t_maint_access", "[maint_access ? "Forbid" : "Permit"] maintenance protocols")

/obj/mecha/proc/topic_maint_access(datum/act/op/A)
	var/mob/user = A.actor
	if(!maint_access || !in_range(src, user))
		return
	if(state == MECHA_OPERATING)
		set_state(MECHA_BOLTS_SECURED)
		to_chat(user, "The securing bolts are now exposed.")
	else if(state == MECHA_BOLTS_SECURED)
		set_state(MECHA_OPERATING)
		to_chat(user, "The securing bolts are now hidden.")
	output_maintenance_dialog(active_id_card, user)

/// Requirement: the maintenance protocols are on and the securing bolts are exposed.
/obj/mecha/proc/bolts_exposed(datum/act/op/A)
	return state >= MECHA_BOLTS_SECURED ? null : MSG(req_silent)

/// Requirement: somebody sits in a passenger compartment (the tracked passenger_count).
/obj/mecha/proc/has_passengers(datum/act/op/A)
	return passenger_count > 0 ? null : MSG(mecha_passenger/none)

/// A compartment's occupancy changed: recount the passengers into the tracked mirror.
/obj/mecha/proc/mecha_passenger_changed()
	var/count = 0
	for(var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P in contents)
		count += P.slot_occupancy(OCCUPANT_SLOT_MECHA_PASSENGER)
	set_passenger_count(count)

/obj/mecha/proc/valve_subject(datum/act/op/A)
	return src

/obj/mecha/proc/valve_default(datum/act/op/A)
	return internal_tank_valve

/obj/mecha/proc/topic_set_internal_tank_valve(datum/act/op/A)
	var/mob/user = A.actor
	var/pressure = A.step_value("pressure")
	if(pressure)
		internal_tank_valve = pressure
		to_chat(user, "The internal pressure valve has been set to [internal_tank_valve]kPa.")

/// The passengers a maintenance link can pull out: occupant name -> their compartment.
/obj/mecha/proc/passenger_choices(datum/act/op/A)
	var/list/passengers = list()
	for(var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P in contents)
		if(P?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER))
			passengers["[P?.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER)]"] = P
	return passengers

/// The hatch the maintenance panel's answer names.
/obj/mecha/proc/chosen_passenger_bay(datum/act/op/A)
	var/list/passengers = passenger_choices(A)
	return passengers[A.step_value("passenger")]

/obj/mecha/proc/remove_passenger_begins(datum/act/op/A)
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P = chosen_passenger_bay(A)
	return msg_text(span_notice("You begin opening the hatch on [P]..."), span_infoplain(span_bold("[A.actor]") + " begins opening the hatch on [P]..."))

/obj/mecha/proc/topic_remove_passenger(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P = chosen_passenger_bay(A)
	if(!P)
		log_world("MECHA: remove_passenger on [src] by [user]: the chosen passenger is gone")
		return OP_REFUSED
	var/mob/passenger_occupant = P.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER)
	P.forced_out(user, passenger_occupant)
	return OP_OK

/obj/mecha/proc/topic_finish_req_access(datum/act/op/A)
	var/mob/user = A.actor
	if(!in_range(src, user))
		return
	add_req_access = 0
	// close TGUI panel (legacy browse(null))
	SStgui.close_uis(src)

/obj/mecha/proc/topic_dna_lock(datum/act/op/A)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	if(istype(user, /mob/living/carbon/brain))
		occupant_message("You are a brain. No.")
		return
	var/mob/living/pilot = user
	dna = pilot.dna?.unique_enzymes
	occupant_message("You feel a prick as the needle takes your DNA sample.")

/obj/mecha/proc/topic_reset_dna(datum/act/op/A)
	var/mob/user = A.actor
	if(topic_is_pilot(user))
		dna = null

/obj/mecha/proc/topic_drop_from_cargo(datum/act/op/A, href_drop_from_cargo)
	var/mob/user = A.actor
	if(!topic_is_pilot(user))
		return
	var/obj/O = href_drop_from_cargo
	if(!O)
		return
	occupant_message(span_notice("You unload [O]."))
	if(!slot_remove(O, get_turf(src)))
		O.forceMove(get_turf(src))
	LAZYREMOVE(cargo, O)
	var/turf/T = get_turf(O)
	if(T)
		T.Entered(O)
	mecha_log_message("Unloaded [O]. Cargo compartment capacity: [cargo_capacity - length(cargo)]")

/// Maintenance-panel settings: re-checked on the answer, still next to the mech with its bolts exposed.
/datum/prompt/number/mecha_tank_valve
	title = "Pressure setting"
	question = "Input new output pressure"
	timeout = 0
	recheck_on_open = TRUE
	ask_flags = ASK_ADJACENT | ASK_CAPABLE

/datum/prompt/number/mecha_tank_valve/recheck_extra()
	var/obj/mecha/M = subject
	return !istype(M) || QDELETED(M) || M.state < MECHA_BOLTS_SECURED ? "bolts secured" : null

/datum/prompt/number/mecha_tank_valve/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default, INFINITY, 0, timeout, FALSE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/// Which passenger to pull out: re-checked on the answer, still next to the mech with its bolts exposed.
/datum/prompt/choice/mecha_remove_passenger
	title = "Forcibly Remove Passenger"
	question = "Choose a passenger to forcibly remove."
	timeout = 0
	ask_flags = ASK_ADJACENT | ASK_CAPABLE

/datum/prompt/choice/mecha_remove_passenger/recheck_extra()
	var/obj/mecha/M = subject || owner
	return istype(M) && M.state >= MECHA_BOLTS_SECURED ? null : "bolts secured"



///////////////////////
///// Power stuff /////
///////////////////////

/obj/mecha/proc/has_charge(amount)
	return (get_charge()>=amount)

/obj/mecha/proc/get_charge()
	if(energy_relay)
		return energy_relay.dyngetcharge()
	return dyngetcharge()

/obj/mecha/proc/dyngetcharge()//returns null if no powercell, else returns cell.charge
	if(!src.cell) return
	return max(0, src.cell.charge)

/obj/mecha/proc/use_power(amount)
	return dynusepower(amount)

/obj/mecha/proc/dynusepower(amount)
	update_cell_alerts()
	var/obj/item/mecha_parts/component/electrical/EC = internal_components[MECH_ELECTRIC]

	if(EC)
		amount = amount * (2 - EC.get_efficiency()) * EC.charge_cost_mod
	else
		amount *= 5

	if(get_charge())
		cell.use(amount)
		return 1
	return 0

/obj/mecha/proc/give_power(amount)
	update_cell_alerts()
	var/obj/item/mecha_parts/component/electrical/EC = internal_components[MECH_ELECTRIC]

	if(!EC)
		amount /= 4
	else
		amount *= EC.get_efficiency()

	if(!isnull(get_charge()))
		cell.give(amount)
		return 1
	return 0

//This is for mobs mostly.
/obj/mecha/attack_generic(mob/user, damage, attack_message)

	user.setClickCooldown(user.get_attack_speed())
	if(!damage)
		return 0

	src.mecha_log_message("Attacked. Attacker - [user].",1)
	user.do_attack_animation(src)

	if(!mech_body_plan().strike_lands(src))//Deflected
		src.log_append_to_last("Armor saved.")
		src.occupant_message(span_notice("\The [user]'s attack is stopped by the armor."))
		act_message(user, null, others = span_infoplain(span_bold("%U%") + " rebounds off [src.name]'s armor!"))
		add_attack_logs(user, src, "attacked")
		play_sfx(src, SFX_WEAPONS_SLASH, extrarange = -1)

	else if(damage < damage_minimum) // Pathetic damage levels just don't harm MECH. // temp_damage_minimum -> damage_minimum
		src.occupant_message(span_notice("\The [user]'s doesn't dent \the [src] paint."))
		act_message(user, src, others = "%U%'s attack doesn't dent %T% armor")
		src.log_append_to_last("Armor saved.")
		play_sfx(src, SFX_EFFECTS_GLASSHIT, volume = 50)
		return

	else
		mech_body_plan().injure(src, damage, MELEE)
		if(damage > internal_damage_minimum)	//Only decently painful attacks trigger a chance of mech damage.
			mech_body_plan().roll_affliction(src, list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
		act_message(user, src, others = span_danger("%U% [attack_message] %T%!"))
		add_attack_logs(user, src, "attacked")

	return 1

/////////////////////////////////////////
//////// Mecha process() helpers ////////
/////////////////////////////////////////
/obj/mecha/proc/stop_process(process)
	set_current_processes(current_processes & ~process)
	if(process == MECHA_PROC_INT_TEMP)
		set_cabin_regulating(FALSE)

/obj/mecha/proc/start_process(process)
	set_current_processes(current_processes | process)

/////////////
/obj/mecha/cloak()
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	. = ..()
	if(occupant && occupant.client && dq_get_cloaked_selfimage(src))
		occupant.client.images += dq_get_cloaked_selfimage(src)

/obj/mecha/uncloak()
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(occupant && occupant.client && dq_get_cloaked_selfimage(src))
		occupant.client.images -= dq_get_cloaked_selfimage(src)
	return ..()

/obj/mecha/proc/update_cell_alerts()
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(occupant && cell)
		var/cellcharge = cell.charge/cell.maxcharge
		switch(cellcharge)
			if(0.75 to INFINITY)
				occupant.clear_alert("charge")
			if(0.5 to 0.75)
				occupant.throw_alert("charge", /atom/movable/screen/alert/lowcell, 1)
			if(0.25 to 0.5)
				occupant.throw_alert("charge", /atom/movable/screen/alert/lowcell, 2)
			if(0.01 to 0.25)
				occupant.throw_alert("charge", /atom/movable/screen/alert/lowcell, 3)
			else
				occupant.throw_alert("charge", /atom/movable/screen/alert/emptycell)

/obj/mecha/proc/update_damage_alerts()
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(occupant)
		var/integrity = get_integrity()/max_integrity*100
		switch(integrity)
			if(30 to 45)
				occupant.throw_alert("mech damage", /atom/movable/screen/alert/low_mech_integrity, 1)
			if(15 to 35)
				occupant.throw_alert("mech damage", /atom/movable/screen/alert/low_mech_integrity, 2)
			if(-INFINITY to 15)
				occupant.throw_alert("mech damage", /atom/movable/screen/alert/low_mech_integrity, 3)
			else
				occupant.clear_alert("mech damage")

/obj/mecha/blob_act(obj/structure/blob/B)
	var/datum/blob_type/blob = B?.overmind?.blob_type
	if(!istype(blob))
		return FALSE

	var/damage = rand(blob.damage_lower, blob.damage_upper)
	src.take_damage(damage, injury_kind_obj_damage_type(blob.injury_kind))
	visible_message(span_danger("\The [B] [blob.attack_verb] \the [src]!"), span_danger("[blob.attack_message_synth]!"))
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB)

	return TRUE

/obj/mecha
	damage_minimum = 5				//Incoming damage lower than this won't actually deal damage. Scrapes shouldn't be a real thing.
	minimum_penetration = 10		//Incoming damage won't be fully applied if you don't have at least 20. Almost all AP clears this.

/// Copies one mob's injuries onto another (used when an AI is temporarily
/// moved into a mecha shell and back). The target is fully healed first, then
/// each of the source's injuries is re-inflicted as the injury kind that makes
/// it, at the same part, and the source's oxygen debt is carried over.
/obj/mecha/proc/mirror_injury_state(mob/living/source_mob, mob/living/target_mob)
	if(!source_mob?.body || !target_mob)
		return
	target_mob.fully_heal()
	for(var/datum/affliction/A as anything in source_mob.body.afflictions)
		var/kind = mirrored_injury_kind(A)
		var/amount = A.load_value()
		if(!kind || amount <= 0)
			continue
		target_mob.injure(kind, amount, A.location?.organ_tag, src, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/oxygen_debt = source_mob.oxygen_debt()
	if(oxygen_debt)
		target_mob.add_oxygen_debt(oxygen_debt, src)

/// The injury kind (INJURY_*) that re-creates affliction `A`, or null when it
/// is not an injury (a disease, a lesion, a vital-system state).
/obj/mecha/proc/mirrored_injury_kind(datum/affliction/A)
	if(!A.injury_category)
		return null
	if(istype(A, /datum/affliction/wound))
		var/datum/affliction/wound/W = A
		switch(W.damage_type)
			if(CUT)
				return INJURY_CUT
			if(PIERCE)
				return INJURY_PIERCE
			if(BURN)
				return INJURY_BURN
	switch(A.injury_category)
		if(INJURY_CATEGORY_PHYSICAL)
			return INJURY_BLUNT
		if(INJURY_CATEGORY_THERMAL)
			return INJURY_BURN
		if(INJURY_CATEGORY_TOXIC)
			return INJURY_TOXIN
		if(INJURY_CATEGORY_GENETIC)
			return INJURY_CELLULAR
		if(INJURY_CATEGORY_NEURAL)
			return INJURY_NEURAL
		if(INJURY_CATEGORY_PAIN)
			return INJURY_PAIN
	return null

/// Icon-state suffix for the melee-mode action button, keyed on the mecha's melee injury kind.
/obj/mecha/proc/melee_damtype_icon()
	switch(melee_injury_kind)
		if(INJURY_BURN)
			return "fire"
		if(INJURY_TOXIN)
			return "tox"
		if(INJURY_PAIN)
			return "halloss"
	return "brute"

// selected, active_jetpack and energy_relay name mounted equipment: relation views (implicit REL).
// cell and internal_tank are implicit owns(policy = OWN_DELETE): a wreck takes them as salvage in Destroy()
// (own_take); otherwise the ownership policy deletes them with the mech.
// cabin_air may be rebound to a connected port's network mixture (set_port_network_air()): PROTO.

/// Detaches the component in `slot` (returned unowned; the caller moves or deletes it) and keeps
/// the empty slot key, since `internal_components` keys double as the mech's slot layout.
/obj/mecha/proc/release_component(slot)
	var/list/slots = internal_components
	. = own_take_member(src, nameof(internal_components), slot)
	if(!islist(slots))
		return
	if(!islist(internal_components))
		internal_components = slots // ALLOW(ownership): restores the slot-layout list own_take_member() nulled when it emptied; holds no entity
	internal_components[slot] = null // ALLOW(ownership): re-adds the empty slot marker (a null value, no entity)
