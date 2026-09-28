/// Interaction entries: a crowbar or welder used on the chassis (crowbar_act()/welder_act()).
#define ROBOT_ENTRY_CROWBAR "robot_crowbar"
#define ROBOT_ENTRY_WELDER "robot_welder"

/mob/living/silicon/robot
	/// Traitor HUD images shown to a syndicate borg's client (see build_traitor_hud()).
	var/list/traitor_hud_images
	/// The client those images were added to.
	var/client/traitor_hud_client
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
	var/list/robotdecal_on	// Lazy.
	var/glowy_enabled = FALSE

	can_be_antagged = TRUE

//Icon stuff

	var/datum/robot_sprite/sprite_datum 				// Sprite datum, holding all our sprite data. Resolved in Initialize.
	var/icon_selected = FALSE								// If icon selection has been completed yet
	var/list/sprite_extra_customization	// Lazy.
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
	// ALLOW(instance_list): mob: 15 mobs at boot; per-instance state, see audit
	var/list/req_access = list(ACCESS_ROBOTICS) // Interned per subtype in Initialize().
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

	/// Abilities (code/datums/abilities/ability.dm) every robot grants itself on
	/// Initialize() and revokes in Destroy() - never gated by death, same as
	/// the `verb/` declarations they replace weren't.
	var/static/list/robot_granted_abilities = list(
		ABILITY_ID_ROBOT_TOGGLE_LIGHTS,
		ABILITY_ID_ROBOT_PICK_NAME,
		ABILITY_ID_ROBOT_CUSTOMIZE_APPEARANCE,
		ABILITY_ID_ROBOT_TOGGLE_GLOWY_STOMACH,
		ABILITY_ID_ROBOT_SPARK_PLUG,
		ABILITY_ID_ROBOT_TOGGLE_GRABBABILITY,
		ABILITY_ID_ROBOT_PURGE_NUTRITION,
		ABILITY_ID_ROBOT_TOGGLE_DECALS,
		ABILITY_ID_ROBOT_NOM,
	)

	var/static/list/robot_verbs_default = list(
		/mob/living/silicon/robot/proc/robot_checklaws,
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

	var/list/vore_light_states	//Robot exclusive. Lazy.
	vore_capacity_ex = list()
	vore_fullness_ex = list()
	vore_icon_bellies = list()

// --- Lifecycle ------------------------------------------------------------------------------

/mob/living/silicon/robot/Initialize(mapload, is_decoy)
	if(islist(req_access))
		req_access = shared_type_list(type, "req_access", req_access)
	spark_system = new /datum/effect/effect/system/spark_spread() // ALLOW(decl): configured before parent init
	spark_system.set_up(5, 0, src)
	spark_system.attach(src)
	om_hook(src, /datum/om/event/living_shield_injury, src, PROC_REF(absorb_injury_with_shield))

	add_language(LANGUAGE_ROBOT_TALK, 1)
	add_language(LANGUAGE_GALCOM, 1)
	add_language(LANGUAGE_EAL, 1)

	set_wires(new /datum/wires/robot(src))

	robot_modules_background = new() // ALLOW(decl): screen object made in nullspace, configured before parent init
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

	// This mob (not a component) is the source: every robot has these
	// (code/modules/mob/living/silicon/robot/robot_abilities.dm), revoked in
	// Destroy(). Unlike robot_verbs_default below, these were never gated by
	// death (they were plain `verb/` declarations, not in that list), so
	// they're granted once here rather than in add_robot_verbs()/remove_robot_verbs().
	for(var/ability_id in robot_granted_abilities)
		grant_ability(ability_id, src)

	. = ..()

	add_robot_verbs()
	setup_hud_images()
	resolve_sprite_datum()
	recompute_power_demand()
	update_senses()

	add_hose_connector(/datum/hose_connector/input/borg)
	add_hose_connector(/datum/hose_connector/output/borg)

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

/// A borg has no nutrition, body temperature or radiation dose to reset (audit P2-D11);
/// its parts and cell were rebuilt above.
/mob/living/silicon/robot/rejuvenate_physiology()
	return

//If there's an MMI in the robot, have it ejected when the mob goes away. --NEO
//Improved /N
// the MMI receives the borg's mind on the turf; shells revert; parts and hat drop.
/mob/living/silicon/robot/on_destroy(force)
	for(var/ability_id in robot_granted_abilities)
		revoke_ability(ability_id, src)
	if(mmi)//Safety for when a cyborg gets dust()ed. Or there is no MMI inside.
		if(mind)
			// The MMI lands on the borg's turf (get_turf() sees through any container). The
			// mind only follows it there: it must never stay in an MMI inside this deleting mob.
			var/turf/T = get_turf(src)
			var/datum/mind_host/host = get_mind_host(mmi)
			if(T)
				mmi.forceMove(T)
			if(T && host)
				var/mob/living/carbon/brain/view = host.receive_mind(mind, "cyborg [src] destroyed")
				view.remove_language(LANGUAGE_ROBOT_TALK)
				mmi = null
			else
				if(!T)
					log_game("MIND: cyborg [key_name(src)] was destroyed with no location; its MMI is lost and the mind is ghosted without re-entry.")
					QDEL_NULL(mmi) // ALLOW(decl): the MMI is lost with the mind when there is no turf
				else if(!shell) // Shells don't have brainmobs in their MMIs.
					log_game("MIND: cyborg [key_name(src)] was destroyed but its MMI [mmi] has no mind host; ghosting.")
					to_chat(src, span_danger("Oops! Something went very wrong, your MMI was unable to receive your mind. You have been ghosted. Please make a bug report so we can fix this bug."))
				mmi = null
				ghostize(FALSE)
		else
			QDEL_NULL(mmi) // ALLOW(decl): mindless MMI deleted here on purpose, beside the mind-transfer branch
	clear_traitor_hud()
	disconnect_from_ai(TRUE)
	if(shell)
		if(deployed)
			undeploy()
		revert_shell() // To get it out of the GLOB list.
	set_cell(null)
	..()

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
	var/obj/item/cell/old_cell = cell
	if(old_cell)
		om_unhook(old_cell, list(/datum/om/event/before/atom_pre_emp_act, /datum/om/event/qdeleting), src)
	cell = new_cell
	// A5: a replacement (not a removal: remove_cell() uninstalls first and keeps the cell) takes
	// the old cell out of the mount and deletes it, instead of orphaning it in contents (a
	// suit-built borg's default cell, overwritten by the chest's).
	if(old_cell && new_cell)
		var/datum/robot_component/old_mount = get_component(ROBOT_SLOT_POWER)
		if(old_mount?.wrapped == old_cell)
			old_mount.uninstall()
		if(old_cell.loc == src)
			qdel(old_cell)
	if(new_cell)
		if(new_cell.loc != src)
			new_cell.forceMove(src)
		om_hook(new_cell, /datum/om/event/before/atom_pre_emp_act, src, PROC_REF(shield_cell_from_emp))
		om_hook(new_cell, /datum/om/event/qdeleting, src, PROC_REF(on_cell_deleted))
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

/mob/living/silicon/robot/proc/shield_cell_from_emp(datum/source, datum/om/event/before/atom_pre_emp_act/event)
	EVENT_HANDLER
	return EMP_PROTECT_SELF

/mob/living/silicon/robot/proc/on_cell_deleted(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
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
	var/sees = stat != DEAD && !has_status(EFFECT_PARALYZED) && !has_status(EFFECT_BLINDED) && !(sdisabilities & BLIND) && is_component_functioning(ROBOT_SLOT_CAMERA)
	blinded = !sees
	if(stat == DEAD)
		return
	if(blinded)
		overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
	else
		clear_fullscreen("blind")
		// A worn camera sees through noise.
		set_fullscreen(component_function(ROBOT_SLOT_CAMERA) < 0.5 || is_nearsighted(), "impaired", /atom/movable/screen/fullscreen/impaired, 1)

// --- Lights -----------------------------------------------------------------------------------

/mob/living/silicon/robot/proc/set_lights(new_state)
	if(lights_on == new_state)
		return
	lights_on = new_state
	refresh_glow()
	recompute_power_demand()
	update_icon()

/datum/om/stage/life/light/silicon/robot
	of = /mob/living/silicon/robot

/datum/om/stage/life/light/silicon/robot/perform(mob/living/silicon/robot/self, datum/om/frame/life/ctx)
	if(self.lights_on)
		self.set_light(self.integrated_light_power, 1, self.robot_light_col)
		return TRUE
	return ..()

// --- Countdowns ------------------------------------------------------------------------------

/mob/living/silicon/robot/proc/start_killswitch(delay = ROBOT_KILLSWITCH_DELAY)
	if(killswitch)
		return FALSE
	killswitch = om_after(src, delay, PROC_REF(fire_killswitch))
	log_game("ROBOT: killswitch armed on [key_name(src)] ([delay / (1 SECOND)]s).")
	return TRUE

/mob/living/silicon/robot/proc/cancel_killswitch()
	if(!killswitch)
		return FALSE
	om_cancel_timer(src, killswitch)
	killswitch = null
	return TRUE

/mob/living/silicon/robot/proc/fire_killswitch()
	killswitch = null
	if(stat == DEAD)
		return
	to_chat(src, span_danger("Killswitch Activated"))
	log_game("ROBOT: killswitch fired on [key_name(src)].")
	om_after(src, 0.5 SECONDS, TYPE_PROC_REF(/mob, gib))

/// Lock the modules. Equipment drops once; activation is refused until the lock times out.
/mob/living/silicon/robot/proc/start_weapon_lock(duration = ROBOT_WEAPON_LOCK_DELAY)
	if(weapon_lock)
		om_cancel_timer(src, weapon_lock)
	weapon_lock = om_after(src, duration, PROC_REF(end_weapon_lock))
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
		identity().ooc_notes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes)
		identity().ooc_notes_likes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_likes)
		identity().ooc_notes_dislikes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_dislikes)
		identity().ooc_notes_favs = read_preference(/datum/preference/text/living/ooc_notes_favs)
		identity().ooc_notes_maybes = read_preference(/datum/preference/text/living/ooc_notes_maybes)
		identity().ooc_notes_style = read_preference(/datum/preference/toggle/living/ooc_notes_style)
		private_notes = client.prefs.read_preference(/datum/preference/text/living/private_notes)
		custom_link = client.prefs.read_preference(/datum/preference/text/human/custom_link) // migrated pref

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
		return (locate_in_list(module.modules, /obj/item/tank/jetpack))
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

EXTEND_INTERACTIONS(/mob/living/silicon/robot, \
	INTERACT_ITEM(null, PROC_REF(robot_interaction_item)), \
	INTERACT_HAND_UNGATED_AS(I_HELP, "Pet", PROC_REF(robot_interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_DISARM, "Tap", PROC_REF(robot_interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_GRAB, "Take hold", PROC_REF(robot_interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_HURT, "Punch", PROC_REF(robot_interaction_hand)), \
	INTERACT_DRAG("Block drag", TYPE_PROC_REF(/atom, interaction_swallow)), \
	INTERACT_ROBOT("Drop hat", PROC_REF(robot_drop_own_hat)), \
	INTERACT_SILICON("Deploy to shell", PROC_REF(robot_ai_deploy_shell)))

/// Old attackby: parts, laws, repairs, IDs and upgrades. Anything else sparks and reaches the attack.
/mob/living/silicon/robot/proc/robot_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/handcuffs)) // fuck i don't even know why isrobot() in handcuff code isn't working so this will have to do
		return TRUE
	if(opened && install_component(W, user))
		return TRUE
	if(opened && istype(W, /obj/item/implant/restrainingbolt) && !cell)
		install_bolt(W, user)
		return TRUE
	if(istype(W, /obj/item/aiModule))
		upload_law_module(W, user)
		return TRUE
	if(istype(W, /obj/item/stack/cable_coil) && can_rewire())
		cable_act(W, user)
		return TRUE
	if(istype(W, /obj/item/cell) && opened)
		insert_cell(W, user)
		return TRUE
	if(istype(W, /obj/item/encryptionkey) && opened)
		if(radio)//sanityyyyyy
			radio.attackby(W,user)//GTFO, you have your own procs
		else
			to_chat(user, span_filter_notice("Unable to locate a radio."))
		return TRUE
	if(W.GetID())
		swipe_id(W, user)
		return TRUE
	if(istype(W, /obj/item/borg/upgrade))
		apply_upgrade(W, user)
		return TRUE
	if(!(istype(W, /obj/item/robotanalyzer) || istype(W, /obj/item/healthanalyzer)) && W.force > 0)
		spark_system.start()
	return FALSE

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

/// Crowbar outside combat mode: the stance-declared pry interactions. In combat mode none is declared, so the crowbar goes on to strike.
/mob/living/silicon/robot/crowbar_act(mob/user, obj/item/tool)
	if(run_interaction_entry(user, src, tool, ROBOT_ENTRY_CROWBAR))
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_SKIP_TO_ATTACK

/// Abstract: working the chassis with a crowbar outside combat mode (run from crowbar_act()).
/datum/interaction/robot_pry
	entry = ROBOT_ENTRY_CROWBAR
	default_action = INPUT_ACTION_USE
	tool = TOOL_CROWBAR
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT)
	effect = /mob/living/silicon/robot/proc/interaction_crowbar

/datum/interaction/robot_pry/help
	id = "robot_pry_help"
	name = "Pry the cover or a part"
	stance = I_HELP

/datum/interaction/robot_pry/disarm
	id = "robot_pry_disarm"
	name = "Pry the cover or a part"
	stance = I_DISARM

/datum/interaction/robot_pry/grab
	id = "robot_pry_grab"
	name = "Pry the cover or a part"
	stance = I_GRAB

/// Crowbar: open or close the cover, lever out the brain, or pry out a part.
/mob/living/silicon/robot/proc/interaction_crowbar(mob/user, obj/item/tool, datum/interaction/interaction)
	if(!opened)
		open_cover(user)
		return TRUE
	if(cell)
		close_cover(user)
		return TRUE
	if(wiresexposed && wires.is_all_cut())
		extract_mmi(user)
		return TRUE
	pry_component(user)
	return TRUE

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
	om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(extract_mmi_robot_done), done_args = list(user))
	return TRUE

/mob/living/silicon/robot/proc/extract_mmi_robot_done(mob/user)
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
	om_ask(user, /datum/om/prompt/choice/pry_component, PROC_REF(pry_component_chosen), choices = removable)
	return TRUE

/// Component name -> slot. Re-checked on the answer: next to the borg and able, and the borg is
/// still open with no cell.
/datum/om/prompt/choice/pry_component
	title = "Remove Component"
	message = "Which component do you want to pry out?"
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/datum/om/prompt/choice/pry_component/valid()
	var/mob/living/silicon/robot/R = subject
	return (!R.opened || R.cell) ? "not open" : null

/mob/living/silicon/robot/proc/pry_component_chosen(datum/om/prompt/choice/pry_component/ask)
	var/mob/user = ask.answerer
	var/datum/robot_component/C = get_component(ask.choices[ask.choice])
	if(!C || C.installed == ROBOT_PART_MISSING || !C.wrapped)
		return FALSE
	var/obj/item/I = C.uninstall()
	to_chat(user, span_filter_notice("You remove \the [I]."))
	I.forceMove(loc)
	return TRUE

/// Welder outside combat mode: the stance-declared repair interactions. In combat mode none is declared, so the welder goes on to strike.
/mob/living/silicon/robot/welder_act(mob/user, obj/item/tool)
	if(run_interaction_entry(user, src, tool, ROBOT_ENTRY_WELDER))
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_SKIP_TO_ATTACK

/// Abstract: welding the chassis's dents outside combat mode (run from welder_act()).
/datum/interaction/robot_weld_repair
	entry = ROBOT_ENTRY_WELDER
	default_action = INPUT_ACTION_USE
	tool = TOOL_WELDER
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT)
	effect = /mob/living/silicon/robot/proc/interaction_weld_repair

/datum/interaction/robot_weld_repair/help
	id = "robot_weld_repair_help"
	name = "Weld the dents"
	stance = I_HELP

/datum/interaction/robot_weld_repair/disarm
	id = "robot_weld_repair_disarm"
	name = "Weld the dents"
	stance = I_DISARM

/datum/interaction/robot_weld_repair/grab
	id = "robot_weld_repair_grab"
	name = "Weld the dents"
	stance = I_GRAB

/// Welder: fix the chassis's dents (not your own).
/mob/living/silicon/robot/proc/interaction_weld_repair(mob/user, obj/item/tool, datum/interaction/interaction)
	if(src == user)
		to_chat(user, span_warning("You lack the reach to be able to repair yourself."))
		return TRUE
	if(!injury_load(INJURY_CATEGORY_PHYSICAL))
		to_chat(user, span_filter_notice("Nothing to fix here!"))
		return TRUE
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder?.remove_fuel(0))
		to_chat(user, span_filter_warning("Need more welding fuel!"))
		return TRUE
	user.setClickCooldown(user.get_attack_speed(welder))
	mend(TREAT_PLATING_REPAIR, 30)
	add_fingerprint(user)
	visible_message(span_filter_notice("[span_red("[user] has fixed some of the dents on [src]!")]"))
	return TRUE

/mob/living/silicon/robot/declare_interactions(list/into)
	into += list(
		/datum/interaction/robot_pry/help,
		/datum/interaction/robot_pry/disarm,
		/datum/interaction/robot_pry/grab,
		/datum/interaction/robot_weld_repair/help,
		/datum/interaction/robot_weld_repair/disarm,
		/datum/interaction/robot_weld_repair/grab,
	)
	..()

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
	om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(wrench_act_robot_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/mob/living/silicon/robot/proc/wrench_act_robot_done(mob/user)
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
			om_task_timed(src, 1.5 MINUTES, target = src, timed_action_flags = IGNORE_INCAPACITATED, receiver = src, on_done = PROC_REF(resist_restraints_robot_done), done_args = list())

	return

/mob/living/silicon/robot/proc/resist_restraints_robot_done()
	visible_message(span_danger("[src] manages to break \the [bolt]!"), span_warning("You successfully break your [bolt]."))
	bolt.malfunction = MALFUNCTION_PERMANENT

/mob/living/silicon/robot/proc/module_reset(notify = TRUE)
	transform_with_anim() //sprite animation
	uneq_all()
	hud_used.update_robot_modules_display(TRUE)
	modtype = initial(modtype)
	hands.icon_state = get_hud_module_icon()

	// Basic upgrades (VTEC, ...) mutate the robot directly (verbs added,
	// vars flipped) rather than living inside the module being reset, so
	// they need their own undo pass or they'd leave permanent side effects
	// behind after the reset.
	robot_upgrade_prototype(/obj/item/borg/upgrade/basic/vtec)?.remove_upgrade(src)

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

/// Old attack_hand (never reached the gate or the default touch): dismounts, cell removal, petting and punching.
/mob/living/silicon/robot/proc/robot_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(LAZYLEN(src?.buckled_mob_list()))
		//We're getting off!
		if(user in src?.buckled_mob_list())
			riding_datum?.force_dismount(user)
		//We're kicking everyone off!
		if(user == src)
			for(var/rider in src?.buckled_mob_list())
				riding_datum?.force_dismount(rider)
		return TRUE

	add_fingerprint(user)

	if(opened && !wiresexposed && !issilicon(user))
		take_out_power_part(user)

	if(ishuman(user) && !opened)
		hand_interact(user, interaction.stance)
	return TRUE

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

/// Petting, punching, tapping and vore on a closed chassis, in `stance` (the touch interaction's).
/mob/living/silicon/robot/proc/hand_interact(mob/living/carbon/human/H, stance)
	switch(stance)
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
		om_ask(H, /datum/om/prompt/choice, PROC_REF(grab_vore_chosen), title = "Feed or Eat", message = "Do you wish to eat [src] or feed yourself to them?", choices = list("Nevermind!", "Eat", "Feed"), buttons = TRUE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)
		return
	if(is_vore_predator(H) && src.devourable)
		om_ask(H, /datum/om/prompt/choice, PROC_REF(grab_vore_chosen), title = "Eat?", message = "Do you wish to eat [src]?", choices = list("Nevermind!", "Eat"), buttons = TRUE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)
		return
	if(H.devourable && src.feeding)
		om_ask(H, /datum/om/prompt/choice, PROC_REF(grab_vore_chosen), title = "Feed?", message = "Do you wish to feed yourself to [src]?", choices = list("Nevermind!", "Feed"), buttons = TRUE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)

/mob/living/silicon/robot/proc/grab_vore_chosen(datum/om/prompt/choice/ask)
	var/mob/living/carbon/human/H = ask.answerer
	switch(ask.choice)
		if("Eat")
			if(is_vore_predator(H) && devourable)
				feed_grabbed_to_self(H, src)
		if("Feed")
			if(H.devourable && feeding)
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
		if(check_access(H.get_active_hand()) || check_access(H.get_equipped_item(SLOT_ID_ID)))
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
	OM_EMIT(src, /datum/om/event/robot_belly_fullness, belly_class, fullness_ref)
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
	var/datum/robot_belly/belly = robot_belly
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

/// Old attack_robot: a cyborg clicking itself drops its hat. The old body ran ..() (attack_ai) first,
/// so that runs first here too, as the AI-style Use (silicon interactions, then the default).
/mob/living/silicon/robot/proc/robot_drop_own_hat(mob/user, obj/item/held, datum/interaction/interaction)
	if(user != src || isnull(hat))
		return FALSE

	actor_use(/datum/input_adapter/ai, user, src)
	balloon_alert(user, "dropping hat...")
	om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_robot_robot_done), done_args = list(user))
	return TRUE

/mob/living/silicon/robot/proc/attack_robot_robot_done(mob/user)
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

/mob/living/silicon/robot/proc/repick_laws()
	return

/mob/living/silicon/robot/proc/add_robot_verbs()
	add_verb(src, robot_verbs_default)
	add_verb(src, silicon_subsystems)
	grant_ability(ABILITY_ID_ROBOT_SENSOR_MODE, src)
	grant_ability(ABILITY_ID_ROBOT_MOUNT, src)
	grant_ability(ABILITY_ID_ROBOT_TOGGLE_MODULE_1, src)
	grant_ability(ABILITY_ID_ROBOT_TOGGLE_MODULE_2, src)
	grant_ability(ABILITY_ID_ROBOT_TOGGLE_MODULE_3, src)
	if(CONFIG_GET(flag/allow_robot_recolor))
		grant_ability(ABILITY_ID_ROBOT_RECOLOUR, src)

/mob/living/silicon/robot/proc/remove_robot_verbs()
	remove_verb(src, robot_verbs_default)
	remove_verb(src, silicon_subsystems)
	revoke_ability(ABILITY_ID_ROBOT_SENSOR_MODE, src)
	revoke_ability(ABILITY_ID_ROBOT_MOUNT, src)
	revoke_ability(ABILITY_ID_ROBOT_TOGGLE_MODULE_1, src)
	revoke_ability(ABILITY_ID_ROBOT_TOGGLE_MODULE_2, src)
	revoke_ability(ABILITY_ID_ROBOT_TOGGLE_MODULE_3, src)
	if(CONFIG_GET(flag/allow_robot_recolor))
		revoke_ability(ABILITY_ID_ROBOT_RECOLOUR, src)

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
		om_unhook(old_ai, list(/datum/om/event/silicon_laws_changed, /datum/om/event/qdeleting), src)
		old_ai.connected_robots -= src
	connected_ai = new_ai
	if(new_ai)
		new_ai.connected_robots |= src
		om_hook(new_ai, /datum/om/event/silicon_laws_changed, src, PROC_REF(on_master_laws_changed))
		om_hook(new_ai, /datum/om/event/qdeleting, src, PROC_REF(on_master_deleted))
	log_runtime("ROBOT_LINK: [key_name(src)] master AI [old_ai ? key_name(old_ai) : "none"] -> [new_ai ? key_name(new_ai) : "none"].")
	return TRUE

/mob/living/silicon/robot/proc/on_master_laws_changed(datum/source, datum/om/event/silicon_laws_changed/event)
	EVENT_HANDLER
	if(lawupdate)
		sync()

/mob/living/silicon/robot/proc/on_master_deleted(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
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
		om_after(src, delay, PROC_REF(play_subversion_sequence), operator_name, operator_their, step + 1)
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

	// A cancel picks "Default".
	om_ask(src, /datum/om/prompt/choice, PROC_REF(rest_style_chosen), title = "Resting Pose", message = "Select resting pose", choices = sprite_datum.rest_sprite_options, buttons = TRUE, cancel_answer = "Default")

/mob/living/silicon/robot/proc/rest_style_chosen(datum/om/prompt/choice/ask)
	rest_style = ask.choice
	update_icon()

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
	if(M in src?.buckled_mob_list())
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
		src?.buckled_mob_list()[M] = "riding"

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
	if(var_name == NAMEOF(src, syndicate))
		set_syndicate(var_value)
		return TRUE
	switch(var_name)
		if(NAMEOF(src, emagged))
			robotact?.update_static_data_for_all_viewers()
		if(NAMEOF(src, emag_items))
			robotact?.update_static_data_for_all_viewers()

	. = ..()

// --- Syndicate cyborgs --------------------------------------------------------------------
// The traitor HUD images are made once, when the borg turns syndicate or logs in,
// and removed on logout or when it stops being syndicate. Never per tick.

/mob/living/silicon/robot/proc/set_syndicate(state)
	state = !!state
	if(syndicate == state)
		return
	syndicate = state
	log_game("CYBORG: [key_name(src)] syndicate state set to [state].")
	if(syndicate)
		apply_syndicate_state()
	else
		clear_traitor_hud()

/// Cut the AI link, mark the mind and show the traitor HUD.
/mob/living/silicon/robot/proc/apply_syndicate_state()
	disconnect_from_ai()
	// TODO: Update to new antagonist system.
	if(mind && !mind.special_role)
		mind.special_role = "traitor"
		LAZYOR(GLOB.traitors.current_antagonists, mind)
	build_traitor_hud()

/mob/living/silicon/robot/proc/build_traitor_hud()
	clear_traitor_hud()
	if(!client)
		return
	for(var/datum/mind/tra in GLOB.traitors.current_antagonists)
		if(!tra.current)
			continue
		LAZYADD(traitor_hud_images, image('icons/mob/mob.dmi', loc = tra.current, icon_state = "traitor"))
	if(!LAZYLEN(traitor_hud_images))
		return
	traitor_hud_client = client
	client.images += traitor_hud_images

/mob/living/silicon/robot/proc/clear_traitor_hud()
	if(traitor_hud_client && LAZYLEN(traitor_hud_images))
		traitor_hud_client.images -= traitor_hud_images
	traitor_hud_client = null
	traitor_hud_images = null

/// This proc checks to see if a borg has access to whatever they're interacting with
/obj/proc/siliconaccess(mob/user)
	var/mob/living/silicon/robot/R = user
	if(istype(R))
		return check_access(R.idcard)
	if(issilicon(user))
		return TRUE
	return FALSE

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
	var/obj/T = locate_in_list(module, given_type)
	if(!T)
		T = locate_within(module, given_type)
	if(!T)
		T = locate_in_list(module.modules, given_type)
	return T

// Do we support specific upgrades?
/mob/living/silicon/robot/proc/supports_upgrade(given_type)
	return (given_type in module.supported_upgrades)

DECLARE_REF(/mob/living/silicon/robot, "robotact", OWNED, null)
DECLARE_DEFAULT_CHILD(/mob/living/silicon/robot, "robotact", /datum/tgui_module/robot_ui)
DECLARE_REF(/mob/living/silicon/robot, "bolt", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "communicator", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "rbPDA", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "hat_overlay", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "inv1", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "inv2", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "inv3", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "robot_modules_background", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "ion_trail", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "spark_system", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "hat", SPILL, null)
// on_destroy() still takes these apart in order: the MMI hands its mind on, the cell unhooks.
// The module, radio, camera and components are deleted by phase 4, after the AI link and shell are undone.
DECLARE_REF(/mob/living/silicon/robot, "mmi", HELD, null)
DECLARE_REF(/mob/living/silicon/robot, "cell", HELD, null)
DECLARE_REF(/mob/living/silicon/robot, "connected_ai", HELD, null)
DECLARE_REF(/mob/living/silicon/robot, "traitor_hud_client", HELD, null)
DECLARE_REF(/mob/living/silicon/robot, "module", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "radio", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "camera", OWNED, null)
DECLARE_REF(/mob/living/silicon/robot, "components", OWNED_LIST, null)
DECLARE_REF(/mob/living/silicon/robot, "sprite_datum", STATIC, null)
