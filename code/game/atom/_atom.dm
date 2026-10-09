/**
 * The base type for nearly all physical objects in SS13

 * Lots and lots of functionality lives here, although in general we are striving to move
 * as much as possible to the components/elements system
 */
/atom
	layer = TURF_LAYER //This was here when I got here. Why though?
	var/level = 2
	var/flags = NONE
	// was_bloodied, blood_color, fluorescent are the forensic_* vars (code/datums/sparse_vars/forensics.dm)
	var/pass_flags = 0
	var/throwpass = 0
	var/germ_level = GERM_LEVEL_AMBIENT // The higher the germ level, the more germ on the atom.
	var/simulated = TRUE //filter for actions - used by lighting overlays
	// atom_say_verb removed (no subtype ever overrode it; inlined to "says" in atom_say)
	var/bubble_icon = "normal" ///what icon the atom uses for speechbubbles
	var/datum/forensics_crime/forensic_data

	EXPIRY_TMP_DECLARE(last_bumped)

	///Chemistry.
	var/datum/reagents/reagents = null

	//var/chem_is_open_container = 0
	// replaced by OPENCONTAINER flags and atom/proc/is_open_container()
	///Chemistry.

	// Overlays
	///Our local copy of (non-priority) overlays without byond magic. Use procs in SSoverlays to manipulate
	var/tmp/list/our_overlays
	///Overlays that should remain on top and not normally removed when using cut_overlay functions, like c4.
	/// A list, or a single overlay when there is only one (see add_overlay()).
	var/tmp/priority_overlays
	///vis overlays managed by SSvis_overlays to automaticaly turn them like other overlays
	var/tmp/list/managed_vis_overlays

	//Detective Work, used for the duplicate data points kept in the scanners
	var/tmp/list/original_atom
	// Track if we are already had initialize() called to prevent double-initialization.
	//var/initialized = FALSE // using the atom flags

	// chat_color, chat_color_name, chat_color_darkened moved to GLOB sparse maps in atom_var_components.dm
	//! Colors
	/**
	 * used to store the different colors on an atom
	 *
	 * its inherent color, the colored paint applied on it, special color effect etc...
	 */
	var/list/atom_colours
	// update_on_z moved to GLOB.update_on_z_by_atom (sparse map).
	// Saves the var entry from every /atom subtype's init table.
	// Use SET_UPDATE_ON_Z / GET_UPDATE_ON_Z macros (see observer_listener helpers).

	/// Radiation insulation types
	var/rad_insulation = RAD_NO_INSULATION
	/// MAT_* name this atom's radiation shielding derives from (apply_rad_shield_material()), or null.
	var/rad_shield_material
	/// Thickness of that shielding in mm.
	var/rad_shield_thickness_mm = 0


/atom/Destroy()
	// ---- L2 lifecycle: leave the live world (state.md section 6). ----
	// The only L2 line in this proc; the containment ledger (C1) owns the rest.
	// dematerialize() must run before release_heat_body(): it drops this
	// atom's rule bindings (dq_rules_on_dematerialize()), which cancel their
	// live heat watches against the still-valid body handle. Releasing the
	// body first frees/recycles its slot in Rust while those watches are
	// still registered on it, so the later cancel either no-ops against a
	// dead handle or -- worse -- lands on whatever body reused the slot,
	// leaving a stale watch that can swallow or misroute a later object's
	// threshold crossing (e.g. the overheating rule never firing).
	dematerialize()
	// ---- end L2 ----
	caps_destroy(src)
	if(!isnull(heat_body))
		release_heat_body()
	if(reagents)
		rel_clear(src, nameof(reagents))
	if(light)
		rel_clear(src, nameof(light))
	if(forensic_data)
		rel_clear(src, nameof(forensic_data))
	// Checking length(overlays) before cutting has significant speed benefits
	if (length(overlays))
		overlays.Cut()
	if (length(our_overlays))
		our_overlays.Cut()
	if (islist(priority_overlays))
		var/list/prio = priority_overlays
		prio.Cut()
	priority_overlays = null
	if (length(managed_vis_overlays))
		rel_clear(src, nameof(managed_vis_overlays))
	if (length(original_atom))
		original_atom.Cut()
	return ..()

/// Shift this atom's surface germ count (never below 0). Organs override it
/// with their infection clamp. The one writer for reagents and cleaning (P2-K5).
/atom/proc/adjust_germ_level(amount)
	germ_level = max(0, germ_level + amount)

/atom/proc/reveal_blood()
	return

/atom/proc/assume_air(datum/gas_mixture/giver)
	return null

/atom/proc/remove_air(amount)
	return null

/atom/proc/return_air()
	if(loc)
		return loc.return_air()
	else
		return null

/atom/proc/Bumped(AM as mob|obj)

	PUBLISH_LEGACY(src, /datum/notice/atom_bumped, AM)

// Convenience proc to see if a container is open for chemistry handling
// returns true if open
// false if closed
/atom/proc/is_open_container()
	var/datum/capability/lib/reagent_container/C = cap_of(src, CAP_REAGENT_CONTAINER)
	if(C)
		return !C.sealed && (!C.lid || reagent_container_lid_open(src))
	return !!(flags & OPENCONTAINER) // ALLOW(reads): a container without the capability is open by its flag; a condition that asks reads it when it is asked

/*//Convenience proc to see whether a container can be accessed in a certain way.

	proc/can_subract_container()
		return flags & EXTRACT_CONTAINER

	proc/can_add_container()
		return flags & INSERT_CONTAINER
*/

// Used to be for the PROXMOVE flag, but that was terrible, so instead it's just here as a stub for
// all the atoms that still have the proc, but get events other ways.
/atom/proc/HasProximity(turf/T, atom/movable/arrived, old_loc) // arrived: the atom itself (not a handle)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// Hooked on the turfs sense_proximity() watches: something entered one of them.
/atom/proc/on_proximity_turf_entered(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/turf/source = A.target
	var/datum/notice/observer_turf_entered/event = A
	HasProximity(source, event.arrived, event.old_loc)

//Register listeners on turfs in a certain range. Entries call HasProximity(turf, arrived, old_loc);
// `callback` is kept for the callers' readability and must be HasProximity.
/atom/proc/sense_proximity(range = 1, callback)
	ASSERT(callback)
	ASSERT(isturf(loc))
	var/list/turfs = trange(range, src)
	for(var/turf/T as anything in turfs)
		observe(T, /datum/notice/observer_turf_entered, src, then(PROC_REF(on_proximity_turf_entered)))

//Unregister from prox listening in a certain range. You should do this BEFORE you move, but if you
// really can't, then you can set the center where you moved from.
/atom/proc/unsense_proximity(range = 1, callback, center)
	ASSERT(isturf(center) || isturf(loc))
	var/list/turfs = trange(range, center ? center : src)
	for(var/turf/T as anything in turfs)
		unobserve(T, /datum/notice/observer_turf_entered, src)


/atom
	/// EMP_PROTECT_* flags this atom always has (was the empprotection element).
	var/emp_protection_flags = NONE

/atom/proc/emp_act(severity, recursive)
	SHOULD_CALL_PARENT(TRUE)
	recursive++
	if(recursive > 5) //After a certain depth, we're just going to assume that it's too insulated to be EMP'd.
		return
	// Listeners add what they shield (adjusts_with writes the act's protection): the flags of every one combine with the atom's own.
	var/protection = emp_protection_flags & EMP_PROTECT_ALL
	var/datum/act/emp/pulse = ACT_TRY(src, emp, severity, protection)
	if(!pulse)
		return protection
	protection = ACT_FINAL(pulse, protection, protection)
	act_done(pulse)
	if(!(protection & EMP_PROTECT_WIRES))
		wires_emp(src)

	if(!(protection & EMP_PROTECT_CONTENTS))
		for(var/atom/A in contents)
			A.emp_act(severity, recursive)

	PUBLISH_LEGACY(src, /datum/notice/atom_emp_act, severity, protection)
	return protection

/atom/proc/bullet_act(obj/item/projectile/P, def_zone)
	var/datum/act/shoot/round = ACT_TRY(src, shoot, P, def_zone)
	if(!round)
		return
	act_done(round)
	if(reflect_projectile(P)) // REFLECTS (systems.md section 12)
		return PROJECTILE_CONTINUE

	P.on_hit(src, 0, def_zone)
	. = 0
	if(!QDELETED(src))
		projectile_damage(P, def_zone)

/// The projectile adapter: how much of a round this atom catches. Types whose
/// shape changes that (grilles, girders, barricades) override this, not bullet_act().
/atom/proc/projectile_damage(obj/item/projectile/P, def_zone)
	return receive_projectile(P, def_zone)

// Called when a blob expands onto the tile the atom occupies.
/atom/proc/blob_act(obj/structure/blob/B)
	receive_blob(B)

/atom/proc/in_contents_of(container)//can take class or object instance as argument
	if(ispath(container))
		if(istype(loc, container))
			return 1
	// ALLOW(spatial): container is an arbitrary caller-supplied object or list
	else if(src in container)
		return 1
	return

/*
 *	atom/proc/search_contents_for(path,list/filter_path=null)
 * Recursevly searches all atom contens (including contents contents and so on).
 *
 * ARGS: path - search atom contents for atoms of this type
 *	   list/filter_path - if set, contents of atoms not of types in this list are excluded from search.
 *
 * RETURNS: list of found atoms
 */

/atom/proc/search_contents_for(path,list/filter_path=null)
	var/list/found = list()
	for(var/atom/A in contents_of(src))
		if(istype(A, path))
			found += A
		if(filter_path)
			var/pass = 0
			for(var/type in filter_path)
				pass |= istype(A, type)
			if(!pass)
				continue
		if(contents_count(A))
			found += A.search_contents_for(path,filter_path)
	return found

/atom/proc/get_examine_desc()
	return desc

//All atoms
/atom/proc/examine(mob/user, infix = "", suffix = "")
	SHOULD_CALL_PARENT(TRUE)
	//This reformat names to get a/an properly working on item descriptions when they are bloody
	var/f_name = "\a [src][infix]."
	if(forensic_data?.has_blooddna() && !istype(src, /obj/effect/decal))
		if(gender == PLURAL)
			f_name = "some "
		else
			f_name = "a "
		if(dq_get_blood_color(src) != SYNTH_BLOOD_COLOUR)
			f_name += "[span_danger("blood-stained")] [name][infix]!"
		else
			f_name += "oil-stained [name][infix]."

	var/borg = "" // Borg grippers say if the item can be gripped
	if(isrobot(user) && isitem(src))
		borg = "None of your grippers can hold this."
		var/mob/living/silicon/robot/R = user
		if(R.module?.modules)
			for(var/obj/item/gripper/G in R.module.modules)
				if(!dq_constraint_refusal(G, CONSTRAINT_HOLD, src, R))
					borg = span_boldnotice("\The [G]") + span_notice(" can hold this.")
					break

	var/list/output = list("[icon2html(src,user.client)] That's [f_name] [suffix] [borg]", get_examine_desc())
	if(uses_integrity && get_integrity() < max_integrity)
		dq_rules_settle(src) // a pending integrity wake lands before we read the band
	if(damage_band)
		output += damage_flavour_text(damage_band)

	output += examine_lines(user)
	PUBLISH_LEGACY(src, /datum/notice/examine, user, output)
	return output

// Don't make these call bicon or anything, these are what bicon uses. They need to return an icon.
/atom/proc/examine_icon()
	return src // 99% of the time just returning src will be sufficient. More complex examine icon things are available where they are needed

// called by mobs when e.g. having the atom as their machine, pulledby, loc (AKA mob being inside the atom) or buckled var set.
// see code/modules/mob/mob_movement.dm for more.
/atom/proc/relaymove()
	return

//called to set the atom's dir and used to add behaviour to dir-changes
/atom/proc/set_dir(new_dir)
	SHOULD_CALL_PARENT(TRUE)
	PUBLISH_LEGACY(src, /datum/notice/atom_dir_change, dir, new_dir)
	var/old_dir = dir
	dir = new_dir
	// A drawn type that reads dir redraws, and so does a look that watches this atom (dir is a tracked read of every look); an atom nothing draws or watches pays one var read.
	if((rx?.look_key || rel_watchers) && old_dir != new_dir)
		tracked_changed(src, nameof(dir))
SETTER(/atom, dir)

/// The engine's look applies a dir through this (the engine does not reach the atom layer): set_dir() on every atom.
/atom/look_set_dir(new_dir)
	set_dir(new_dir)

/// Density is a tracked base var (G8): this is its only writer. A change publishes nameof(density) to its readers
/// and, as a bridge, raises the channel the type's declared field names (machinery_fields.dm).
/atom/proc/set_density(new_density)
	new_density = !!new_density // Sanitize to be strictly 0 or 1
	if(density == new_density)
		return FALSE
	density = new_density
	tracked_bridged_changed(src, nameof(density))
	return TRUE
SETTER(/atom, density)

// Called to set the atom's invisibility and usd to add behavior to invisibility changes.
/atom/proc/set_invisibility(new_invisibility)
	if(invisibility == new_invisibility)
		return FALSE
	invisibility = new_invisibility
	return TRUE

/atom/proc/ex_act(strength = 3)
	var/datum/act/explode/blast = ACT_TRY(src, explode, strength)
	if(!blast)
		return COMPONENT_IGNORE_EXPLOSION
	act_done(blast)
	return NONE

/**
 * Respond to fire being used on our atom
 *
 * Default behaviour is to publish /datum/notice/atom_fire_act and return
 */
/atom/proc/fire_act(exposed_temperature, exposed_volume)
	PUBLISH_LEGACY(src, /datum/notice/atom_fire_act, exposed_temperature, exposed_volume)
	return FALSE

/**
 * Puts out a fire on this atom. Overrides (a burning object's) end their burning state and call the parent.
 */
/atom/proc/extinguish()
	SHOULD_CALL_PARENT(TRUE)
	return NONE

// Returns an assoc list of RCD information.
// Example would be: list(RCD_VALUE_MODE = RCD_DECONSTRUCT, RCD_VALUE_DELAY = 50, RCD_VALUE_COST = RCD_SHEETS_PER_MATTER_UNIT * 4)
// This occurs before rcd_act() is called, and it won't be called if it returns FALSE.
/atom/proc/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	return FALSE

/atom/proc/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	return

/atom/proc/occult_act(mob/living/user)
	return

/atom/proc/melt()
	return

// Previously this was defined both on /obj/ and /turf/ seperately.  And that's bad.
/atom/proc/update_icon()
	// A DECLARE_APPEARANCE type needs no override (code/datums/lifecycle/declarations.dm).
	decl_appearance_apply()


/atom/proc/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	PUBLISH_LEGACY(src, /datum/notice/hitby, source, throwingdatum)
	thrown_damage(source, throwingdatum)

/// The thrown-impact adapter. Types whose shape changes how hard a throw lands
/// (reinforced windows, low walls) override this, not hitby().
/atom/proc/thrown_damage(atom/movable/source, datum/thrownthing/throwingdatum)
	return receive_thrown(source, throwingdatum)

//returns 1 if made bloody, returns 0 otherwise
/atom/proc/add_blood(mob/living/carbon/human/M as mob)

	if(flags & NOBLOODY)
		return 0

	dq_set_was_bloodied(src, TRUE)
	if(!dq_get_blood_color(src))
		dq_set_blood_color(src, SYNTH_BLOOD_COLOUR)
	if(istype(M))
		if (!istype(M.dna, /datum/dna))
			rel_set(M, nameof(M.dna), new /datum/dna(null))
			M.dna.real_name = M.real_name
		M.check_dna()
		dq_set_blood_color(src, M.species.get_blood_colour(M))
	. = 1
	return 1

/atom/proc/on_rag_wipe(obj/item/reagent_containers/glass/rag/R)
	wash(CLEAN_WASH)
	R.reagents.splash(src, 1)

/atom/proc/get_global_map_pos()
	if(!islist(GLOB.global_map) || isemptylist(GLOB.global_map)) return
	var/cur_x = null
	var/cur_y = null
	var/list/y_arr = null
	for(cur_x = 1, cur_x <= GLOB.global_map.len, cur_x++)
		y_arr = GLOB.global_map[cur_x]
		cur_y = y_arr.Find(src.z)
		if(cur_y)
			break
	if(cur_x && cur_y)
		return list("x"=cur_x,"y"=cur_y)
	else
		return 0

/atom/proc/checkpass(passflag)
	return (pass_flags&passflag)

/proc/isinspace(atom/source)
	if(istype(get_turf(source), /turf/space))
		return 1
	else
		return 0

// Show a message to all mobs and objects in sight of this atom
// Use for objects performing visible actions
// message is output to anyone who can see, e.g. "The [src] does something!"
// blind_message (optional) is what blind people will hear e.g. "You hear something!"
/atom/proc/visible_message(message, blind_message, list/exclude_mobs, range = world.view, runemessage = "<span style='font-size: 1.5em'>👁</span>")

	var/list/see
	if(isbelly(loc))
		var/obj/belly/B = loc
		see = B.get_mobs_and_objs_in_belly()
	else
		see = get_mobs_and_objs_in_view_fast(get_turf(src), range, remote_ghosts = FALSE)

	var/list/seeing_mobs = see["mobs"]
	var/list/seeing_objs = see["objs"]
	if(LAZYLEN(exclude_mobs))
		seeing_mobs -= exclude_mobs

	for(var/obj/O as anything in seeing_objs)
		O.show_message(message, VISIBLE_MESSAGE, blind_message, AUDIBLE_MESSAGE)
	for(var/mob/M as anything in seeing_mobs)
		if(M.see_invisible >= invisibility && MOB_CAN_SEE_PLANE(M, plane))
			M.show_message(message, VISIBLE_MESSAGE, blind_message, AUDIBLE_MESSAGE)
			if(runemessage != -1)
				M.create_chat_message(src, "[runemessage]", FALSE, list("emote"), audible = FALSE)
		else if(blind_message)
			M.show_message(blind_message, AUDIBLE_MESSAGE)

// Show a message to all mobs and objects in earshot of this atom
// Use for objects performing audible actions
// message is the message output to anyone who can hear.
// deaf_message (optional) is what deaf people will see.
// hearing_distance (optional) is the range, how many tiles away the message can be heard.
/atom/proc/audible_message(message, deaf_message, hearing_distance, radio_message, runemessage)

	var/range = hearing_distance || world.view
	var/list/hear = get_mobs_and_objs_in_view_fast(get_turf(src),range,remote_ghosts = FALSE)

	var/list/hearing_mobs = hear["mobs"]
	var/list/hearing_objs = hear["objs"]

	if(radio_message)
		for(var/obj/O as anything in hearing_objs)
			O.hear_talk(src, list(new /datum/multilingual_say_piece(GLOB.all_languages["Noise"], radio_message)), null)
	else
		for(var/obj/O as anything in hearing_objs)
			O.show_message(message, AUDIBLE_MESSAGE, deaf_message, VISIBLE_MESSAGE)

	for(var/mob/M as anything in hearing_mobs)
		var/msg = message
		M.show_message(msg, AUDIBLE_MESSAGE, deaf_message, VISIBLE_MESSAGE)
		if(runemessage != -1)
			M.create_chat_message(src, "[runemessage || message]", FALSE, list("emote"))

/atom/movable/proc/dropInto(atom/destination)
	while(istype(destination))
		var/atom/drop_destination = destination.onDropInto(src)
		if(!istype(drop_destination) || drop_destination == destination)
			return forceMove(destination)
		destination = drop_destination
	return moveToNullspace()

/atom/proc/onDropInto(atom/movable/AM)
	return // If onDropInto returns null, then dropInto will forceMove AM into us.

/atom/movable/onDropInto(atom/movable/AM)
	return loc // If onDropInto returns something, then dropInto will attempt to drop AM there.

/atom/proc/InsertedContents()
	return contents

/atom/proc/get_gravity(turf/T)
	if(!T || !isturf(T))
		T = get_turf(src)
	if(istype(T, /turf/space)) // Turf never has gravity
		return FALSE
	var/area/A = get_area(T)
	if(A && A.get_gravity())
		return TRUE
	return FALSE

/atom/proc/is_incorporeal()
	return FALSE

/atom/proc/drop_location()
	var/atom/L = loc
	if(!L)
		return null
	return L.AllowDrop() ? L : L.drop_location()

/atom/proc/AllowDrop()
	return FALSE

/atom/proc/get_nametag_name(mob/user)
	return name

/atom/proc/get_nametag_desc(mob/user)
	return "" //Desc itself is often too long to use

/atom/proc/atom_say(message)
	if(!message)
		return
	var/list/speech_bubble_hearers = list()
	for(var/mob/M in get_mobs_in_view(7, src))
		// was [atom_say_verb], inlined since no subtype ever overrode it
		M.show_message(span_npc_say(span_name("[src]") + " says, \"[message]\""), 2, null, 1)
		if(M.client)
			speech_bubble_hearers += M.client

	if(length(speech_bubble_hearers))
		var/image/I = generate_speech_bubble(src, "[bubble_icon][say_test(message)]", FLY_LAYER)
		I.appearance_flags = APPEARANCE_UI_IGNORE_ALPHA
		flick_overlay(I, speech_bubble_hearers, 30)

/atom/proc/speech_bubble(bubble_state = "", bubble_loc = src, list/bubble_recipients = list())
	return

/atom/Entered(atom/movable/AM, atom/old_loc)
	. = ..()
	op_moved(AM, src)
	PUBLISH_LEGACY(AM, /datum/notice/movable_attempted_move, old_loc, AM.loc)
	PUBLISH_LEGACY(src, /datum/notice/atom_entered, AM, old_loc)
	if(rel_watchers)
		look_neighbour_moved(src, AM)
	PUBLISH_LEGACY(AM, /datum/notice/atom_entering, src, old_loc)
	RANGE_WATCH(src, RANGE_ENTERED, AM, old_loc)

/atom/Exit(atom/movable/AM, atom/new_loc)
	. = ..()

/atom/Exited(atom/movable/AM, atom/new_loc)
	. = ..()
	op_moved(AM, src)
	PUBLISH_LEGACY(src, /datum/notice/atom_exited, AM, new_loc)
	if(rel_watchers)
		look_neighbour_moved(src, AM)
	RANGE_WATCH(src, RANGE_EXITED, AM, new_loc)

/atom/proc/interact(mob/user)
	return

// Purpose: Determines if the object can pass this atom.
// Called by: Movement.
// Inputs: The moving atom, target turf.
// Outputs: Boolean if can pass.
// Airflow and ZAS zones now uses CanZASPass() instead of this proc.
/atom/proc/CanPass(atom/movable/mover, turf/target)
	return !density


//! ## Atom Colour Priority System
/**
 * A System that gives finer control over which atom colour to colour the atom with.
 * The "highest priority" one is always displayed as opposed to the default of
 * "whichever was set last is displayed"
 */

/// Adds an instance of colour_type to the atom's atom_colours list
/// atom_colours is interned (intern_list): atoms with the same colours share one
/// read-only list, so every change builds a new list.
/atom/proc/add_atom_colour(coloration, colour_priority)
	if(!coloration)
		return
	if(colour_priority > COLOUR_PRIORITY_AMOUNT)
		return
	var/list/new_colours = length(atom_colours) ? atom_colours.Copy() : list()
	if(new_colours.len < COLOUR_PRIORITY_AMOUNT)
		new_colours.len = COLOUR_PRIORITY_AMOUNT //four priority levels currently.
	new_colours[colour_priority] = coloration
	atom_colours = intern_list(new_colours)
	update_atom_colour()

/// Removes an instance of colour_type from the atom's atom_colours list
/atom/proc/remove_atom_colour(colour_priority, coloration)
	if(!atom_colours) // Nothing to remove; don't allocate the priority list just to find that out.
		update_atom_colour()
		return
	if(colour_priority > atom_colours.len)
		return
	if(coloration && atom_colours[colour_priority] != coloration)
		return //if we don't have the expected color (for a specific priority) to remove, do nothing
	var/list/new_colours = atom_colours.Copy()
	new_colours[colour_priority] = null
	atom_colours = intern_list(new_colours)
	update_atom_colour()

/// Resets the atom's color to null, and then sets it to the highest priority colour available
/atom/proc/update_atom_colour()
	color = null
	for(var/C in atom_colours)
		if(islist(C))
			var/list/L = C
			if(L.len)
				color = L
				return
		else if(C)
			color = C
			return

///Passes Stat Browser Panel clicks to the game and calls client click on an atom

/atom/proc/topic_statpanel_click(datum/act/op/A, href_statpanel_item_click, href_statpanel_item_shiftclick, href_statpanel_item_ctrlclick, href_statpanel_item_altclick)
	var/mob/user = A.actor
	if(!user?.client)
		return
	var/list/paramslist = list()
	switch(href_statpanel_item_click)
		if("left")
			paramslist["left"] = "1"
		if("right")
			paramslist["right"] = "1"
		if("middle")
			paramslist["middle"] = "1"
		else
			return
	if(href_statpanel_item_shiftclick)
		paramslist["shift"] = "1"
	if(href_statpanel_item_ctrlclick)
		paramslist["ctrl"] = "1"
	if(href_statpanel_item_altclick)
		paramslist["alt"] = "1"
	user.client.Click(src, loc, null, list2params(paramslist))
	return TRUE

GLOBAL_LIST_EMPTY(icon_dimensions)

/// get_oversized_icon_offsets() for an unshifted atom (shared; callers only read it).
GLOBAL_LIST_INIT(zero_icon_offsets, list("x" = 0, "y" = 0))

/atom/proc/get_oversized_icon_offsets()
	if (pixel_x == 0 && pixel_y == 0)
		return GLOB.zero_icon_offsets
	var/list/icon_dimensions = get_icon_dimensions(icon)
	var/icon_width = icon_dimensions["width"]
	var/icon_height = icon_dimensions["height"]
	return list(
		"x" = icon_width > world.icon_size && pixel_x != 0 ? (icon_width - world.icon_size) * 0.5 : 0,
		"y" = icon_height > world.icon_size /*&& pixel_y != 0*/ ? (icon_height - world.icon_size) * 0.5 : 0, // we don't have pixel_y in use
	)

/// Returns the src and all recursive contents as a list.
/atom/proc/get_all_contents(ignore_flag_1)
	. = list(src)
	var/i = 0
	while(i < length(.))
		var/atom/checked_atom = .[++i]
		if(checked_atom.flags & ignore_flag_1)
			continue
		if(checked_atom?.latent_contents_enabled())
			checked_atom.latent_materialize_all() // a search needs real things (C5)
		. += checked_atom.contents

/// Identical to get_all_contents but returns a list of atoms of the type passed in the argument.
/atom/proc/get_all_contents_type(type)
	var/list/processing_list = list(src)
	. = list()
	var/i = 0
	while(i < length(processing_list))
		var/atom/checked_atom = processing_list[++i]
		if(checked_atom?.latent_contents_enabled())
			checked_atom.latent_materialize_all() // a search needs real things (C5)
		processing_list += checked_atom.contents
		if(istype(checked_atom, type))
			. += checked_atom

/**
*	Respond to our atom being checked by a virus extrapolator.
*
*	Default behaviour is to return an empty list (overrides populate it)
*
*	Returns a list of viruses in the atom.
*	Include EXTRAPOLATOR_SPECIAL_HANDLED in the list if the extrapolation act has been handled by this proc or a signal, and should not be handled by the extrapolator itself.
*/
/atom/proc/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run = FALSE)
	. = list(EXTRAPOLATOR_RESULT_DISEASES = list()) // ALLOW(sys_const_list_alloc): fresh result container that overrides fill via EXTRAPOLATOR_ACT_ADD_DISEASES(., ...)

/**
*	Wash this atom
*
*	This will clean it off any temporary stuff like blood. Override this in your item to add custom cleaning behavior.
*	Returns true if any washing was necessary and thus performed
*	Arguments:
*	clean_types: any of the CLEAN_ constants
*/
/atom/proc/wash(clean_types)
	SHOULD_CALL_PARENT(TRUE)

	. = FALSE

	// Basically "if has washable coloration"
	if(length(atom_colours) >= WASHABLE_COLOUR_PRIORITY && atom_colours[WASHABLE_COLOUR_PRIORITY])
		remove_atom_colour(WASHABLE_COLOUR_PRIORITY)

	forensic_data?.wash(clean_types)
	dq_set_blood_color(src, null)
	germ_level = 0
	dq_set_fluorescent(src, 0)

/// Its icon state (after() target for a state that reverts, like a flash of a sprite).
/atom/proc/set_icon_state(new_state)
	icon_state = new_state

/// Its base colour, under any colour layers (a debug or effect tint that reverts later).
/atom/proc/set_base_color(new_color)
	color = new_color
