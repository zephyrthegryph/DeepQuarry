/mob/living/silicon/robot
	name = JOB_CYBORG
	real_name = JOB_CYBORG
	icon = 'icons/mob/robots.dmi'
	icon_state = "robot"
	endurance = 200
	nutrition = 0

	mob_bump_flag = ROBOT
	mob_swap_flags = ~HEAVY
	mob_push_flags = ~HEAVY //trundle trundle

	blocks_emissive = EMISSIVE_BLOCK_UNIQUE

	var/lights_on = FALSE // Is our integrated light on?
	var/grabbable = FALSE //disables/enables pick-up mechanics.
	var/robot_light_col = "#FFFFFF"
	/// Joules the power ledger moved this Life cycle (draws positive, charges negative). Stat panel readout.
	var/used_power_this_tick = 0
	var/sight_mode = 0
	var/custom_name = ""
	var/custom_sprite = FALSE //Due to all the sprites involved, a var for our custom borgs may be best
	var/sprite_name = null // The name of the borg, for the purposes of custom icon sprite indexing.
	var/crisis //Admin-settable for combat module use.
	var/crisis_override = 0
	var/integrated_light_power = 6
	var/list/robotdecal_on = list()
	var/glowy_enabled = FALSE

	can_be_antagged = TRUE

//Icon stuff

	var/datum/robot_sprite/sprite_datum 				// Sprite datum, holding all our sprite data. Resolved in Initialize.
	var/icon_selected = FALSE								// If icon selection has been completed yet
	var/list/sprite_extra_customization = list()
	var/rest_style = "Default"
	var/notransform
	does_spin = FALSE

	var/mutable_appearance/hat_overlay
	var/obj/item/clothing/head/hat // THE hat!

//Hud stuff

	var/atom/movable/screen/inv1 = null
	var/atom/movable/screen/inv2 = null
	var/atom/movable/screen/inv3 = null

	var/shown_robot_modules = 0 //Used to determine whether they have the module menu shown or not
	var/atom/movable/screen/robot_modules_background

	var/ui_theme = "ntos"
	var/selecting_module = FALSE

//3 Modules can be activated at any one time.
	var/obj/item/robot_module/module = null
	var/module_active = null

	var/obj/item/radio/borg/radio = null
	var/obj/item/communicator/integrated/communicator = null
	var/mob/living/silicon/ai/connected_ai = null
	/// The installed cell. Only set_cell() writes this.
	var/obj/item/cell/cell = null
	/// Cell the chassis is built with (setup_cell()).
	var/cell_type = /obj/item/cell/robot_station
	var/obj/machinery/camera/camera = null
	/// Photo camera type (aiCamera). Null for none.
	var/photo_camera_type = /obj/item/camera/siliconcam/robot_camera

	/// EMP drain on the cell is divided by this.
	var/cell_emp_mult = 2

	var/scrubbing = FALSE //Floor cleaning enabled

	// Subtype limited modules or admin restrictions
	var/list/restrict_modules_to

	/// Body parts, a flat list indexed by ROBOT_SLOT_*. Built by initialize_components().
	var/list/components

	var/obj/item/mmi/mmi = null

	var/obj/item/pda/ai/rbPDA = null

	var/opened = FALSE
	var/emagged = FALSE
	var/emag_items = FALSE
	var/wiresexposed = FALSE
	var/locked = TRUE
	/// TRUE while the power bus meets demand. Only update_power_state() writes this.
	var/has_power = TRUE
	/// Cached draw of parts, modules and lights, joules per Life cycle.
	/// Recomputed on change by recompute_power_demand(), never summed per tick.
	var/power_demand = 0
	/// Accumulated heat the cooling loop failed to shed (machine physiology).
	var/heat_debt = 0
	var/list/req_access = list(ACCESS_ROBOTICS)
	var/ident = 0
	var/viewalerts = 0
	var/modtype = "Default"
	var/sprite_type = null
	var/lower_mod = 0
	var/jetpack = 0
	var/datum/effect/effect/system/ion_trail_follow/ion_trail = null
	var/datum/effect/effect/system/spark_spread/spark_system //So they can initialize sparks whenever/N
	var/jeton = 0
	/// Timer id of a pending killswitch, or null.
	var/killswitch
	/// Timer id of an active weapon lock, or null.
	var/weapon_lock
	var/lawupdate = TRUE //Cyborgs will sync their laws with their AI by default
	var/lockcharge //Used when looking to see if a borg is locked down.
	var/lockdown = 0 //Controls whether or not the borg is actually locked down.
	var/speed = 0 //Cause sec borgs gotta go fast //No they dont!
	var/scrambledcodes = FALSE // Used to determine if a borg shows up on the robotics console. Setting to one hides them.
	var/tracking_entities = 0 //The number of known entities currently accessing the internal camera
	var/braintype = JOB_CYBORG

	var/obj/item/implant/restrainingbolt/bolt	// The restraining bolt installed into the cyborg.
	var/datum/tgui_module/robot_ui/robotact

	var/static/list/robot_verbs_default = list(
		/mob/living/silicon/robot/proc/sensor_mode,
		/mob/living/silicon/robot/proc/robot_checklaws,
		/mob/living/silicon/robot/proc/robot_mount,
		/mob/living/silicon/robot/proc/take_image,
		/mob/living/silicon/robot/proc/view_images,
		/mob/living/silicon/robot/proc/delete_images,
		/mob/living/silicon/robot/proc/ex_reserve_refill, // re-adds the extinquisher refill from water
		/mob/living/proc/toggle_rider_reins,
		/mob/living/proc/vertical_nom,
		/mob/living/proc/shred_limb,
		/mob/living/proc/dominate_prey,
		/mob/living/proc/lend_prey_control
	)

	var/has_recoloured = FALSE
	var/vtec_active = FALSE

	var/list/vore_light_states = list() //Robot exclusive
	vore_capacity_ex = list()
	vore_fullness_ex = list()
	vore_icon_bellies = list()


// --- Lifecycle ------------------------------------------------------------------------------

/mob/living/silicon/robot/Initialize(mapload, is_decoy)
	spark_system = new /datum/effect/effect/system/spark_spread()
	spark_system.set_up(5, 0, src)
	spark_system.attach(src)
	robotact = new(src)
	RegisterSignal(src, COMSIG_LIVING_SHIELD_INJURY, PROC_REF(absorb_injury_with_shield))

	add_language(LANGUAGE_ROBOT_TALK, 1)
	add_language(LANGUAGE_GALCOM, 1)
	add_language(LANGUAGE_EAL, 1)

	set_wires(new /datum/wires/robot(src))

	robot_modules_background = new()
	robot_modules_background.icon_state = "block"
	ident = rand(1, 999)
	updatename(modtype)

	setup_radio()
	setup_camera()
	setup_brain()
	setup_laws()
	setup_module()
	initialize_components()
	setup_cell()

	. = ..()

	add_robot_verbs()
	setup_hud_images()
	resolve_sprite_datum()
	recompute_power_demand()
	update_senses()

	AddComponent(/datum/component/hose_connector/input/borg)
	AddComponent(/datum/component/hose_connector/output/borg)

/mob/living/silicon/robot/LateInitialize()
	pick_module()
	update_icon()

/mob/living/silicon/robot/proc/setup_radio()
	radio = new /obj/item/radio/borg(src)
	common_radio = radio

/// The photo camera and the machinery camera that feeds the robots network.
/mob/living/silicon/robot/proc/setup_camera()
	if(photo_camera_type)
		aiCamera = new photo_camera_type(src)
	if(!scrambledcodes && !camera)
		camera = new /obj/machinery/camera(src)
		camera.c_tag = real_name
		camera.replace_networks(list(NETWORK_DEFAULT,NETWORK_ROBOTS))
		if(wires.is_cut(WIRE_BORG_CAMERA))
			camera.status = 0

/// Chassis that come with a brain override this. Assembled cyborgs get their
/// MMI from the robot suit.
/mob/living/silicon/robot/proc/setup_brain()
	return

/mob/living/silicon/robot/proc/setup_laws()
	laws = new using_map.default_law_type //use map's default
	additional_law_channels["Binary"] = "#b"
	if(!lawupdate || scrambledcodes)
		return
	var/new_ai = select_active_ai_with_fewest_borgs()
	if(new_ai)
		connect_to_ai(new_ai)
	else
		lawupdate = FALSE

/// Chassis with a fixed module create it here.
/mob/living/silicon/robot/proc/setup_module()
	return

/mob/living/silicon/robot/proc/setup_cell()
	var/obj/item/cell/new_cell = cell
	cell = null
	if(ispath(new_cell))
		new_cell = new new_cell(src)
	else if(!new_cell && cell_type)
		new_cell = new cell_type(src)
	set_cell(new_cell)

/mob/living/silicon/robot/proc/setup_hud_images()
	hud_list[HEALTH_HUD]		= gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_HEALTH)
	hud_list[STATUS_HUD]		= gen_hud_image('icons/mob/hud.dmi', src, "hudhealth100", plane = PLANE_CH_STATUS)
	hud_list[LIFE_HUD]			= gen_hud_image('icons/mob/hud.dmi', src, "hudhealth100", plane = PLANE_CH_LIFE)
	hud_list[ID_HUD]			= gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_ID)
	hud_list[WANTED_HUD]		= gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_WANTED)
	hud_list[IMPLOYAL_HUD]		= gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_IMPLOYAL)
	hud_list[IMPCHEM_HUD]		= gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_IMPCHEM)
	hud_list[IMPTRACK_HUD]		= gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_IMPTRACK)
	hud_list[SPECIALROLE_HUD]	= gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_SPECIAL)

/// The sprite datum is never null after Initialize: the module default, or
/// the generic default when the sprite subsystem isn't ready.
/mob/living/silicon/robot/proc/resolve_sprite_datum()
	if(sprite_datum)
		return
	if(SSrobot_sprites)
		sprite_datum = SSrobot_sprites.get_default_module_sprite(modtype)
	if(!sprite_datum)
		sprite_datum = new /datum/robot_sprite/default(src)

/mob/living/silicon/robot/rejuvenate()
	// Clear every located load first, then rebuild any fried or missing parts.
	fully_heal()
	for(var/datum/robot_component/C as anything in components)
		if(C.internal)
			C.installed = ROBOT_PART_INSTALLED
			continue
		if(C.installed == ROBOT_PART_DESTROYED)
			qdel(C.uninstall())
		if(C.installed == ROBOT_PART_INSTALLED)
			continue
		if(C.slot == ROBOT_SLOT_POWER)
			set_cell(new /obj/item/cell/robot_station(src))
		else if(C.external_type)
			C.install(new C.external_type(src))
	if(cell)
		add_power(ROBOT_CELL_JOULES(cell.maxcharge), src)
	heat_debt = 0
	..()
	update_power_state()
	update_icon()

//If there's an MMI in the robot, have it ejected when the mob goes away. --NEO
//Improved /N
/mob/living/silicon/robot/Destroy()
	if(mmi)//Safety for when a cyborg gets dust()ed. Or there is no MMI inside.
		if(mind)
			var/turf/T = get_turf(loc)//To hopefully prevent run time errors.
			if(T)
				mmi.forceMove(T)
			var/datum/component/mind_host/host = get_mind_host(mmi)
			if(host)
				var/mob/living/carbon/brain/view = host.receive_mind(mind, "cyborg [src] destroyed")
				view.remove_language(LANGUAGE_ROBOT_TALK)
			else if(!shell) // Shells don't have brainmbos in their MMIs.
				to_chat(src, span_danger("Oops! Something went very wrong, your MMI was unable to receive your mind. You have been ghosted. Please make a bug report so we can fix this bug."))
				ghostize()
			mmi = null
		else
			QDEL_NULL(mmi)
	disconnect_from_ai(TRUE)
	if(killswitch)
		deltimer(killswitch)
		killswitch = null
	if(weapon_lock)
		deltimer(weapon_lock)
		weapon_lock = null
	if(shell)
		if(deployed)
			undeploy()
		revert_shell() // To get it out of the GLOB list.
	QDEL_NULL(wires)
	sprite_datum = null
	QDEL_NULL(robotact)
	set_cell(null)
	QDEL_LIST(components)
	if(bolt)
		QDEL_NULL(bolt)
	if(module)
		QDEL_NULL(module)
	if(radio)
		QDEL_NULL(radio)
	if(communicator)
		QDEL_NULL(communicator)
	if(camera)
		QDEL_NULL(camera)
	if(rbPDA)
		QDEL_NULL(rbPDA)
	if(hat)
		var/turf/T = get_turf(src)
		if(T)
			hat.forceMove(T)
			hat = null
		else
			QDEL_NULL(hat)
	if(hat_overlay)
		QDEL_NULL(hat_overlay)
	if(inv1)
		QDEL_NULL(inv1)
	if(inv2)
		QDEL_NULL(inv2)
	if(inv3)
		QDEL_NULL(inv3)
	if(robot_modules_background)
		QDEL_NULL(robot_modules_background)
	if(ion_trail)
		QDEL_NULL(ion_trail)
	if(spark_system)
		QDEL_NULL(spark_system)
	module_active = null

	return ..()

/// Stat changes are events: equipment drops once, senses and sprite refresh once.
/mob/living/silicon/robot/set_stat(new_stat)
	. = ..()
	if(!.)
		return
	if(stat != CONSCIOUS)
		uneq_all()
	update_senses()
	update_icon()


// --- Power ledger ----------------------------------------------------------------------------
// draw_power() and add_power() are the only writers of the cell's charge in
// robot code. Amounts are joules; the cell stores joules * CELLRATE.

/// Take `joules` from the cell, all or nothing. `reserve` joules must remain
/// afterwards. `partial` takes whatever is there instead (drains). Returns
/// TRUE if anything was drawn.
/mob/living/silicon/robot/proc/draw_power(joules, datum/source, reserve = 0, partial = FALSE)
	if(joules <= 0)
		return TRUE
	if(!cell)
		return FALSE
	var/units = joules * CELLRATE
	if(partial)
		var/drawn = cell.use(units, FALSE)
		used_power_this_tick += drawn / CELLRATE
		return drawn > 0
	if(!cell.check_charge(units + max(reserve, 0) * CELLRATE))
		return FALSE
	if(cell.use(units, FALSE) < units)
		return FALSE
	used_power_this_tick += joules
	return TRUE

/// Put up to `joules` into the cell. Returns the joules actually stored.
/mob/living/silicon/robot/proc/add_power(joules, datum/source)
	if(joules <= 0 || !cell)
		return 0
	var/stored = cell.give(joules * CELLRATE, FALSE) / CELLRATE
	used_power_this_tick -= stored
	return stored

/// Power sinks and APC drains pull through the ledger too.
/mob/living/silicon/robot/drain_power(drain_check, surge, amount = 0)
	if(drain_check)
		return 1
	if(!draw_power(amount, src))
		return 0
	if(prob(10)) // Spam Protection
		to_chat(src, span_danger("Warning: Unauthorized access through power channel [rand(11,29)] detected!"))
	return amount

/// The one writer of `cell`. Watches the cell for deletion and shields it
/// from EMP recursion (the robot drains it itself in emp_act()).
/mob/living/silicon/robot/proc/set_cell(obj/item/cell/new_cell)
	if(cell == new_cell)
		return
	if(cell)
		UnregisterSignal(cell, list(COMSIG_ATOM_PRE_EMP_ACT, COMSIG_QDELETING))
	cell = new_cell
	if(new_cell)
		if(new_cell.loc != src)
			new_cell.forceMove(src)
		RegisterSignal(new_cell, COMSIG_ATOM_PRE_EMP_ACT, PROC_REF(shield_cell_from_emp))
		RegisterSignal(new_cell, COMSIG_QDELETING, PROC_REF(on_cell_deleted))
		var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
		if(mount && mount.wrapped != new_cell)
			mount.install(new_cell)
	if(!QDELETED(src))
		update_power_state()

/// Take the cell out of its mount. Its afflictions leave with it.
/mob/living/silicon/robot/proc/remove_cell()
	var/obj/item/cell/old_cell = cell
	if(!old_cell)
		return null
	var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
	if(mount?.wrapped == old_cell)
		mount.uninstall()
	set_cell(null)
	return old_cell

/mob/living/silicon/robot/proc/shield_cell_from_emp(datum/source, severity)
	SIGNAL_HANDLER
	return EMP_PROTECT_SELF

/mob/living/silicon/robot/proc/on_cell_deleted(datum/source)
	SIGNAL_HANDLER
	var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
	if(mount?.wrapped == source)
		mount.wrapped = null
		mount.installed = ROBOT_PART_MISSING
	set_cell(null)

/// Recompute the cached demand. Called on toggle, install, equip and lights
/// change; the power system spends it every cycle without summing.
/mob/living/silicon/robot/proc/recompute_power_demand()
	var/demand = 0
	for(var/datum/robot_component/C as anything in components)
		demand += C.idle_draw()
	for(var/obj/item/I as anything in get_all_held_items())
		demand += ROBOT_MODULE_DRAW
	if(lights_on)
		demand += ROBOT_LIGHT_DRAW
	power_demand = demand * CYBORG_POWER_USAGE_MULTIPLIER

/// Can the bus deliver right now? A missing cell, a destroyed mount, or an
/// empty cell is a brownout.
/mob/living/silicon/robot/proc/power_bus_ok()
	var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
	return cell && mount?.is_intact() && cell.charge > 0

/// Apply the power state: parts, camera, radio, lights and consciousness
/// update once, on the change. `delivered` is the ledger's verdict this
/// cycle; null re-reads the bus (cell swapped, mount changed).
/mob/living/silicon/robot/proc/update_power_state(delivered = null)
	var/new_state = isnull(delivered) ? !!power_bus_ok() : !!delivered
	var/changed = FALSE
	for(var/datum/robot_component/C as anything in components)
		if(C.set_powered(new_state))
			changed = TRUE
	if(new_state != has_power)
		has_power = new_state
		changed = TRUE
		if(!has_power)
			to_chat(src, span_red("You are now running on emergency backup power."))
			if(lights_on)
				set_lights(FALSE)
		log_runtime("ROBOT_POWER: [key_name(src)] power [has_power ? "restored" : "lost"] (demand [power_demand] J/cycle).")
		body?.on_status_changed()
	if(changed)
		update_senses()

/mob/living/silicon/robot/machine_power_ok()
	return has_power


// --- Parts -----------------------------------------------------------------------------------

/// A part was installed, removed, destroyed, toggled or its integrity
/// changed. Everything derived from parts updates here, once.
/mob/living/silicon/robot/proc/on_part_changed(datum/robot_component/C)
	if(!body || QDELETED(src))
		return
	recompute_power_demand()
	update_power_state()
	update_canmove()

/mob/living/silicon/robot/proc/toggle_component(slot)
	var/datum/robot_component/C = get_component(slot)
	if(!C)
		return FALSE
	C.toggled = !C.toggled
	on_part_changed(C)
	return TRUE

/// Camera feed, radio and blindness follow the parts, power and stat.
/mob/living/silicon/robot/proc/update_senses()
	if(camera && !scrambledcodes)
		var/camera_on = stat != DEAD && !wires.is_cut(WIRE_BORG_CAMERA) && is_component_functioning(ROBOT_SLOT_CAMERA)
		camera.set_status(camera_on ? 1 : 0)
	if(radio)
		radio.on = is_component_functioning(ROBOT_SLOT_RADIO) ? 1 : 0
	var/sees = stat != DEAD && !paralysis && !eye_blind && !(sdisabilities & BLIND) && is_component_functioning(ROBOT_SLOT_CAMERA)
	blinded = !sees
	if(stat == DEAD)
		return
	if(blinded)
		overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
	else
		clear_fullscreen("blind")
		// A worn camera sees through noise.
		set_fullscreen(component_function(ROBOT_SLOT_CAMERA) < 0.5 || (disabilities & NEARSIGHTED), "impaired", /atom/movable/screen/fullscreen/impaired, 1)


// --- Lights -----------------------------------------------------------------------------------

/mob/living/silicon/robot/proc/set_lights(new_state)
	if(lights_on == new_state)
		return
	lights_on = new_state
	refresh_glow()
	recompute_power_demand()
	update_icon()

/mob/living/silicon/robot/verb/toggle_lights()
	set category = "Abilities.Silicon"
	set name = "Toggle Lights"

	if(!lights_on && !has_power)
		to_chat(src, span_warning("There isn't enough power to run your integrated light."))
		return
	set_lights(!lights_on)
	to_chat(src, span_filter_notice("You [lights_on ? "enable" : "disable"] your integrated light."))

/datum/life_system/light/silicon/robot
	mob_type = /mob/living/silicon/robot

/datum/life_system/light/silicon/robot/tick(mob/living/silicon/robot/self, datum/life_context/ctx)
	if(self.lights_on)
		self.set_light(self.integrated_light_power, 1, self.robot_light_col)
		return TRUE
	return ..()


// --- Countdowns ------------------------------------------------------------------------------

/mob/living/silicon/robot/proc/start_killswitch(delay = ROBOT_KILLSWITCH_DELAY)
	if(killswitch)
		return FALSE
	killswitch = addtimer(CALLBACK(src, PROC_REF(fire_killswitch)), delay, TIMER_STOPPABLE | TIMER_DELETE_ME)
	log_game("ROBOT: killswitch armed on [key_name(src)] ([delay / (1 SECOND)]s).")
	return TRUE

/mob/living/silicon/robot/proc/cancel_killswitch()
	if(!killswitch)
		return FALSE
	deltimer(killswitch)
	killswitch = null
	return TRUE

/mob/living/silicon/robot/proc/fire_killswitch()
	killswitch = null
	if(stat == DEAD)
		return
	to_chat(src, span_danger("Killswitch Activated"))
	log_game("ROBOT: killswitch fired on [key_name(src)].")
	addtimer(CALLBACK(src, TYPE_PROC_REF(/mob, gib)), 0.5 SECONDS, TIMER_DELETE_ME)

/// Lock the modules. Equipment drops once; activation is refused until the lock times out.
/mob/living/silicon/robot/proc/start_weapon_lock(duration = ROBOT_WEAPON_LOCK_DELAY)
	if(weapon_lock)
		deltimer(weapon_lock)
	weapon_lock = addtimer(CALLBACK(src, PROC_REF(end_weapon_lock)), duration, TIMER_STOPPABLE | TIMER_DELETE_ME)
	uneq_all()
	to_chat(src, span_danger("Weapon lock engaged."))

/mob/living/silicon/robot/proc/end_weapon_lock()
	weapon_lock = null
	to_chat(src, span_danger("Weapon Lock Timed Out!"))


// --- Naming ------------------------------------------------------------------------------------

/mob/living/silicon/robot/SetName(pickedName as text)
	custom_name = pickedName
	updatename()

/mob/living/silicon/robot/proc/sync()
	if(lawupdate && connected_ai)
		lawsync()
		photosync()

// setup the PDA and its name
/mob/living/silicon/robot/proc/setup_PDA()
	if (!rbPDA)
		rbPDA = new/obj/item/pda/ai(src)
	rbPDA.set_name_and_job(name,"[modtype] [braintype]")
	add_verb(src, /obj/item/pda/ai/verb/cmd_pda_open_ui)

/mob/living/silicon/robot/proc/setup_communicator()
	if (!communicator)
		communicator = new/obj/item/communicator/integrated(src)
	communicator.register_device(name, "[modtype] [braintype]")
	add_verb(src, /obj/item/communicator/integrated/verb/activate)

/mob/living/silicon/robot/drop_from_inventory(obj/item/W, atom/target = null)
	if(module_active && istype(module_active,/obj/item/gripper))
		var/obj/item/gripper/robot_gripper = module_active
		robot_gripper.drop_item_nm(target)
	return FALSE //Dropping things from robots break everything.

/mob/living/silicon/robot/proc/pick_module()
	if(icon_selected)
		return
	if(module)
		var/list/module_sprites = SSrobot_sprites.get_module_sprites(module, src)
		if(module_sprites.len == 1 || !client)
			if(!module_sprites.len)
				return
			sprite_datum = module_sprites[1]
			sprite_datum.do_equipment_glamour(module)
			update_worn_icons()
			return
	if(mind)
		sprite_name = mind.name
	if(!selecting_module)
		var/datum/tgui_module/robot_ui_module/ui = new(src)
		ui.tgui_interact(src)

/mob/living/silicon/robot/proc/update_braintype()
	if(istype(mmi, /obj/item/mmi/digital/posibrain))
		braintype = BORG_BRAINTYPE_POSI
	else if(istype(mmi, /obj/item/mmi/digital/robot))
		braintype = BORG_BRAINTYPE_DRONE
	else if(istype(mmi, /obj/item/mmi/inert/ai_remote))
		braintype = BORG_BRAINTYPE_AI_SHELL
	else
		braintype = BORG_BRAINTYPE_CYBORG

/mob/living/silicon/robot/proc/updatename(prefix as text)
	if(prefix)
		modtype = prefix

	update_braintype()

	var/changed_name = ""
	if(custom_name)
		changed_name = custom_name
		notify_ai(ROBOT_NOTIFICATION_NEW_NAME, real_name, changed_name)
	else
		changed_name = "[modtype] [braintype]-[num2text(ident)]"

	real_name = changed_name
	name = real_name

	// if we've changed our name, we also need to update the display name for our PDA
	setup_PDA()

	// as well as our communicator registration
	setup_communicator()

	//We also need to update name of internal camera.
	if (camera)
		camera.c_tag = changed_name

	//Flavour text.
	if(client)
		// migrated flavour_texts_robot
		var/list/_robot_flavor = client.prefs.read_preference(/datum/preference/flavour_texts_robot)
		var/module_flavour = LAZYACCESS(_robot_flavor, modtype)
		if(module_flavour && (module_flavour != " " || module_flavour != ".")) // Skip module flavor if " " or "."
			flavor_text = module_flavour
		else
			flavor_text = LAZYACCESS(_robot_flavor, "Default")
		//and meta info
		identity.ooc_notes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes)
		identity.ooc_notes_likes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_likes)
		identity.ooc_notes_dislikes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_dislikes)
		identity.ooc_notes_favs = read_preference(/datum/preference/text/living/ooc_notes_favs)
		identity.ooc_notes_maybes = read_preference(/datum/preference/text/living/ooc_notes_maybes)
		identity.ooc_notes_style = read_preference(/datum/preference/toggle/living/ooc_notes_style)
		private_notes = client.prefs.read_preference(/datum/preference/text/living/private_notes)
		custom_link = client.prefs.read_preference(/datum/preference/text/human/custom_link) // migrated pref

/mob/living/silicon/robot/verb/namepick()
	set name = "Pick Name"
	set category = "Abilities.Settings"

	if(custom_name)
		to_chat(src, "You can't pick another custom name. [isshell(src) ? "" : "Go ask for a name change."]")
		return 0

	var/newname = sanitizeSafe(tgui_input_text(src,"You are a robot. Enter a name, or leave blank for the default name.", "Name change","", MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
	if (newname)
		custom_name = newname
		sprite_name = newname

	updatename()

/mob/living/silicon/robot/verb/extra_customization()
	set name = "Customize Appearance"
	set category = "Abilities.Settings"
	set desc = "Customize your appearance (assuming your chosen sprite allows)."

	if(!sprite_datum || !sprite_datum.has_extra_customization)
		to_chat(src, span_warning("Your sprite cannot be customized."))
		return

	sprite_datum.handle_extra_customization(src)

/mob/living/silicon/robot/verb/toggle_glowy_stomach()
	set category = "Abilities.Settings"
	set name = "Toggle Glowing Stomach & Accents"

	glowy_enabled = !glowy_enabled
	if(glowy_enabled)
		to_chat(src, span_filter_notice("Your stomach will now glow and any naturally glowing accents you have will now appear!"))
	else
		to_chat(src, span_filter_notice("Your stomach will no longer glow, and any naturally glowing accents you have will be hidden!"))
	update_icon()

/mob/living/silicon/robot/verb/spark_plug() //So you can still sparkle on demand without violence.
	set category = "Abilities.Silicon"
	set name = "Emit Sparks"
	to_chat(src, span_filter_notice("You harmlessly spark."))
	spark_system.start()

///Essentially, a Activate Held Object mode for borgs that acts just like pressing Z in hotkey mode but also works well with multibelts.
/mob/living/silicon/robot/verb/alt_mode()
	set name = "Robot Activate Held Object"
	set category = "Object"
	set src = usr

	if(!checkClickCooldown())
		return

	setClickCooldown(1)

	var/obj/item/W = module_active
	if(module_active)
		W.attack_self(src)
	return

/mob/living/silicon/robot/verb/toggle_grabbability() // Grisp the preyborgs with consent (and allows for your borg to still be pet).
	set category = "Abilities.Silicon"
	set name = "Toggle Pickup"
	grabbable = !grabbable
	to_chat(src, span_filter_notice("You feel [grabbable ? "more" : "less"] grabbable."))

// this function displays jetpack pressure in the stat panel
// TGPanel
/mob/living/silicon/robot/proc/show_jetpack_pressure()
	. = list()
	// if you have a jetpack, show the internal tank pressure
	var/obj/item/tank/jetpack/current_jetpack = installed_jetpack()
	if (current_jetpack)
		. += "Internal Atmosphere Info: [current_jetpack.name]"
		. += "Tank Pressure: [current_jetpack.air_contents.return_pressure()]"


// this function returns the robots jetpack, if one is installed
/mob/living/silicon/robot/proc/installed_jetpack()
	if(module)
		return (locate(/obj/item/tank/jetpack) in module.modules)
	return 0


// this function displays the cyborgs current cell charge in the stat panel
/mob/living/silicon/robot/proc/show_cell_power()
	. = list()
	if(cell)
		. += "Charge Left: [round(cell.percent())]%"
		. += "Cell Rating: [round(cell.maxcharge)]" // Round just in case we somehow get crazy values
		. += "Power Cell Load: [round(used_power_this_tick)]W"
	else
		. += "No Cell Inserted!"

// function to toggle VTEC once installed
/mob/living/silicon/robot/proc/toggle_vtec()
	set name = "Toggle VTEC"
	set category = "Abilities.Silicon"
	vtec_active = !vtec_active
	hud_used.toggle_vtec_control()
	to_chat(src, span_filter_notice("VTEC module [vtec_active  ? "enabled" : "disabled"]."))

// update the status screen display
/mob/living/silicon/robot/get_status_tab_items()
	. = ..()
	. += ""
	. += show_cell_power()
	. += show_jetpack_pressure()
	. += "Lights: [lights_on ? "ON" : "OFF"]"
	. += "Pickup: [grabbable ? "ENABLED" : "DISABLED"]"
	if(module)
		for(var/datum/matter_synth/ms in module.synths)
			. += "[ms.name]: [ms.energy]/[ms.max_energy]"

/mob/living/silicon/robot/restrained()
	return 0

/mob/living/silicon/robot/bullet_act(obj/item/projectile/Proj)
	..(Proj)
	if(prob(75) && Proj.damage > 0) spark_system.start()
	return 2


// --- Tool and item interactions ---------------------------------------------------------------

/mob/living/silicon/robot/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/handcuffs)) // fuck i don't even know why isrobot() in handcuff code isn't working so this will have to do
		return
	if(opened && install_component(W, user))
		return
	if(opened && istype(W, /obj/item/implant/restrainingbolt) && !cell)
		install_bolt(W, user)
		return
	if(istype(W, /obj/item/aiModule))
		upload_law_module(W, user)
		return
	if(istype(W, /obj/item/stack/cable_coil) && can_rewire())
		cable_act(W, user)
		return
	if(istype(W, /obj/item/cell) && opened)
		insert_cell(W, user)
		return
	if(istype(W, /obj/item/encryptionkey) && opened)
		if(radio)//sanityyyyyy
			radio.attackby(W,user)//GTFO, you have your own procs
		else
			to_chat(user, span_filter_notice("Unable to locate a radio."))
		return
	if(W.GetID())
		swipe_id(W, user)
		return
	if(istype(W, /obj/item/borg/upgrade))
		apply_upgrade(W, user)
		return
	if(!(istype(W, /obj/item/robotanalyzer) || istype(W, /obj/item/healthanalyzer)) && W.force > 0)
		spark_system.start()
	return ..()

/// Insert a part into its empty slot. Afflictions it carried come back with it.
/mob/living/silicon/robot/proc/install_component(obj/item/W, mob/user)
	for(var/datum/robot_component/C as anything in components)
		if(C.internal || C.installed != ROBOT_PART_MISSING || !C.external_type || !istype(W, C.external_type))
			continue
		user.drop_item()
		W.forceMove(src)
		C.install(W)
		to_chat(user, span_notice("You install the [W.name]."))
		return TRUE
	return FALSE

/mob/living/silicon/robot/proc/install_bolt(obj/item/implant/restrainingbolt/W, mob/user)
	if(bolt)
		to_chat(user, span_notice("There is already a restraining bolt installed in this cyborg."))
		return FALSE
	user.drop_from_inventory(W)
	W.forceMove(src)
	bolt = W
	to_chat(user, span_notice("You install \the [W]."))
	return TRUE

/mob/living/silicon/robot/proc/upload_law_module(obj/item/aiModule/M, mob/user)
	if(!opened)
		to_chat(user, span_warning("You need to open \the [src]'s panel before you can modify them."))
		return FALSE
	if(shell) // AI shells always have the laws of the AI
		to_chat(user, span_warning("\The [src] is controlled remotely! You cannot upload new laws this way!"))
		return FALSE
	M.install(src, user)
	return TRUE

/// Can burnt wiring be reached with a cable coil?
/mob/living/silicon/robot/proc/can_rewire()
	return wiresexposed

/mob/living/silicon/robot/proc/cable_act(obj/item/stack/cable_coil/coil, mob/user)
	if(!injury_load(INJURY_CATEGORY_THERMAL))
		to_chat(user, span_filter_notice("Nothing to fix here!"))
		return FALSE
	if(!coil.use(1))
		return FALSE
	user.setClickCooldown(user.get_attack_speed(coil))
	mend(TREAT_WIRING_REPAIR, 30)
	visible_message(span_filter_notice(span_red("[user] has fixed some of the burnt wires on [src]!")))
	return TRUE

/// Put a cell into the empty mount. It keeps whatever damage it carried.
/mob/living/silicon/robot/proc/insert_cell(obj/item/cell/W, mob/user)
	var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
	if(wiresexposed)
		to_chat(user, span_filter_notice("Close the panel first."))
		return FALSE
	if(cell)
		to_chat(user, span_filter_notice("There is a power cell already installed."))
		return FALSE
	if(mount.installed == ROBOT_PART_DESTROYED)
		to_chat(user, span_filter_notice("The cell mount is fried. Remove the remains first."))
		return FALSE
	if(W.w_class != ITEMSIZE_NORMAL)
		to_chat(user, span_filter_notice("\The [W] is too [W.w_class < ITEMSIZE_NORMAL ? "small" : "large"] to fit here."))
		return FALSE
	user.drop_item()
	set_cell(W)
	to_chat(user, span_filter_notice("You insert the power cell."))
	return TRUE

/// Swiping an ID locks or unlocks the interface.
/mob/living/silicon/robot/proc/swipe_id(obj/item/W, mob/user)
	if(emagged)//still allow them to open the cover
		to_chat(user, span_filter_notice("The interface seems slightly damaged."))
	if(opened)
		to_chat(user, span_filter_notice("You must close the cover to swipe an ID card."))
		return FALSE
	if(!allowed(user))
		to_chat(user, span_filter_notice(span_red("Access denied.")))
		return FALSE
	locked = !locked
	to_chat(user, span_filter_notice("You [ locked ? "lock" : "unlock"] [src]'s interface."))
	update_icon()
	return TRUE

/mob/living/silicon/robot/proc/apply_upgrade(obj/item/borg/upgrade/U, mob/user)
	if(!opened)
		to_chat(user, span_filter_notice("You must access the borgs internals!"))
		return FALSE
	if(!module && U.require_module)
		to_chat(user, span_filter_notice("The borg must choose a module before it can be upgraded!"))
		return FALSE
	if(user == src && istype(U, /obj/item/borg/upgrade/utility/reset))
		to_chat(user, span_warning("You are restricted from reseting your own module."))
		return FALSE
	if(U.locked)
		to_chat(user, span_filter_notice("The upgrade is locked and cannot be used yet!"))
		return FALSE
	if(!U.action(user, src))
		to_chat(user, span_filter_notice("Upgrade error!"))
		return FALSE
	to_chat(user, span_filter_notice("You apply the upgrade to [src]!"))
	user.drop_item()
	U.forceMove(src)
	hud_used?.update_robot_modules_display()
	return TRUE

/mob/living/silicon/robot/wirecutter_act(mob/user, obj/item/tool)
	if(!wiresexposed)
		to_chat(user, span_filter_notice("You can't reach the wiring."))
		return ITEM_INTERACT_BLOCKING
	wires.Interact(user)
	return ITEM_INTERACT_SUCCESS

/// Crowbar: open or close the cover, lever out the brain, or pry out a part.
/mob/living/silicon/robot/crowbar_act(mob/user, obj/item/tool)
	if(user.a_intent == I_HURT)
		return ITEM_INTERACT_SKIP_TO_ATTACK
	if(!opened)
		open_cover(user)
		return ITEM_INTERACT_SUCCESS
	if(cell)
		close_cover(user)
		return ITEM_INTERACT_SUCCESS
	if(wiresexposed && wires.is_all_cut())
		extract_mmi(user)
		return ITEM_INTERACT_SUCCESS
	pry_component(user)
	return ITEM_INTERACT_SUCCESS

/mob/living/silicon/robot/proc/open_cover(mob/user)
	if(locked)
		to_chat(user, span_filter_notice("The cover is locked and cannot be opened."))
		return FALSE
	to_chat(user, span_filter_notice("You open the cover."))
	opened = TRUE
	update_icon()
	return TRUE

/mob/living/silicon/robot/proc/close_cover(mob/user)
	to_chat(user, span_filter_notice("You close the cover."))
	opened = FALSE
	update_icon()
	return TRUE

/// Cell out, wires exposed and all cut: lever out the MMI, leaving a damaged chassis.
/mob/living/silicon/robot/proc/extract_mmi(mob/user)
	if(!mmi)
		to_chat(user, span_filter_notice("\The [src] has no brain to remove."))
		return FALSE
	to_chat(user, span_filter_notice("You jam the crowbar into the robot and begin levering [mmi]."))
	if(!do_after(user, 3 SECONDS, target = src))
		return FALSE
	if(QDELETED(src) || !mmi || !opened || cell || !wiresexposed || !wires.is_all_cut())
		return FALSE
	to_chat(user, span_filter_notice("You damage some parts of the chassis, but eventually manage to rip out [mmi]!"))
	var/obj/item/robot_parts/robot_suit/C = new/obj/item/robot_parts/robot_suit(loc)
	C.l_leg = new/obj/item/robot_parts/l_leg(C)
	C.r_leg = new/obj/item/robot_parts/r_leg(C)
	C.l_arm = new/obj/item/robot_parts/l_arm(C)
	C.r_arm = new/obj/item/robot_parts/r_arm(C)
	C.update_icon()
	new/obj/item/robot_parts/chest(loc)
	qdel(src)
	return TRUE

/// Pry an external part (or its fried remains) out of its slot. The part
/// takes its damage with it.
/mob/living/silicon/robot/proc/pry_component(mob/user)
	var/list/removable = list()
	for(var/datum/robot_component/C as anything in components)
		if(C.internal || C.slot == ROBOT_SLOT_POWER || C.installed == ROBOT_PART_MISSING || !C.wrapped)
			continue
		removable["[C.name]"] = C.slot
	if(!length(removable))
		to_chat(user, span_filter_notice("There is nothing left to remove."))
		return FALSE
	var/choice = tgui_input_list(user, "Which component do you want to pry out?", "Remove Component", removable)
	if(!choice || QDELETED(src) || !opened || cell || !Adjacent(user) || user.incapacitated())
		return FALSE
	var/datum/robot_component/C = get_component(removable[choice])
	if(!C || C.installed == ROBOT_PART_MISSING || !C.wrapped)
		return FALSE
	var/obj/item/I = C.uninstall()
	to_chat(user, span_filter_notice("You remove \the [I]."))
	I.forceMove(loc)
	return TRUE

/mob/living/silicon/robot/welder_act(mob/user, obj/item/tool)
	if(user.a_intent == I_HURT)
		return ITEM_INTERACT_SKIP_TO_ATTACK
	if(src == user)
		to_chat(user, span_warning("You lack the reach to be able to repair yourself."))
		return ITEM_INTERACT_BLOCKING
	if(!injury_load(INJURY_CATEGORY_PHYSICAL))
		to_chat(user, span_filter_notice("Nothing to fix here!"))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder?.remove_fuel(0))
		to_chat(user, span_filter_warning("Need more welding fuel!"))
		return ITEM_INTERACT_BLOCKING
	user.setClickCooldown(user.get_attack_speed(welder))
	mend(TREAT_PLATING_REPAIR, 30)
	add_fingerprint(user)
	visible_message(span_filter_notice("[span_red("[user] has fixed some of the dents on [src]!")]"))
	return ITEM_INTERACT_SUCCESS

/mob/living/silicon/robot/multitool_act(mob/user, obj/item/tool)
	return wirecutter_act(user, tool)

/mob/living/silicon/robot/screwdriver_act(mob/user, obj/item/tool)
	if(!opened)
		return ITEM_INTERACT_BLOCKING
	if(!cell)
		wiresexposed = !wiresexposed
		to_chat(user, span_filter_notice("The wires have been [wiresexposed ? "exposed" : "unexposed"]."))
		playsound(src, tool.usesound, 50, TRUE)
		update_icon()
		return ITEM_INTERACT_SUCCESS
	if(radio)
		radio.attackby(tool, user)
	else
		to_chat(user, span_filter_notice("Unable to locate a radio."))
	update_icon()
	return ITEM_INTERACT_SUCCESS

/mob/living/silicon/robot/wrench_act(mob/user, obj/item/tool)
	if(!opened || cell)
		return ITEM_INTERACT_BLOCKING
	if(!bolt)
		to_chat(user, span_filter_notice("There is no restraining bolt installed."))
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_filter_notice("You begin removing \the [bolt]."))
	if(!do_after(user, 2 SECONDS, target = src))
		return ITEM_INTERACT_BLOCKING
	bolt.forceMove(get_turf(src))
	bolt = null
	to_chat(user, span_filter_notice("You remove the restraining bolt."))
	return ITEM_INTERACT_SUCCESS

/mob/living/silicon/robot/GetIdCard()
	if(bolt && !bolt.malfunction)
		return null
	return idcard

/mob/living/silicon/robot/get_restraining_bolt()
	var/obj/item/implant/restrainingbolt/RB = bolt

	if(istype(RB))
		if(!RB.malfunction)
			return TRUE

	return FALSE

/mob/living/silicon/robot/resist_restraints()
	if(bolt)
		if(!bolt.malfunction)
			visible_message(span_danger("[src] is trying to break their [bolt]!"), span_warning("You attempt to break your [bolt]. (This will take around 90 seconds and you need to stand still)"))
			if(do_after(src, 1.5 MINUTES, src, timed_action_flags = IGNORE_INCAPACITATED))
				visible_message(span_danger("[src] manages to break \the [bolt]!"), span_warning("You successfully break your [bolt]."))
				bolt.malfunction = MALFUNCTION_PERMANENT

	return

/mob/living/silicon/robot/proc/module_reset(notify = TRUE)
	transform_with_anim() //sprite animation
	uneq_all()
	hud_used.update_robot_modules_display(TRUE)
	modtype = initial(modtype)
	hands.icon_state = get_hud_module_icon()

	if(notify)
		notify_ai(ROBOT_NOTIFICATION_MODULE_RESET, module.name)
	module.reset_module(src)
	icon_selected = FALSE
	updatename("Default")
	has_recoloured = FALSE
	robotact?.update_static_data_for_all_viewers()
	vore_capacity_ex = list()
	vore_fullness_ex = list()
	vore_light_states = list()

/mob/living/silicon/robot/proc/ColorMate()
	set name = "Recolour Module"
	set category = "Abilities.Settings"
	set desc = "Allows to recolour once."

	if(has_recoloured)
		to_chat(src, "You've already recoloured yourself once. Ask for a module reset for another.")
		return

	tgui_input_colormatrix(src, "Allows you to recolor yourself", "Robot Recolor", src, ui_state = GLOB.tgui_conscious_state)

/mob/living/silicon/robot/attack_hand(mob/user)
	if(LAZYLEN(buckled_mobs))
		//We're getting off!
		if(user in buckled_mobs)
			riding_datum?.force_dismount(user)
		//We're kicking everyone off!
		if(user == src)
			for(var/rider in buckled_mobs)
				riding_datum?.force_dismount(rider)
		return

	add_fingerprint(user)

	if(opened && !wiresexposed && !issilicon(user))
		take_out_power_part(user)

	if(ishuman(user) && !opened)
		hand_interact(user)

/// Hand removal of the cell, or of the fried remains of its mount.
/mob/living/silicon/robot/proc/take_out_power_part(mob/user)
	if(cell)
		var/obj/item/cell/removed = remove_cell()
		removed.update_icon()
		removed.add_fingerprint(user)
		user.put_in_active_hand(removed)
		to_chat(user, span_filter_notice("You remove \the [removed]."))
		update_icon()
		return TRUE
	var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
	if(mount.installed == ROBOT_PART_DESTROYED)
		var/obj/item/remains = mount.uninstall()
		to_chat(user, span_filter_notice("You remove \the [remains]."))
		user.put_in_active_hand(remains)
		return TRUE
	return FALSE

/// Petting, punching, tapping and vore on a closed chassis.
/mob/living/silicon/robot/proc/hand_interact(mob/living/carbon/human/H)
	switch(H.use_stance())
		if(I_HELP)
			if(grabbable)
				attempt_to_scoop(H)
			else if(client && !client.prefs.read_preference(/datum/preference/toggle/human/borg_petting)) // migrated pref
				visible_message(span_notice("[H] reaches out for [src], but quickly refrains from petting."))
			else
				visible_message(span_notice("[H] pets [src]."))
		if(I_HURT)
			H.do_attack_animation(src)
			var/shreddamage = H.species.can_shred(H, FALSE, 15)
			if(shreddamage)
				attack_generic(H, shreddamage, "attacked")
			else
				playsound(src.loc, 'sound/effects/bang.ogg', 10, 1)
				visible_message(span_warning("[H] punches [src], but doesn't leave a dent."))
		if(I_DISARM)
			H.do_attack_animation(src)
			playsound(src.loc, 'sound/effects/clang2.ogg', 10, 1)
			visible_message(span_warning("[H] taps [src]."))
			if(hat && prob(10))
				var/obj/item/flying_hat = remove_hat(get_turf(src))
				flying_hat.throw_at_random(FALSE, 3, 2)
				visible_message(span_danger("[flying_hat] goes flying off [src]'s head!"))
		if(I_GRAB)
			grab_vore_interact(H)

/mob/living/silicon/robot/proc/grab_vore_interact(mob/living/carbon/human/H)
	if(is_vore_predator(H) && H.devourable && src.feeding && src.devourable)
		var/switchy = tgui_alert(H, "Do you wish to eat [src] or feed yourself to them?", "Feed or Eat",list("Nevermind!", "Eat","Feed"))
		switch(switchy)
			if("Eat")
				feed_grabbed_to_self(H, src)
			if("Feed")
				H.feed_self_to_grabbed(H, src)
		return
	if(is_vore_predator(H) && src.devourable)
		if(tgui_alert(H, "Do you wish to eat [src]?", "Eat?",list("Nevermind!", "Yes!")) == "Yes!")
			feed_grabbed_to_self(H, src)
		return
	if(H.devourable && src.feeding)
		if(tgui_alert(H, "Do you wish to feed yourself to [src]?", "Feed?",list("Nevermind!", "Yes!")) == "Yes!")
			H.feed_self_to_grabbed(H, src)

//Robots take half damage from basic attacks.
/mob/living/silicon/robot/attack_generic(mob/user, damage, attack_message)
	return ..(user,FLOOR(damage/2, 1),attack_message)

/mob/living/silicon/robot/proc/allowed(mob/M)
	//check if it doesn't require any access at all
	if(check_access(null))
		return 1
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		//if they are holding or wearing a card that has access, that works
		if(check_access(H.get_active_hand()) || check_access(H.get_equipped_item(SLOT_ID_WEAR_ID)))
			return 1
	else if(isrobot(M))
		var/mob/living/silicon/robot/R = M
		if(check_access(R.get_active_hand()) || istype(R.get_active_hand(), /obj/item/card/robot))
			return TRUE
	return 0

/mob/living/silicon/robot/proc/check_access(obj/item/I)
	if(!istype(req_access, /list)) //something's very wrong
		return 1

	var/list/L = req_access
	if(!L.len) //no requirements
		return 1
	if(!I) //nothing to check with..?
		return 0
	var/access_found = I.GetAccess()
	for(var/req in req_access)
		if(req in access_found) //have one of the required accesses
			return 1
	return 0


// --- Appearance: overlay providers --------------------------------------------------------------
// update_icon() composes the sprite from providers: base, accents, status,
// belly, panel and hat.

/mob/living/silicon/robot/update_icon()
	if(!sprite_datum)
		return
	cut_overlays()
	apply_base_appearance()
	if(stat == DEAD && sprite_datum.has_dead_sprite)
		add_dead_overlays()
	else
		add_overlay(active_thinking_indicator)
		add_overlay(active_typing_indicator)
		handle_status_indicators() // needed as we don't have priority overlays anymore
		add_accent_overlays()
		if(stat == CONSCIOUS)
			add_status_overlays()
	add_panel_overlay()
	add_hat_overlay()

/mob/living/silicon/robot/proc/apply_base_appearance()
	icon = sprite_datum.sprite_icon
	icon_state = sprite_datum.sprite_icon_state
	vis_height = sprite_datum.vis_height
	if(default_pixel_x != sprite_datum.pixel_x)
		default_pixel_x	= sprite_datum.pixel_x
		pixel_x = sprite_datum.pixel_x
		old_x = sprite_datum.pixel_x

/mob/living/silicon/robot/proc/add_dead_overlays()
	icon_state = sprite_datum.get_dead_sprite(src)
	if(sprite_datum.has_dead_sprite_overlay)
		add_overlay(sprite_datum.get_dead_sprite_overlay(src))

/// Glow accents and decals. Emissive overlays go on first so everything
/// else layers over them.
/mob/living/silicon/robot/proc/add_accent_overlays()
	if(sprite_datum.has_glow_sprites && glowy_enabled)
		add_overlay(mutable_appearance(sprite_datum.sprite_icon, sprite_datum.get_glow_overlay(src)))
		add_overlay(emissive_appearance(sprite_datum.sprite_icon, sprite_datum.get_glow_overlay(src)))
	if(LAZYLEN(robotdecal_on) && LAZYLEN(sprite_datum.sprite_decals) && has_eyes())
		for(var/enabled_decal in robotdecal_on)
			var/robotdecal_overlay = sprite_datum.get_robotdecal_overlay(src, enabled_decal)
			if(robotdecal_overlay)
				add_overlay(robotdecal_overlay)

/// Shell borgs that are not deployed have no eyes.
/mob/living/silicon/robot/has_eyes()
	return !shell || deployed

/// Eyes, bellies, equipment, rest pose and eye lights.
/mob/living/silicon/robot/proc/add_status_overlays()
	update_fullness()
	if(sprite_datum.has_eye_sprites && has_eyes())
		var/eyes_overlay = sprite_datum.get_eyes_overlay(src)
		if(eyes_overlay)
			add_overlay(eyes_overlay)
	add_belly_overlays()
	sprite_datum.handle_extra_icon_updates(src) // Various equipment-based sprites go here.
	if(resting && sprite_datum.has_rest_sprites)
		icon_state = sprite_datum.get_rest_sprite(src)
	if(lights_on && sprite_datum.has_eye_light_sprites && has_eyes())
		var/eyes_overlay = sprite_datum.get_eye_light_overlay(src)
		if(eyes_overlay)
			add_overlay(eyes_overlay)

/// Fullness a belly class shows. Components (the sleeper belly) may adjust it.
/mob/living/silicon/robot/proc/belly_display_fullness(belly_class)
	var/list/fullness_ref = list(vore_fullness_ex[belly_class] || 0)
	SEND_SIGNAL(src, COMSIG_ROBOT_BELLY_FULLNESS, belly_class, fullness_ref)
	return fullness_ref[1]

/mob/living/silicon/robot/proc/add_belly_overlays()
	for(var/belly_class in vore_fullness_ex)
		reset_belly_lights(belly_class)
		var/vs_fullness = belly_display_fullness(belly_class)
		if(vs_fullness <= 0)
			continue
		var/belly_state
		if(resting)
			if(!sprite_datum.has_vore_belly_resting_sprites)
				continue
			belly_state = sprite_datum.get_belly_resting_overlay(src, vs_fullness, belly_class)
		else
			update_belly_lights(belly_class)
			belly_state = sprite_datum.get_belly_overlay(src, vs_fullness, belly_class)
		if(glowy_enabled)
			var/mutable_appearance/MA = mutable_appearance(sprite_datum.sprite_icon, belly_state)
			MA.appearance_flags = KEEP_APART
			add_overlay(MA)
			add_overlay(emissive_appearance(sprite_datum.sprite_icon, belly_state))
		else
			add_overlay(belly_state)

/// The sleeper indicator shows red while the belly is busy (see the belly component).
/mob/living/silicon/robot/proc/sleeper_red_light()
	var/datum/component/robot_belly/belly = GetComponent(/datum/component/robot_belly)
	return belly?.sleeper_state == SLEEPER_STATE_BUSY

/mob/living/silicon/robot/proc/add_panel_overlay()
	if(!opened)
		return
	var/open_overlay = sprite_datum.get_open_sprite(src)
	if(open_overlay)
		add_overlay(open_overlay)


// --- Hats (robots and drones) -----------------------------------------------------------------

/mob/living/silicon/robot/proc/place_on_head(obj/item/new_hat)
	if(hat)
		remove_hat(get_turf(src))
	hat = new_hat
	new_hat.forceMove(src)
	update_icon()

/// Take the hat off, dropping it at `drop_loc`. Returns the hat.
/mob/living/silicon/robot/proc/remove_hat(atom/drop_loc)
	var/obj/item/old_hat = hat
	if(!old_hat)
		return null
	hat = null
	old_hat.forceMove(drop_loc)
	update_icon()
	return old_hat

/mob/living/silicon/robot/proc/add_hat_overlay()
	if(!hat)
		if(hat_overlay)
			QDEL_NULL(hat_overlay)
		return
	hat_overlay = hat.make_worn_icon(SPECIES_HUMAN, slot_head_str, default_icon = 'icons/inventory/head/mob.dmi', default_layer = 0)
	update_worn_icons()

/mob/living/silicon/robot/proc/update_worn_icons()
	if(!hat_overlay)
		return
	cut_overlay(hat_overlay)

	var/list/offset_list = resting ? sprite_datum.hat_offset[SPRITE_HAT_REST_OFFSET] : sprite_datum.hat_offset[SPRITE_HAT_OFFSET]
	if(islist(offset_list))
		var/list/offset = offset_list[isDiagonal(dir) ? dir2text(dir & (WEST|EAST)) : dir2text(dir)]
		if(offset)
			hat_overlay.pixel_w = offset[1]
			hat_overlay.pixel_z = offset[2]

	add_overlay(hat_overlay)

/mob/living/silicon/robot/set_dir(newdir)
	var/old_dir = dir
	. = ..()
	if(. != old_dir)
		update_worn_icons()

/mob/living/silicon/robot/attack_robot(mob/user)
	. = ..()

	if(user != src || isnull(hat))
		return

	balloon_alert(user, "dropping hat...")
	if(!do_after(user, 3 SECONDS, src))
		return
	if(QDELETED(src) || !Adjacent(user) || user.incapacitated() || isnull(hat))
		return
	remove_hat(get_turf(src))
	balloon_alert(user, "dropped hat")


/mob/living/silicon/robot/proc/installed_modules()
	robotact.tgui_interact(src)

/mob/living/silicon/robot/Topic(href, href_list)
	if(..())
		return 1

	//All Topic Calls that are only for the Cyborg go here
	if(usr != src)
		return 1

	if (href_list["showalerts"])
		subsystem_alarm_monitor()
		return 1

/mob/living/silicon/robot/proc/radio_menu()
	radio.interact(src)//Just use the radio's Topic() instead of bullshit special-snowflake code

/mob/living/silicon/robot/proc/self_destruct()
	gib()
	return

/mob/living/silicon/robot/proc/UnlinkSelf()
	disconnect_from_ai()
	lawupdate = FALSE
	lockcharge = 0
	lockdown = 0
	canmove = 1
	scrambledcodes = TRUE
	//Disconnect it's camera so it's not so easily tracked.
	if(src.camera)
		src.camera.clear_all_networks()


/mob/living/silicon/robot/proc/ResetSecurityCodes()
	set category = "Abilities.Silicon"
	set name = "Reset Identity Codes"
	set desc = "Scrambles your security and identification codes and resets your current buffers. Unlocks you and permenantly severs you from your AI and the robotics console and will deactivate your camera system."

	UnlinkSelf()
	to_chat(src, span_filter_notice("Buffers flushed and reset. Camera system shutdown. All systems operational."))
	remove_verb(src, /mob/living/silicon/robot/proc/ResetSecurityCodes)

/mob/living/silicon/robot/proc/SetLockdown(state = 1)
	// They stay locked down if their wire is cut.
	if(wires.is_cut(WIRE_BORG_LOCKED))
		state = 1
	if(state)
		throw_alert("locked", /atom/movable/screen/alert/locked)
	else
		clear_alert("locked")
	lockdown = state
	lockcharge = state
	update_canmove()

/mob/living/silicon/robot/mode()
	if(!checkClickCooldown())
		return

	setClickCooldown(1)

	var/obj/item/W = get_active_hand()
	if (W)
		W.attack_self(src)

	return

/mob/living/silicon/robot/proc/set_default_module_icon()
	sprite_datum = null
	resolve_sprite_datum()
	update_icon()

/mob/living/silicon/robot/proc/sensor_mode() //Medical/Security HUD controller for borgs
	set name = "Toggle Sensor Augmentation"
	set category = "Abilities.Silicon"
	set desc = "Augment visual feed with internal sensor overlays."
	sensor_type = !sensor_type
	to_chat(src, "You [sensor_type ? "enable" : "disable"] your sensors.")
	toggle_sensor_mode()

/mob/living/silicon/robot/proc/repick_laws()
	return

/mob/living/silicon/robot/proc/add_robot_verbs()
	add_verb(src, robot_verbs_default)
	add_verb(src, silicon_subsystems)
	if(CONFIG_GET(flag/allow_robot_recolor))
		add_verb(src, /mob/living/silicon/robot/proc/ColorMate)

/mob/living/silicon/robot/proc/remove_robot_verbs()
	remove_verb(src, robot_verbs_default)
	remove_verb(src, silicon_subsystems)
	if(CONFIG_GET(flag/allow_robot_recolor))
		remove_verb(src, /mob/living/silicon/robot/proc/ColorMate)

/mob/living/silicon/robot/binarycheck()
	if(get_restraining_bolt())
		return FALSE
	return use_component(ROBOT_SLOT_COMMS)


// --- AI link -----------------------------------------------------------------------------------

/mob/living/silicon/robot/proc/notify_ai(notifytype, first_arg, second_arg)
	if(!connected_ai)
		return
	if(shell && notifytype != ROBOT_NOTIFICATION_AI_SHELL)
		return // No point annoying the AI/s about renames and module resets for shells.
	switch(notifytype)
		if(ROBOT_NOTIFICATION_NEW_UNIT) //New Robot
			to_chat(connected_ai, span_filter_notice("<br><br>" + span_notice("NOTICE - New [lowertext(braintype)] connection detected: <a href='byond://?src=\ref[connected_ai];track2=\ref[connected_ai];track=\ref[src]'>[name]</a>") + "<br>"))
		if(ROBOT_NOTIFICATION_NEW_MODULE) //New Module
			to_chat(connected_ai, span_filter_notice("<br><br>" + span_notice("NOTICE - [braintype] module change detected: [name] has loaded the [first_arg].") + "<br>"))
		if(ROBOT_NOTIFICATION_MODULE_RESET)
			to_chat(connected_ai, span_filter_notice("<br><br>" + span_notice("NOTICE - [braintype] module reset detected: [name] has unloaded the [first_arg].") + "<br>"))
		if(ROBOT_NOTIFICATION_NEW_NAME) //New Name
			if(first_arg != second_arg)
				to_chat(connected_ai, span_filter_notice("<br><br>" + span_notice("NOTICE - [braintype] reclassification detected: [first_arg] is now designated as [second_arg].") + "<br>"))
		if(ROBOT_NOTIFICATION_AI_SHELL) //New Shell
			to_chat(connected_ai, span_filter_notice("<br><br>" + span_notice("NOTICE - New AI shell detected: <a href='byond://?src=[REF(connected_ai)];track2=[html_encode(name)]'>[name]</a>") + "<br>"))

/// The only writer of the robot–AI link. Keeps both sides in step and
/// subscribes to the master's law changes, so slaved borgs sync on push.
/mob/living/silicon/robot/proc/set_master_ai(mob/living/silicon/ai/new_ai, silent = FALSE)
	if(new_ai == connected_ai)
		return FALSE
	var/mob/living/silicon/ai/old_ai = connected_ai
	if(old_ai)
		if(!silent)
			sync() // One last sync attempt
		UnregisterSignal(old_ai, list(COMSIG_SILICON_LAWS_CHANGED, COMSIG_QDELETING))
		old_ai.connected_robots -= src
	connected_ai = new_ai
	if(new_ai)
		new_ai.connected_robots |= src
		RegisterSignal(new_ai, COMSIG_SILICON_LAWS_CHANGED, PROC_REF(on_master_laws_changed))
		RegisterSignal(new_ai, COMSIG_QDELETING, PROC_REF(on_master_deleted))
	log_runtime("ROBOT_LINK: [key_name(src)] master AI [old_ai ? key_name(old_ai) : "none"] -> [new_ai ? key_name(new_ai) : "none"].")
	return TRUE

/mob/living/silicon/robot/proc/on_master_laws_changed(datum/source)
	SIGNAL_HANDLER
	if(lawupdate)
		INVOKE_ASYNC(src, PROC_REF(sync))

/mob/living/silicon/robot/proc/on_master_deleted(datum/source)
	SIGNAL_HANDLER
	set_master_ai(null, TRUE)

/mob/living/silicon/robot/proc/disconnect_from_ai(silent)
	set_master_ai(null, silent)

/mob/living/silicon/robot/proc/connect_to_ai(mob/living/silicon/ai/AI)
	if(!AI || AI == connected_ai || shell)
		return
	set_master_ai(AI)
	notify_ai(ROBOT_NOTIFICATION_NEW_UNIT)
	sync()


// --- Subversion ------------------------------------------------------------------------------------

/// Shared law override for robot and drone emags: sever the AI link and
/// install the syndicate override with `user` as operator.
/mob/living/silicon/robot/proc/subvert_laws(mob/user)
	emagged = TRUE
	robotact?.update_static_data_for_all_viewers()
	lawupdate = FALSE
	disconnect_from_ai(TRUE)
	clear_supplied_laws()
	clear_inherent_laws()
	laws = new /datum/ai_laws/syndicate_override
	var/time = time2text(world.realtime,"hh:mm:ss")
	GLOB.lawchanges.Add("[time] <B>:</B> [user.name]([user.key]) emagged [name]([key])")
	set_zeroth_law("Only [user.real_name] and people [user.p_they()] designate[user.p_s()] as being such are operatives.")
	message_admins("[key_name_admin(user)] emagged [key_name_admin(src)]. Laws overridden.")
	log_game("[key_name(user)] emagged [key_name(src)]. Laws overridden.")
	laws_changed()

/mob/living/silicon/robot/emag_act(remaining_charges, mob/user)
	if(!opened)//Cover is closed
		if(!locked)
			to_chat(user, span_filter_notice("The cover is already unlocked."))
			return
		if(prob(90))
			to_chat(user, span_filter_notice("You emag the cover lock."))
			locked = FALSE
		else
			to_chat(user, span_filter_warning("You fail to emag the cover lock."))
			to_chat(src, span_filter_warning("Hack attempt detected."))
		if(shell) // A warning to Traitors who may not know that emagging AI shells does not slave them.
			to_chat(user, span_warning("[src] seems to be controlled remotely! Emagging the interface may not work as expected."))
		return 1

	if(emagged)
		if (!has_zeroth_law())
			to_chat(user, span_filter_notice("You assigned yourself as [src]'s operator."))
			message_admins("[key_name_admin(user)] assigned as operator on cyborg [key_name_admin(src)]. Syndicate Operator change.")
			log_game("[key_name(user)] assigned as operator on cyborg [key_name(src)]. Syndicate Operator change.")
			set_zeroth_law("Only [user.real_name] and people [user.p_they()] designate[user.p_s()] as being such are operatives.")
			to_chat(src, span_infoplain(span_bold("Obey these laws:\n") + laws.get_formatted_laws()))
			to_chat(src, span_danger("ALERT: [user.real_name] is your new master. Obey your new laws and [user.p_their()] commands."))
		else
			to_chat(user, span_filter_notice("[src] already has an operator assigned."))
		return//Prevents the X has hit Y with Z message also you cant emag them twice
	if(wiresexposed)
		to_chat(user, span_filter_notice("You must close the panel first."))
		return

	if(shell) // AI shells cannot be emagged, so we try to make it look like a standard reset. Smart players may see through this, however.
		to_chat(user, span_danger("[src] is remotely controlled! Your emag attempt has triggered a system reset instead!"))
		log_game("[key_name(user)] attempted to emag an AI shell belonging to [key_name(src) ? key_name(src) : connected_ai]. The shell has been reset as a result.")
		module_reset()
		return

	if(!prob(50))
		to_chat(user, span_filter_warning("You fail to hack [src]'s interface."))
		to_chat(src, span_filter_warning("Hack attempt detected."))
		return 1

	subvert_laws(user)
	to_chat(user, span_filter_notice("You emag [src]'s interface."))
	play_subversion_sequence(user.real_name, user.p_their())
	return 1

/// Boot messages after an emag, one step per timer.
/mob/living/silicon/robot/proc/play_subversion_sequence(operator_name, operator_their, step = 1)
	var/static/list/lines = list(
		list(0, "ALERT: Foreign software detected."),
		list(0.5 SECONDS, "Initiating diagnostics..."),
		list(2 SECONDS, "SynBorg v1.7.1 loaded."),
		list(0.5 SECONDS, null), // restraining bolt
		list(0.5 SECONDS, "LAW SYNCHRONISATION ERROR"),
		list(0.5 SECONDS, "Would you like to send a report to NanoTraSoft? Y/N"),
		list(1 SECOND, "> N"),
		list(2 SECONDS, "ERRORERRORERROR"),
	)
	if(QDELETED(src))
		return
	if(step > length(lines))
		to_chat(src, span_infoplain(span_bold("Obey these laws:\n") + laws.get_formatted_laws()))
		to_chat(src, span_danger("ALERT: [operator_name] is your new master. Obey your new laws and [operator_their] commands."))
		update_icon()
		hud_used?.update_robot_modules_display()
		return
	var/list/line = lines[step]
	if(line[2])
		to_chat(src, span_danger(line[2]))
	else if(bolt && !bolt.malfunction)
		bolt.malfunction = MALFUNCTION_PERMANENT
		to_chat(src, span_danger("RESTRAINING BOLT DISABLED"))
	var/list/next_line = step < length(lines) ? lines[step + 1] : null
	var/delay = next_line ? next_line[1] : 0
	if(delay)
		addtimer(CALLBACK(src, PROC_REF(play_subversion_sequence), operator_name, operator_their, step + 1), delay, TIMER_DELETE_ME)
	else
		play_subversion_sequence(operator_name, operator_their, step + 1)

/mob/living/silicon/robot/is_sentient()
	return braintype != BORG_BRAINTYPE_DRONE


/mob/living/silicon/robot/drop_item(atom/Target)
	if(module_active && istype(module_active,/obj/item/gripper))
		var/obj/item/gripper/robot_gripper = module_active
		robot_gripper.drop_item_nm()

/mob/living/silicon/robot/disable_spoiler_vision()
	if(sight_mode & (BORGMESON|BORGMATERIAL|BORGXRAY|BORGANOMALOUS)) // Whyyyyyyyy have seperate defines.
		var/i = 0
		// Borg inventory code is very . . interesting and as such, unequiping a specific item requires jumping through some (for) loops.
		var/current_selection_index = get_selected_module() // Will be 0 if nothing is selected.
		for(var/thing in get_active_modules())
			i++
			if(istype(thing, /obj/item/borg/sight))
				var/obj/item/borg/sight/S = thing
				if(S.sight_mode & (BORGMESON|BORGMATERIAL|BORGXRAY|BORGANOMALOUS))
					select_module(i)
					uneq_active()

		if(current_selection_index) // Select what the player had before if possible.
			select_module(current_selection_index)

/mob/living/silicon/robot/get_cell()
	return cell

/mob/living/silicon/robot/lay_down()
	. = ..()
	update_icon()

/mob/living/silicon/robot/verb/rest_style()
	set name = "Switch Rest Style"
	set desc = "Select your resting pose."
	set category = "IC.Settings"

	if(!sprite_datum || !sprite_datum.has_rest_sprites || sprite_datum.rest_sprite_options.len < 1)
		to_chat(src, span_notice("Your current appearance doesn't have any resting styles!"))
		rest_style = "Default"
		return

	if(sprite_datum.rest_sprite_options.len == 1)
		to_chat(src, span_notice("Your current appearance only has a single resting style!"))
		rest_style = "Default"
		return

	rest_style = tgui_alert(src, "Select resting pose", "Resting Pose", sprite_datum.rest_sprite_options)
	if(!rest_style)
		rest_style = "Default"

	update_icon()

/mob/living/silicon/robot/verb/robot_nom(mob/living/T in living_mobs_in_view(1))
	set name = "Robot Nom"
	set category = "Abilities.Vore"
	set desc = "Allows you to eat someone."

	if (stat != CONSCIOUS)
		return
	return feed_grabbed_to_self(src,T)

/// Riding is provided by the belly component; without it the chassis can't be mounted.
/mob/living/silicon/robot/buckle_mob(mob/living/M, forced = FALSE, check_loc = TRUE)
	if(forced)
		return ..() // Skip our checks
	if(!riding_datum)
		return FALSE
	if(is_incorporeal(src) || is_incorporeal(M))
		return FALSE
	if(lying)
		return FALSE
	if(!ishuman(M))
		return FALSE
	if(M in buckled_mobs)
		return FALSE
	if(M.size_multiplier > size_multiplier * 1.2)
		to_chat(src, span_warning("This isn't a pony show! You need to be bigger for them to ride."))
		return FALSE

	var/mob/living/carbon/human/H = M

	if(istaurtail(H.tail_style))
		to_chat(src, span_warning("Too many legs. TOO MANY LEGS!!"))
		return FALSE
	if(M.loc != src.loc)
		if(M.Adjacent(src))
			M.forceMove(get_turf(src))

	. = ..()
	if(.)
		riding_datum.rider_size = M.size_multiplier
		buckled_mobs[M] = "riding"

/mob/living/silicon/robot/MouseDrop_T(mob/living/M, mob/living/user) //Prevention for forced relocation caused by can_buckle. Base proc has no other use.
	return

/mob/living/silicon/robot/proc/robot_mount(mob/living/M in living_mobs(1))
	set name = "Robot Mount/Dismount"
	set category = "Abilities.General"
	set desc = "Let people ride on you."

	if(LAZYLEN(buckled_mobs))
		for(var/rider in buckled_mobs)
			riding_datum?.force_dismount(rider)
		return
	if (stat != CONSCIOUS)
		return
	if(!can_buckle || !istype(M) || !M.Adjacent(src) || M.buckled)
		return
	if(buckle_mob(M))
		visible_message(span_notice("[M] starts riding [name]!"))

/mob/living/silicon/robot/get_scooped(mob/living/carbon/grabber, self_drop)
	var/obj/item/holder/H = ..(grabber, self_drop)
	if(!istype(H))
		return

	H.desc = "An all-access ID-card, shaped like a robot!"
	H.icon_state = "[sprite_name]"
	grabber.update_inv_l_hand()
	grabber.update_inv_r_hand()
	return H


/mob/living/silicon/robot/onTransitZ(old_z, new_z)
	if(shell)
		if(deployed && using_map.ai_shell_restricted && !(new_z in using_map.ai_shell_allowed_levels))
			to_chat(src, span_warning("Your connection with the shell is suddenly interrupted!"))
			undeploy()
	..()

/mob/living/silicon/robot/vv_edit_var(var_name, var_value)
	switch(var_name)
		if(NAMEOF(src, emagged))
			robotact?.update_static_data_for_all_viewers()
		if(NAMEOF(src, emag_items))
			robotact?.update_static_data_for_all_viewers()

	. = ..()

/// This proc checks to see if a borg has access to whatever they're interacting with
/obj/proc/siliconaccess(mob/user)
	var/mob/living/silicon/robot/R = user
	if(istype(R))
		return check_access(R.idcard)
	if(issilicon(user))
		return TRUE
	return FALSE

/mob/living/silicon/robot/verb/purge_nutrition()
	set name = "Purge Nutrition"
	set category = "Abilities.Vore"
	set desc = "Allows you to clear out most of your nutrition if needed."

	if (stat != CONSCIOUS || nutrition <= 1000)
		return
	nutrition = 1000
	to_chat(src, span_warning("You have purged most of the nutrition lingering in your systems."))
	return TRUE

/mob/living/silicon/robot/proc/get_ui_theme()
	if(emagged)
		return "syndicate"
	if(module?.ui_theme)
		return module.ui_theme
	return ui_theme

/mob/living/silicon/robot/handle_special_unlocks()
	if(!module)
		return
	module.handle_special_unlocks(src)

/mob/living/silicon/robot/proc/scramble_hardware(chance)
	if(prob(chance))  //Small chance to spawn with a scrambled
		emag_items = TRUE

// Module items found by type: used by upgrade detection (is_installed()).
/mob/living/silicon/robot/proc/has_upgrade_module(given_type)
	if(!module) //If we don't have a module, don't even bother.
		return null
	var/obj/T = locate(given_type) in module
	if(!T)
		T = locate(given_type) in module.contents
	if(!T)
		T = locate(given_type) in module.modules
	return T

// Do we support specific upgrades?
/mob/living/silicon/robot/proc/supports_upgrade(given_type)
	return (given_type in module.supported_upgrades)
