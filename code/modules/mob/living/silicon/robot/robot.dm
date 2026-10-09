
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
	/// Set when the borg is destroyed with a mind and a place: the MMI leaves for the turf (the policy of `mmi`).
	var/tmp/mmi_ejects = FALSE

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
	// ALLOW(instance_list): d: per-mob req_access with starting entries, edited at runtime; mobs are few
	var/list/req_access = list(ACCESS_ROBOTICS) // Interned per subtype in Initialize().
	var/ident = 0
	var/viewalerts = 0
	var/modtype = "Default"
	var/sprite_type = null
	var/lower_mod = 0
	var/jetpack = 0
	var/datum/effect/effect/system/ion_trail_follow/ion_trail = null
	var/jeton = 0
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
	var/list/active_module_types // The types of the active modules (module_slots_changed()). Lazy.
	vore_capacity_ex = list()
	vore_fullness_ex = list()
	vore_icon_bellies = list()

// --- Lifecycle ------------------------------------------------------------------------------

/mob/living/silicon/robot/Initialize(mapload, is_decoy)
	if(islist(req_access))
		req_access = shared_type_list(type, "req_access", req_access)
	global.observe(src, /datum/notice/living_shield_injury, src, then(PROC_REF(absorb_injury_with_shield)))

	add_language(LANGUAGE_ROBOT_TALK, 1)
	add_language(LANGUAGE_GALCOM, 1)
	add_language(LANGUAGE_EAL, 1)


	rel_set(src, nameof(robot_modules_background), new /atom/movable/screen()) // ALLOW(decl): screen object made in nullspace, configured before parent init
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
	grant(src, robot_utility(), src)
	if(may_pick_name())
		grant(src, robot_naming(), src)

	. = ..()

	add_robot_verbs()
	setup_hud_images()
	resolve_sprite_datum()
	recompute_power_demand()
	update_senses()

	add_hose_connector(/datum/hose_connector/input/borg)
	add_hose_connector(/datum/hose_connector/output/borg)

/mob/living/silicon/robot/proc/setup_radio()
	rel_set(src, nameof(radio), new /obj/item/radio/borg(src))
	rel_set(src, nameof(common_radio), radio) // an alias of the owned radio

/// The photo camera and the machinery camera that feeds the robots network.
/mob/living/silicon/robot/proc/setup_camera()
	if(photo_camera_type)
		rel_set(src, nameof(aiCamera), new photo_camera_type(src))
	if(!scrambledcodes && !camera)
		rel_set(src, nameof(camera), new /obj/machinery/camera(src))
		camera.c_tag = real_name
		camera.replace_networks(list(NETWORK_DEFAULT,NETWORK_ROBOTS))
		if(wire_is_cut(src, WIRE_BORG_CAMERA))
			camera.status = 0

/// Chassis that come with a brain override this. Assembled cyborgs get their
/// MMI from the robot suit.
/mob/living/silicon/robot/proc/setup_brain()
	return

/mob/living/silicon/robot/proc/setup_laws()
	rel_set(src, nameof(laws), new using_map.default_law_type) //use map's default
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
	if(!cell && cell_type)
		set_cell(new cell_type(src))

/mob/living/silicon/robot/proc/setup_hud_images()
	rel_add(src, nameof(hud_list), gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_HEALTH), HEALTH_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image('icons/mob/hud.dmi', src, "hudhealth100", plane = PLANE_CH_STATUS), STATUS_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image('icons/mob/hud.dmi', src, "hudhealth100", plane = PLANE_CH_LIFE), LIFE_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_ID), ID_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_WANTED), WANTED_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_IMPLOYAL), IMPLOYAL_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_IMPCHEM), IMPCHEM_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_IMPTRACK), IMPTRACK_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image('icons/mob/hud.dmi', src, "hudblank", plane = PLANE_CH_SPECIAL), SPECIALROLE_HUD)

/// The sprite datum is never null after Initialize: the module default, or
/// the generic default when the sprite subsystem isn't ready.
/mob/living/silicon/robot/proc/resolve_sprite_datum()
	if(sprite_datum)
		return
	if(SSrobot_sprites)
		proto_set(src, nameof(sprite_datum), SSrobot_sprites.get_default_module_sprite(modtype))
	if(!sprite_datum)
		proto_set(src, nameof(sprite_datum), new /datum/robot_sprite/default(src)) // unregistered fallback: the robot's private copy

/mob/living/silicon/robot/rejuvenate()
	// Clear every located load first, then rebuild any fried or missing parts.
	fully_heal()
	for(var/datum/robot_component/C as anything in components)
		if(C.internal)
			C.installed = ROBOT_PART_INSTALLED
			continue
		if(C.installed == ROBOT_PART_DESTROYED)
			spent(C.uninstall())
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

/// A borg has no nutrition, body temperature or radiation dose to reset (audit P2-D11);
/// its parts and cell were rebuilt above.
/mob/living/silicon/robot/rejuvenate_physiology()
	return

//If there's an MMI in the robot, have it ejected when the mob goes away. --NEO
//Improved /N
// the MMI receives the borg's mind on the turf; shells revert; parts and hat drop.
/mob/living/silicon/robot/on_destroy(force)
	revoke(src, robot_utility(), src)
	revoke(src, robot_naming(), src)
	if(mmi)//Safety for when a cyborg gets dust()ed. Or there is no MMI inside.
		if(mind)
			// The MMI lands on the borg's turf (get_turf() sees through any container). The
			// mind only follows it there: it must never stay in an MMI inside this deleting mob.
			var/turf/T = get_turf(src)
			var/datum/mind_host/host = get_mind_host(mmi)
			if(T)
				mmi.forceMove(T)
				mmi_ejects = TRUE // the MMI's policy is OWN_SPILL from here: it lives on, on the turf
			if(T && host)
				var/mob/living/carbon/brain/view = host.receive_mind(mind, "cyborg [src] destroyed")
				view.remove_language(LANGUAGE_ROBOT_TALK)
			else
				if(!T)
					// The MMI stays in the robot and goes with it by ownership policy.
					log_game("MIND: cyborg [key_name(src)] was destroyed with no location; its MMI is lost and the mind is ghosted without re-entry.")
				else
					if(!shell) // Shells don't have brainmobs in their MMIs.
						log_game("MIND: cyborg [key_name(src)] was destroyed but its MMI [mmi] has no mind host; ghosting.")
						to_chat(src, span_danger("Oops! Something went very wrong, your MMI was unable to receive your mind. You have been ghosted. Please make a bug report so we can fix this bug."))
				ghostize(FALSE)
		// A mindless MMI stays in the robot and goes with it by ownership policy.
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
/// Ownership: the power mount's `wrapped` owns the cell (install() adopts it); `cell` is a
/// relation alias of it, so the cell has exactly one owner.
/mob/living/silicon/robot/proc/set_cell(obj/item/cell/new_cell)
	if(cell == new_cell)
		return
	var/obj/item/cell/old_cell = cell
	if(old_cell)
		unobserve(old_cell, /datum/act/emp, src)
		unobserve(old_cell, /datum/notice/qdeleting, src)
	if(new_cell && new_cell.loc != src)
		new_cell.forceMove(src)
	rel_set(src, nameof(cell), new_cell)
	var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
	// A5: a replacement (not a removal: remove_cell() uninstalls first and keeps the cell) takes
	// the old cell out of the mount and deletes it, instead of orphaning it in contents (a
	// suit-built borg's default cell, overwritten by the chest's).
	if(old_cell && new_cell && mount?.wrapped == old_cell)
		consume(mount.uninstall())
	if(new_cell)
		global.observe(new_cell, /datum/act/emp, src, adjusts_with(PROC_REF(shield_cell_from_emp)))
		global.observe(new_cell, /datum/notice/qdeleting, src, then(PROC_REF(on_cell_deleted)))
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

/mob/living/silicon/robot/proc/shield_cell_from_emp(datum/act/emp/pulse)
	SHOULD_NOT_SLEEP(TRUE)
	pulse.protection |= EMP_PROTECT_SELF

/mob/living/silicon/robot/proc/on_cell_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
	if(mount?.wrapped == source)
		rel_take(mount, nameof(mount.wrapped))
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
		var/camera_on = stat != DEAD && !wire_is_cut(src, WIRE_BORG_CAMERA) && is_component_functioning(ROBOT_SLOT_CAMERA)
		camera.set_status(camera_on ? 1 : 0)
	if(radio)
		radio.on = is_component_functioning(ROBOT_SLOT_RADIO) ? 1 : 0
	var/sees = stat != DEAD && !has_status(STAT_PARALYZED) && !has_status(STAT_BLINDED) && !(sdisabilities & BLIND) && is_component_functioning(ROBOT_SLOT_CAMERA)
	set_blinded(!sees)
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
	set_lights_on(new_state)
	refresh_glow()
	recompute_power_demand()

/mob/living/silicon/robot/life_light_due()
	return TRUE

/mob/living/silicon/robot/life_light(datum/seq_frame/life/F)
	if(src.lights_on)
		src.set_light(src.integrated_light_power, 1, src.robot_light_col)
		return TRUE
	return ..()

// --- Countdowns ------------------------------------------------------------------------------

/mob/living/silicon/robot/proc/start_killswitch(delay = ROBOT_KILLSWITCH_DELAY)
	if(after_pending(src, "killswitch"))
		return FALSE
	after(src, delay, PROC_REF(fire_killswitch), key = "killswitch")
	log_game("ROBOT: killswitch armed on [key_name(src)] ([delay / (1 SECOND)]s).")
	return TRUE

/mob/living/silicon/robot/proc/cancel_killswitch()
	if(!after_pending(src, "killswitch"))
		return FALSE
	cancel_after(src, "killswitch")
	return TRUE

/mob/living/silicon/robot/proc/fire_killswitch()
	if(stat == DEAD)
		return
	to_chat(src, span_danger("Killswitch Activated"))
	log_game("ROBOT: killswitch fired on [key_name(src)].")
	after(src, 0.5 SECONDS, TYPE_PROC_REF(/mob, gib))

/// Lock the modules. Equipment drops once; activation is refused until the lock times out.
/mob/living/silicon/robot/proc/start_weapon_lock(duration = ROBOT_WEAPON_LOCK_DELAY)
	if(after_pending(src, "weapon_lock"))
		cancel_after(src, "weapon_lock")
	after(src, duration, PROC_REF(end_weapon_lock), key = "weapon_lock")
	uneq_all()
	to_chat(src, span_danger("Weapon lock engaged."))

/mob/living/silicon/robot/proc/end_weapon_lock()
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
		rel_set(src, nameof(rbPDA), new/obj/item/pda/ai(src))
	rbPDA.set_name_and_job(name,"[modtype] [braintype]")
	grant(src, granted_verb(/obj/item/pda/ai/verb/cmd_pda_open_ui), src)

/mob/living/silicon/robot/proc/setup_communicator()
	if (!communicator)
		rel_set(src, nameof(communicator), new/obj/item/communicator/integrated(src))
	communicator.register_device(name, "[modtype] [braintype]")
	grant(src, granted_verb(/obj/item/communicator/integrated/verb/activate), src)

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
			proto_set(src, nameof(sprite_datum), module_sprites[1])
			sprite_datum.do_equipment_glamour(module)
			return
	if(mind)
		sprite_name = mind.name
	if(!selecting_module)
		var/datum/tgui_module/robot_ui_module/menu = new(src)
		menu.tgui_interact(src)

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
	set category = VERB_CAT_OBJECT
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
	if(prob(75) && Proj.damage > 0) fx_sparks(src, 5, FALSE)
	return 2

// --- Tool and item interactions ---------------------------------------------------------------

MSG_DEF_SELF(robot_tool/no_wiring, "You can't reach the wiring.")
MSG_DEF_SELF(robot_tool/no_bolt, "There is no restraining bolt installed.")
MSG_DEF_SELF(robot_tool/self_repair, "You lack the reach to be able to repair yourself.")
MSG_DEF_SELF(robot_tool/no_dents, "Nothing to fix here.")

/// The cyborg's own item, tool and touch ops (called from CAPABILITIES(/mob/living/silicon/robot), library/mob/hands.dm). They sit above the
/// living-mob defaults (a hit); the crowbar and welder answer outside harm intent, where the old interactions were stance-declared (they strike in combat mode).
/proc/robot_interactions()
	return list(
		op("robot_item", item(/obj/item), label("Use on"), passes(), then(TYPE_PROC_REF(/mob/living/silicon/robot, robot_item_used))),
		op("robot_pet", hand(), ungated(), stance(I_HELP), label("Pet"), then(TYPE_PROC_REF(/mob/living/silicon/robot, robot_hand_help))),
		op("robot_tap", hand(), ungated(), stance(I_DISARM), label("Tap"), then(TYPE_PROC_REF(/mob/living/silicon/robot, robot_hand_disarm))),
		op("robot_hold", hand(), ungated(), stance(I_GRAB), label("Take hold"), then(TYPE_PROC_REF(/mob/living/silicon/robot, robot_hand_grab))),
		op("robot_punch", hand(), ungated(), stance(I_HURT), label("Punch"), then(TYPE_PROC_REF(/mob/living/silicon/robot, robot_hand_hurt))),
		op("deploy_shell", remote(), label("Deploy to shell"), when(TYPE_PROC_REF(/mob/living/silicon/robot, shell_open_to_ai)), then(TYPE_PROC_REF(/mob/living/silicon/robot, robot_ai_deploy_shell))),
		op("robot_pry", tool(TOOL_CROWBAR), stance(I_HELP, I_DISARM, I_GRAB), label("Pry the cover or a part"), wait(0), then(TYPE_PROC_REF(/mob/living/silicon/robot, interaction_crowbar))),
		op("robot_weld_repair", tool(TOOL_WELDER), stance(I_HELP, I_DISARM, I_GRAB), label("Weld the dents"), costs(RES_FUEL, 0), wait(0),
			needs(req(TYPE_PROC_REF(/mob/living/silicon/robot, repairing_another), because = MSG(robot_tool/self_repair)), req(TYPE_PROC_REF(/mob/living/silicon/robot, has_dents), because = MSG(robot_tool/no_dents))),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, interaction_weld_repair))),
		op("robot_wires", any_of_tools(TOOL_WIRECUTTER, TOOL_MULTITOOL), label("Work the wiring"), wait(0), needs(req(TYPE_PROC_REF(/mob/living/silicon/robot, wiring_reachable), because = MSG(robot_tool/no_wiring))), then(TYPE_PROC_REF(/mob/living/silicon/robot, robot_wires_worked))),
		op("robot_screwdriver", tool(TOOL_SCREWDRIVER), label("Work the panel"), wait(0), needs(req(TYPE_PROC_REF(/mob/living/silicon/robot, panel_open_holds), silent = TRUE)), then(TYPE_PROC_REF(/mob/living/silicon/robot, robot_screwdriver_used))),
		op("robot_bolt_wrench", tool(TOOL_WRENCH), label("Remove the restraining bolt"), wait(2 SECONDS), needs(req(TYPE_PROC_REF(/mob/living/silicon/robot, bolt_wrench_ready), silent = TRUE), req(TYPE_PROC_REF(/mob/living/silicon/robot, has_bolt), because = MSG(robot_tool/no_bolt))),
			starts(TYPE_PROC_REF(/mob/living/silicon/robot, bolt_wrench_started)), then(TYPE_PROC_REF(/mob/living/silicon/robot, wrench_act_robot_done))))

/// The panel is open and the cell is out: a wrench can reach the restraining bolt.
/mob/living/silicon/robot/proc/bolt_wrench_ready(datum/act/op/A)
	return opened && !cell

/mob/living/silicon/robot/proc/has_bolt(datum/act/op/A)
	return !!bolt

/mob/living/silicon/robot/proc/bolt_wrench_started(datum/act/op/A)
	to_chat(A.actor, span_filter_notice("You begin removing \the [bolt]."))

/mob/living/silicon/robot/proc/panel_open_holds(datum/act/op/A)
	return opened

/mob/living/silicon/robot/proc/wiring_reachable(datum/act/op/A)
	return wiresexposed

/// The welder is for another cyborg's dents, not your own.
/mob/living/silicon/robot/proc/repairing_another(datum/act/op/A)
	return A.actor != src

/// An AI may deploy into a shell that allows it and is not another AI's.
/mob/living/silicon/robot/proc/shell_open_to_ai(datum/act/op/A)
	return read_once(shell && CONFIG_GET(flag/allow_ai_shells) && (!connected_ai || connected_ai == A.actor))

/mob/living/silicon/robot/proc/robot_wires_worked(datum/act/op/A)
	wires_open(src, A.actor)
	return OP_OK

/mob/living/silicon/robot/proc/robot_screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!cell)
		set_wiresexposed(!wiresexposed)
		to_chat(user, span_filter_notice("The wires have been [wiresexposed ? "exposed" : "unexposed"]."))
		playsound(src, tool.usesound, 50, TRUE)
		return OP_OK
	if(radio)
		radio.item_used_on(tool, user)
	else
		to_chat(user, span_filter_notice("Unable to locate a radio."))
	return OP_OK

/mob/living/silicon/robot/proc/robot_hand_help(datum/act/op/A)
	return robot_interaction_hand(A, I_HELP)

/mob/living/silicon/robot/proc/robot_hand_disarm(datum/act/op/A)
	return robot_interaction_hand(A, I_DISARM)

/mob/living/silicon/robot/proc/robot_hand_grab(datum/act/op/A)
	return robot_interaction_hand(A, I_GRAB)

/mob/living/silicon/robot/proc/robot_hand_hurt(datum/act/op/A)
	return robot_interaction_hand(A, I_HURT)

/// The item op: parts, laws, repairs, IDs and upgrades. Anything else sparks and reaches the attack.
/mob/living/silicon/robot/proc/robot_item_used(datum/act/op/A)
	return robot_interaction_item(A.actor, A.held) ? OP_OK : OP_PASS

/// Parts, laws, repairs, IDs and upgrades: TRUE when the item was taken.
/mob/living/silicon/robot/proc/robot_interaction_item(mob/user, obj/item/W)
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
			radio.item_used_on(W, user)//GTFO, you have your own procs
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
		fx_sparks(src, 5, FALSE)
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
	if(!move_into(src, nameof(src.bolt), W, user))
		return FALSE
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
	act_message(user, src, others = span_filter_notice(span_red("%U% has fixed some of the burnt wires on %T%!")))
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

/// Crowbar outside combat mode: open or close the cover, lever out the brain, or pry out a part.
/mob/living/silicon/robot/proc/interaction_crowbar(datum/act/op/A)
	var/mob/user = A.actor
	if(!opened)
		open_cover(user)
		return OP_OK
	if(cell)
		close_cover(user)
		return OP_OK
	if(wiresexposed && wires_all_cut(src))
		extract_mmi(user)
		return OP_OK
	pry_component(user)
	return OP_OK

/mob/living/silicon/robot/proc/open_cover(mob/user)
	if(locked)
		to_chat(user, span_filter_notice("The cover is locked and cannot be opened."))
		return FALSE
	to_chat(user, span_filter_notice("You open the cover."))
	set_opened(TRUE)
	return TRUE

/mob/living/silicon/robot/proc/close_cover(mob/user)
	to_chat(user, span_filter_notice("You close the cover."))
	set_opened(FALSE)
	return TRUE

/// Cell out, wires exposed and all cut: lever out the MMI, leaving a damaged chassis.
/mob/living/silicon/robot/proc/extract_mmi(mob/user)
	if(!mmi)
		to_chat(user, span_filter_notice("\The [src] has no brain to remove."))
		return FALSE
	to_chat(user, span_filter_notice("You jam the crowbar into the robot and begin levering [mmi]."))
	task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(extract_mmi_robot_done), done_args = list(user))
	return TRUE

/mob/living/silicon/robot/proc/extract_mmi_robot_done(mob/user)
	if(QDELETED(src) || !mmi || !opened || cell || !wiresexposed || !wires_all_cut(src))
		return FALSE
	to_chat(user, span_filter_notice("You damage some parts of the chassis, but eventually manage to rip out [mmi]!"))
	var/obj/item/robot_parts/robot_suit/C = new/obj/item/robot_parts/robot_suit(loc)
	rel_set(C, nameof(C.l_leg), new/obj/item/robot_parts/l_leg(C))
	rel_set(C, nameof(C.r_leg), new/obj/item/robot_parts/r_leg(C))
	rel_set(C, nameof(C.l_arm), new/obj/item/robot_parts/l_arm(C))
	rel_set(C, nameof(C.r_arm), new/obj/item/robot_parts/r_arm(C))
	new/obj/item/robot_parts/chest(loc)
	spent(src, user)
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
	open_request(src, /datum/prompt/choice, PROC_REF(pry_component_chosen), answerer = user, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, valid = PROC_REF(pry_component_askable), title = "Remove Component", question = "Which component do you want to pry out?", choices = removable, timeout = 0)
	return TRUE

/// The choices are component name -> slot. Re-checked on the answer: the borg is still open with no cell.
/mob/living/silicon/robot/proc/pry_component_askable(datum/request/R)
	return opened && !cell

/mob/living/silicon/robot/proc/pry_component_chosen(datum/act/request/A)
	if(!A.answer)
		return FALSE
	var/datum/prompt/choice/pry_question = A.request
	var/mob/user = A.request.answerer
	var/datum/robot_component/C = get_component(pry_question.choices[A.answer.value])
	if(!C || C.installed == ROBOT_PART_MISSING || !C.wrapped)
		return FALSE
	var/obj/item/I = C.uninstall()
	to_chat(user, span_filter_notice("You remove \the [I]."))
	I.forceMove(loc)
	return TRUE

/// TRUE when there is plating damage to weld.
/mob/living/silicon/robot/proc/has_dents(datum/act/op/A)
	return read_once(!!injury_load(INJURY_CATEGORY_PHYSICAL))

/// Welder: fix the chassis's dents (not your own).
/mob/living/silicon/robot/proc/interaction_weld_repair(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder?.remove_fuel(0))
		to_chat(user, span_filter_warning("Need more welding fuel!"))
		return OP_OK
	user.setClickCooldown(user.get_attack_speed(welder))
	mend(TREAT_PLATING_REPAIR, 30)
	add_fingerprint(user)
	act_message(src, user, others = span_filter_notice("[span_red("%T% has fixed some of the dents on %U%!")]"))
	return OP_OK

/mob/living/silicon/robot/proc/wrench_act_robot_done(datum/act/op/A)
	bolt.forceMove(get_turf(src))
	rel_take(src, nameof(bolt))
	to_chat(A.actor, span_filter_notice("You remove the restraining bolt."))
	return OP_OK

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
	perform_op(src, src, "break_bolt", null, ORIGIN_VERB, AUTH_PHYSICAL)

/// A bolt that still holds can be broken (the "break_bolt" op).
/mob/living/silicon/robot/proc/bolt_breakable(datum/act/op/A)
	return read_once(!isnull(bolt) && !bolt.malfunction)

/mob/living/silicon/robot/proc/bolt_break_text(datum/act/op/A)
	return msg_text(span_warning("You attempt to break your [bolt]. (This will take around 90 seconds and you need to stand still)"), span_danger("%U% is trying to break their [bolt]!"))

/mob/living/silicon/robot/proc/bolt_broken(datum/act/op/A)
	if(isnull(bolt))
		return OP_FAILED
	act_message(src, null, MSG_SELF(span_warning("You successfully break your [bolt].")), MSG_OTHERS(span_danger("%U% manages to break the [bolt]!")))
	bolt.malfunction = MALFUNCTION_PERMANENT
	return OP_OK

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
	set_vore_fullness_ex(list())
	set_vore_light_states(list())

/// Old attack_hand (never reached the gate or the default touch): dismounts, petting and punching. The cell is the take_power_part op.
/mob/living/silicon/robot/proc/robot_interaction_hand(datum/act/op/A, stance)
	var/mob/user = A.actor
	if(LAZYLEN(src?.buckled_mob_list()))
		//We're getting off!
		if(user in src?.buckled_mob_list())
			riding_datum?.force_dismount(user)
		//We're kicking everyone off!
		if(user == src)
			for(var/rider in src?.buckled_mob_list())
				riding_datum?.force_dismount(rider)
		return OP_OK

	add_fingerprint(user)

	if(ishuman(user) && !opened)
		hand_interact(user, stance)
	return OP_OK

/// The take_power_part op's condition: the chassis is open, its wiring tucked away, and there is a cell or the fried remains of its mount to take.
/mob/living/silicon/robot/proc/power_part_exposed(datum/act/A)
	if(!opened || wiresexposed)
		return FALSE
	if(cell)
		return TRUE
	var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
	return mount?.installed == ROBOT_PART_DESTROYED

/// The cell, or the fried remains of its mount, out to the hand (or the gripper) that took it.
/mob/living/silicon/robot/proc/power_part_taken(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/removed = null
	if(cell)
		removed = remove_cell()
		removed.add_fingerprint(user)
	else
		var/datum/robot_component/mount = get_component(ROBOT_SLOT_POWER)
		if(mount?.installed != ROBOT_PART_DESTROYED)
			return OP_REFUSED
		removed = mount.uninstall()
	op_deliver(A, removed)
	to_chat(user, span_filter_notice("You remove \the [removed]."))
	return OP_OK

/// Petting, punching, tapping and vore on a closed chassis, in `stance` (the touch interaction's).
/mob/living/silicon/robot/proc/hand_interact(mob/living/carbon/human/H, stance)
	switch(stance)
		if(I_HELP)
			if(grabbable)
				attempt_to_scoop(H)
			else if(client && !client.prefs.read_preference(/datum/preference/toggle/human/borg_petting)) // migrated pref
				act_message(H, src, others = span_notice("%U% reaches out for %T%, but quickly refrains from petting."))
			else
				act_message(H, src, others = span_notice("%U% pets %T%."))
		if(I_HURT)
			H.do_attack_animation(src)
			var/shreddamage = H.species.can_shred(H, FALSE, 15)
			if(shreddamage)
				generic_hit(src, H, shreddamage, "attacked")
			else
				play_sfx(src.loc, SFX_EFFECTS_BANG, 0.2)
				act_message(H, src, others = span_warning("%U% punches %T%, but doesn't leave a dent."))
		if(I_DISARM)
			H.do_attack_animation(src)
			play_sfx(src.loc, SFX_EFFECTS_CLANG2, 0.2)
			act_message(H, src, others = span_warning("%U% taps %T%."))
			if(hat && prob(10))
				var/obj/item/flying_hat = remove_hat(get_turf(src))
				flying_hat.throw_at_random(FALSE, 3, 2)
				act_message(src, null, others = span_danger("[flying_hat] goes flying off %U%'s head!"))
		if(I_GRAB)
			grab_vore_interact(H)

/mob/living/silicon/robot/proc/grab_vore_interact(mob/living/carbon/human/H)
	if(is_vore_predator(H) && H.devourable && src.feeding && src.devourable)
		open_request(src, /datum/prompt/choice, PROC_REF(grab_vore_chosen), answerer = H, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, title = "Feed or Eat", question = "Do you wish to eat [src] or feed yourself to them?", choices = list("Nevermind!", "Eat", "Feed"), buttons = TRUE, timeout = 0)
		return
	if(is_vore_predator(H) && src.devourable)
		open_request(src, /datum/prompt/choice, PROC_REF(grab_vore_chosen), answerer = H, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, title = "Eat?", question = "Do you wish to eat [src]?", choices = list("Nevermind!", "Eat"), buttons = TRUE, timeout = 0)
		return
	if(H.devourable && src.feeding)
		open_request(src, /datum/prompt/choice, PROC_REF(grab_vore_chosen), answerer = H, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, title = "Feed?", question = "Do you wish to feed yourself to [src]?", choices = list("Nevermind!", "Feed"), buttons = TRUE, timeout = 0)

/mob/living/silicon/robot/proc/grab_vore_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/carbon/human/H = A.request.answerer
	switch(A.answer.value)
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

// --- Hats (robots and drones) -----------------------------------------------------------------

/mob/living/silicon/robot/proc/place_on_head(obj/item/new_hat)
	if(hat)
		remove_hat(get_turf(src))
	rel_set(src, nameof(hat), new_hat)
	new_hat.forceMove(src)

/// Take the hat off, dropping it at `drop_loc`. Returns the hat.
/mob/living/silicon/robot/proc/remove_hat(atom/drop_loc)
	var/obj/item/old_hat = hat
	if(!old_hat)
		return null
	rel_take(src, nameof(hat))
	old_hat.forceMove(drop_loc)
	return old_hat

/// Old attack_robot: a cyborg clicking itself with an empty hand drops its hat (the "drop_hat" op).
/mob/living/silicon/robot/proc/hat_droppable(datum/act/op/A)
	return A.actor == src && !isnull(hat)

/// The old body ran ..() (attack_ai) first, so that runs first here too, as the AI-style Use (silicon interactions, then the default).
/mob/living/silicon/robot/proc/hat_drop_started(datum/act/op/A)
	actor_use(/datum/input_adapter/ai, A.actor, src)
	balloon_alert(A.actor, "dropping hat...")

/mob/living/silicon/robot/proc/hat_dropped(datum/act/op/A)
	if(isnull(hat))
		return OP_FAILED
	remove_hat(get_turf(src))
	balloon_alert(A.actor, "dropped hat")
	return OP_OK

/mob/living/silicon/robot/proc/installed_modules()
	robotact.tgui_interact(src)


/mob/living/silicon/robot/proc/radio_menu()
	radio.interact(src)//Just use the radio's Topic() instead of bullshit special-snowflake code

/mob/living/silicon/robot/proc/self_destruct()
	gib()
	return

/mob/living/silicon/robot/proc/UnlinkSelf()
	disconnect_from_ai()
	lawupdate = FALSE
	lockcharge = 0
	set_lockdown(0)
	canmove = 1
	scrambledcodes = TRUE
	//Disconnect it's camera so it's not so easily tracked.
	if(src.camera)
		src.camera.clear_all_networks()

/mob/living/silicon/robot/proc/ResetSecurityCodes()
	set category = VERB_CAT_ABILITIES_SILICON
	set name = "Reset Identity Codes"
	set desc = "Scrambles your security and identification codes and resets your current buffers. Unlocks you and permenantly severs you from your AI and the robotics console and will deactivate your camera system."

	UnlinkSelf()
	to_chat(src, span_filter_notice("Buffers flushed and reset. Camera system shutdown. All systems operational."))

/mob/living/silicon/robot/proc/SetLockdown(state = 1)
	// They stay locked down if their wire is cut.
	if(wire_is_cut(src, WIRE_BORG_LOCKED))
		state = 1
	if(state)
		throw_alert("locked", /atom/movable/screen/alert/locked)
	else
		clear_alert("locked")
	set_lockdown(state)
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
	proto_set(src, nameof(sprite_datum), null)
	resolve_sprite_datum()

/mob/living/silicon/robot/proc/repick_laws()
	return

/mob/living/silicon/robot/proc/add_robot_verbs()
	for(var/granted_path in robot_verbs_default)
		grant(src, granted_verb(granted_path), src)
	for(var/granted_path in silicon_subsystems)
		grant(src, granted_verb(granted_path), src)
	grant(src, robot_live(), src)
	if(CONFIG_GET(flag/allow_robot_recolor))
		grant(src, robot_recolour(), src)

/mob/living/silicon/robot/proc/remove_robot_verbs()
	for(var/granted_path in robot_verbs_default)
		revoke(src, granted_verb(granted_path), src)
	for(var/granted_path in silicon_subsystems)
		revoke(src, granted_verb(granted_path), src)
	revoke(src, robot_live(), src)
	if(CONFIG_GET(flag/allow_robot_recolor))
		revoke(src, robot_recolour(), src)

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
		unobserve(old_ai, /datum/notice/silicon_laws_changed, src)
		unobserve(old_ai, /datum/notice/qdeleting, src)
		rel_remove(old_ai, nameof(old_ai.connected_robots), src)
	rel_set(src, nameof(connected_ai), new_ai)
	if(new_ai)
		rel_add(new_ai, nameof(new_ai.connected_robots), src)
		global.observe(new_ai, /datum/notice/silicon_laws_changed, src, then(PROC_REF(on_master_laws_changed)))
		global.observe(new_ai, /datum/notice/qdeleting, src, then(PROC_REF(on_master_deleted)))
	log_runtime("ROBOT_LINK: [key_name(src)] master AI [old_ai ? key_name(old_ai) : "none"] -> [new_ai ? key_name(new_ai) : "none"].")
	return TRUE

/mob/living/silicon/robot/proc/on_master_laws_changed(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	if(lawupdate)
		sync()

/mob/living/silicon/robot/proc/on_master_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
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
	set_emagged(TRUE)
	robotact?.update_static_data_for_all_viewers()
	lawupdate = FALSE
	disconnect_from_ai(TRUE)
	clear_supplied_laws()
	clear_inherent_laws()
	rel_set(src, nameof(laws), new /datum/ai_laws/syndicate_override)
	var/time = time2text(world.realtime,"hh:mm:ss")
	GLOB.lawchanges.Add("[time] <B>:</B> [user.name]([user.key]) emagged [name]([key])")
	set_zeroth_law("Only [user.real_name] and people [user.p_they()] designate[user.p_s()] as being such are operatives.")
	message_admins("[key_name_admin(user)] emagged [key_name_admin(src)]. Laws overridden.")
	log_game("[key_name(user)] emagged [key_name(src)]. Laws overridden.")
	laws_changed()

/// The emag() capability's effect (CAPABILITIES(/mob/living/silicon/robot), library/mob/hands.dm). A branch that did nothing declines (the card goes on as an
/// ordinary item); a try that happened, a failed hack included, uses the card up by one.
/mob/living/silicon/robot/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(!opened)//Cover is closed
		if(!locked)
			to_chat(user, span_filter_notice("The cover is already unlocked."))
			return OP_DECLINE
		if(prob(90))
			to_chat(user, span_filter_notice("You emag the cover lock."))
			locked = FALSE
		else
			to_chat(user, span_filter_warning("You fail to emag the cover lock."))
			to_chat(src, span_filter_warning("Hack attempt detected."))
		if(shell) // A warning to Traitors who may not know that emagging AI shells does not slave them.
			to_chat(user, span_warning("[src] seems to be controlled remotely! Emagging the interface may not work as expected."))
		return OP_OK

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
		return OP_OK//Prevents the X has hit Y with Z message also you cant emag them twice
	if(wiresexposed)
		to_chat(user, span_filter_notice("You must close the panel first."))
		return OP_DECLINE

	if(shell) // AI shells cannot be emagged, so we try to make it look like a standard reset. Smart players may see through this, however.
		to_chat(user, span_danger("[src] is remotely controlled! Your emag attempt has triggered a system reset instead!"))
		log_game("[key_name(user)] attempted to emag an AI shell belonging to [key_name(src) ? key_name(src) : connected_ai]. The shell has been reset as a result.")
		module_reset()
		return OP_OK

	if(!prob(50))
		to_chat(user, span_filter_warning("You fail to hack [src]'s interface."))
		to_chat(src, span_filter_warning("Hack attempt detected."))
		return OP_OK

	subvert_laws(user)
	to_chat(user, span_filter_notice("You emag [src]'s interface."))
	play_subversion_sequence(user.real_name, user.p_their())
	return OP_OK

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
		after(src, delay, PROC_REF(play_subversion_sequence), with = list(operator_name, operator_their, step + 1))
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

/mob/living/silicon/robot/verb/rest_style()
	set name = "Switch Rest Style"
	set desc = "Select your resting pose."
	set category = VERB_CAT_IC_SETTINGS

	if(!sprite_datum || !sprite_datum.has_rest_sprites || sprite_datum.rest_sprite_options.len < 1)
		to_chat(src, span_notice("Your current appearance doesn't have any resting styles!"))
		set_rest_style("Default")
		return

	if(sprite_datum.rest_sprite_options.len == 1)
		to_chat(src, span_notice("Your current appearance only has a single resting style!"))
		set_rest_style("Default")
		return

	// A cancel picks "Default".
	open_request(src, /datum/prompt/choice, PROC_REF(rest_style_chosen), answerer = src, title = "Resting Pose", question = "Select resting pose", choices = sprite_datum.rest_sprite_options, buttons = TRUE, timeout = 0)

/mob/living/silicon/robot/proc/rest_style_chosen(datum/act/request/A)
	set_rest_style(A.answer ? A.answer.value : "Default")

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
		rel_add(GLOB.traitors, nameof(/datum/antagonist::current_antagonists), mind)
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

/mob/living/silicon/robot/ownership()
	. = ..()
	. += owns(nameof(hat), policy = OWN_SPILL)
	// on_destroy() still takes these apart in order: the MMI hands its mind on, the cell unhooks.
	// The module, radio, camera and components are deleted by phase 4, after the AI link and shell are undone.
	// A borg with a mind gives its MMI to the turf (mmi_ejects, set in on_destroy()); a mindless one's goes with it.
	. += owns(nameof(mmi), policy = OWN_SPILL, if_var = nameof(mmi_ejects), else_policy = OWN_CONTAINED)
	// A registered robot sprite, or the robot's private fallback default (copy-on-write).
	. += rel_one(nameof(sprite_datum), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)

/mob/living/silicon/robot/relations()
	. = ..()
	// The power mount (components[ROBOT_SLOT_POWER].wrapped) owns the cell; `cell` is its alias.
	. += rel_one(nameof(cell))

// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
TRACKED(/mob/living/silicon/robot, sight_mode)
TRACKED(/mob/living/silicon/robot, emagged)
TRACKED(/mob/living/silicon/robot, lockdown)

// ---- the wires (declared with the cyborg's capabilities, code/library/mob/hands.dm) ----


/mob/living/silicon/robot/proc/wire_lights()
	return list(
		"The LawSync light is [lawupdate ? "on" : "off"].",
		"The AI link light is [connected_ai ? "on" : "off"].",
		"The Camera light is [(camera && camera.status == 1) ? "on" : "off"].",
		"The lockdown light is [lockcharge ? "on" : "off"].")

/// The law wire cut syncs the laws one last time and stops the updates; mended, they resume (unless emagged).
/mob/living/silicon/robot/proc/lawcheck_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(!N.mended)
		if(lawupdate)
			to_chat(src, "LawSync protocol engaged.")
			lawsync()
			show_laws()
	else if(!lawupdate && !emagged)
		lawupdate = TRUE

/// The AI wire cut drops the cyborg's AI link.
/mob/living/silicon/robot/proc/ai_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(!N.mended)
		disconnect_from_ai()

/// The AI wire pulsed makes the cyborg pick an AI again.
/mob/living/silicon/robot/proc/ai_wire_pulsed(datum/act/A)
	reselect_ai_by_wire()

/mob/living/silicon/robot/proc/reselect_ai_by_wire()
	if(emagged)
		return
	var/mob/living/silicon/ai/picked = select_active_ai(src, src, PROC_REF(reselect_ai_by_wire), list())
	if(picked)
		connect_to_ai(picked)

/mob/living/silicon/robot/proc/camera_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(!isnull(camera) && !scrambledcodes)
		camera.status = N.mended

/mob/living/silicon/robot/proc/camera_wire_pulsed(datum/act/A)
	if(!isnull(camera) && camera.can_use() && !scrambledcodes)
		act_message(src, null, others = "%U%'s camera lense focuses loudly.")
		to_chat(src, "Your camera lense focuses loudly.")

/mob/living/silicon/robot/proc/lockdown_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	SetLockdown(!N.mended)

/mob/living/silicon/robot/proc/lockdown_wire_pulsed(datum/act/A)
	SetLockdown(!lockdown) // toggle

/// The water reserve a module's extinguishers refill from (station.dm sets it for the modules that have one).
/mob/living/silicon/robot
	var/datum/matter_synth/water_res

/// water res (a relation view: it reads null once the target is deleted).
/mob/living/silicon/robot/proc/water_res() as /datum/matter_synth
	return water_res

/mob/living/silicon/robot/proc/ex_reserve_refill()
	set name = "Refill Extinguisher"
	set category = VERB_CAT_OBJECT
	var/datum/matter_synth/water = water_res()
	for(var/obj/item/extinguisher/E in module.modules)
		if(E.reagents.total_volume < E.max_water)
			if(water && water.energy > 0)
				var/amount = E.max_water - E.reagents.total_volume
				if(water.energy < amount)
					amount = water.energy
				water.use_charge(amount)
				E.reagents.add_reagent(REAGENT_ID_WATER, amount)
				to_chat(src, span_filter_notice("You refill the extinguisher using your water reserves."))
			else
				to_chat(src, span_filter_notice("Insufficient water reserves."))
