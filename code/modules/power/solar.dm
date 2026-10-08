// # define SOLAR_MAX_DIST 40 // Removal
#define SOLAR_AUTO_START_NO     0 // Will never start itself.
#define SOLAR_AUTO_START_YES    1 // Will always start itself.
#define SOLAR_AUTO_START_CONFIG 2 // Will start itself if config allows it (default is no).

GLOBAL_VAR_INIT(solar_gen_rate, 1500)

/obj/machinery/power/solar
	name = "solar panel"
	desc = "A solar electrical generator."
	icon = 'icons/obj/power.dmi'
	icon_state = "sp_base"
	anchored = TRUE
	density = TRUE
	unacidable = TRUE
	use_power = USE_POWER_OFF
	idle_power_usage = 0
	active_power_usage = 0
	var/id = 0
	/// Power this panel last reported to its controller (was the controller's connected_panels[panel] value).
	var/controller_supply = 0
	// 12 integrity with a 2-point "broken" buffer: ~10 damage cracks it (atom_break),
	// then any further hit shatters it into shards (atom_destruction).
	max_integrity = 12
	integrity_failure = 0.167
	var/obscured = 0
	var/sunfrac = 0
	var/adir = SOUTH // actual dir
	var/ndir = SOUTH // target dir
	var/turn_angle = 0
	var/tmp/obj/machinery/power/solar_control/control
	var/glass_type = /obj/item/stack/material/glass
	var/SOLAR_MAX_DIST = 60 // ours are >40 away
TRACKED(/obj/machinery/power/solar, adir)

/obj/machinery/power/solar/drain_power()
	return -1

MSG_DEF(solar/glass_off, "You take the glass off the solar panel.", "%U% takes the glass off the solar panel.")

// A solar panel (doc/rewrite/final_api.html section 16): linked to a solar control computer on its network, it supplies solar_gen_rate W times
// its exposure (cos^2 of its angle off the sun, 0 past 90 degrees, 0 obscured), summed by the controller into one persistent supply. A crowbar
// takes the glass off; a hostile swing with anything strikes it.
CAPABILITIES(/obj/machinery/power/solar)
	climb()
	ref_one(nameof(control), /obj/machinery/power/solar_control)
	op("remove_glass", tool(TOOL_CROWBAR), label("Take the glass off"), wait(2 SECONDS), says(MSG(solar/glass_off)), then(PROC_REF(glass_removed)))
	param(nameof(glass_type), pos = 1)

// ALLOW(init/INSTANCE_STATE): a panel in reinforced glass is twice as tough
/obj/machinery/power/solar/Initialize(mapload)
	. = ..()
	if(glass_type == /obj/item/stack/material/glass/reinforced) //if the panel is in reinforced glass
		max_integrity *= 2
		update_integrity(max_integrity)

/// `connect_to_network()` needs `vg_entity` bound, which only happens once
/// `on_materialize()`'s `vg_bind()` runs -- see the base class override's
/// docs (`code/modules/power/power.dm`).
/obj/machinery/power/solar/on_materialize()
	. = ..()
	connect_to_network()

// leaves its solar control computer.
/obj/machinery/power/solar/on_destroy(force)
	unset_control() //remove from control computer
	..()

//set the control of the panel to a given computer if closer than SOLAR_MAX_DIST
/obj/machinery/power/solar/proc/set_control(obj/machinery/power/solar_control/SC)
	ASSERT(!control())
	if(SC && (get_dist(src, SC) > SOLAR_MAX_DIST))
		return 0
	rel_set(src, nameof(control), SC)
	return 1

//set the control of the panel to null and removes it from the control list of the previous control computer if needed
/obj/machinery/power/solar/proc/unset_control()
	if(control())
		control().remove_panel(src)
	rel_clear(src, nameof(control))

/// The glass is off: an anchored assembly and the sheets are left.
/obj/machinery/power/solar/proc/glass_removed(datum/act/op/A)
	var/obj/item/solar_assembly/S = new(loc)
	S.set_anchored(TRUE)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	replace_with(src, glass_type, 2)
	return OP_OK

// First time integrity bottoms out, the panel flips to its broken (cracked) state.
/obj/machinery/power/solar/atom_break(damage_flag)
	. = ..()
	if(.)
		broken()

// Once broken, further damage shatters it into shards.
/obj/machinery/power/solar/atom_destruction(damage_flag)
	new /obj/item/material/shard(src.loc)
	new /obj/item/material/shard(src.loc)
	return ..()

/obj/machinery/power/solar/draw(datum/look/look)
	..()
	if(broken_now())
		look.overlay("solar_panel-b")
	else
		look.overlay("solar_panel")
		look.set_dir(angle2dir(adir))

//calculates the fraction of the sun that the panel recieves
/obj/machinery/power/solar/proc/update_solar_exposure()
	if(!GLOB.sun)
		return
	if(obscured)
		sunfrac = 0
		return

	//find the smaller angle between the direction the panel is facing and the direction of the sun (the sign is not important here)
	var/source_angle = SSsolars.get_solar_angle(get_turf(src))
	var/p_angle = min(abs(adir - source_angle), 360 - abs(adir - source_angle))
	if(p_angle > 90) // if facing more than 90deg from sun, zero output
		sunfrac = 0
		return

	sunfrac = cos(p_angle) ** 2
	//isn't the power recieved from the incoming light proportionnal to cos(p_angle) (Lambert's cosine law) rather than cos(p_angle)^2 ?

/obj/machinery/power/solar/proc/get_power_supplied()
	if(broken_now())
		return 0
	if(!GLOB.sun || !control())
		return 0  //if there's no sun or the panel is not linked to a solar control computer, no need to proceed
	if(!power_region || power_region != control().power_region)
		return 0 // We aren't connected to the controller
	if(obscured)
		return 0 //get no light from the sun, so don't generate power
	return GLOB.solar_gen_rate * sunfrac

/obj/machinery/power/solar/proc/broken()
	unset_control()
	climb_shake_off(src, null)
	return

//trace towards sun to see if we're in shadow
/obj/machinery/power/solar/proc/occlusion()
	var/turf/our_t = get_turf(src)
	var/datum/planet/our_planet
	if(!our_t || our_t.z > length(SSplanets.z_to_planet) || !SSplanets.z_to_planet[our_t.z])
		// If we are NOT on a planet, we check toward the edge of the map, otherwise we're going to assume the sun is above us on a planet
		var/ax = x		// start at the solar panel
		var/ay = y
		var/turf/T = null

		for(var/i = 1 to 20)		// 20 steps is enough
			ax += GLOB.sun.dx	// do step
			ay += GLOB.sun.dy

			T = locate( round(ax,0.5),round(ay,0.5),z)

			if(!T || T.x == 1 || T.x==world.maxx || T.y==1 || T.y==world.maxy)		// not obscured if we reach the edge
				break

			if(T.opacity)			// if we hit a solid turf, panel is obscured
				obscured = 1
				return
	else
		// If we are on a planet, get it for later so we can change the intensity of the light we recieve
		our_planet = SSplanets.z_to_planet[our_t.z]

	obscured = 0		// if hit the edge or stepped 20 times, not obscured
	update_solar_exposure()

	// Use the actual brightness of time and weather if we are on a planet, check if we're not blocked above by seeing what our outdoors status is
	if(our_planet)
		sunfrac *= our_t.is_outdoors() ? our_planet.sun["brightness"] : 0

/// Updates the power generation of a solar panel.
/obj/machinery/power/solar/proc/update_power_generation(obj/machinery/power/solar_control/SC)
	set_adir(SC.cdir) //instantly rotates the panel
	occlusion()//and
	changed(src) //update it
	var/sgen = get_power_supplied()
	controller_supply = sgen
	return sgen

/// Looks nice but doesn't generate power.
/obj/machinery/power/solar/fake

/obj/machinery/power/solar/fake/get_power_supplied()
	return 0

/obj/machinery/power/solar/fake/update_power_generation()
	return 0

//
// Solar Assembly - For construction of solar arrays.
//

/obj/item/solar_assembly
	name = "solar panel assembly"
	desc = "A solar panel assembly kit, allows constructions of a solar panel, or with a tracking circuit board, a solar tracker"
	icon = 'icons/obj/power.dmi'
	icon_state = "sp_base"
	item_state = "camera"
	w_class = ITEMSIZE_LARGE // Pretty big!
	anchored = FALSE
	var/tracker = 0

MSG_DEF_SELF(solar_assembly/not_placed, "It has to be on the floor.")
MSG_DEF_SELF(solar_assembly/unanchored, "It has to be wrenched in place first.")
MSG_DEF_SELF(solar_assembly/not_glass, "It needs glass or reinforced glass.")
MSG_DEF(solar_assembly/glassed, "You place the glass on the solar assembly.", "%U% places the glass on the solar assembly.")
MSG_DEF(solar_assembly/electronics_in, "You insert the electronics into the solar assembly.", "%U% inserts the electronics into the solar assembly.")
MSG_DEF(solar_assembly/electronics_out, "You take out the electronics from the solar assembly.", "%U% takes out the electronics from the solar assembly.")

// The assembly of a panel or tracker: wrenched down on the floor it takes two sheets of glass and becomes a panel (with tracker electronics in,
// a tracker); a crowbar takes the electronics back out. Wrenched down, it cannot be picked up.
CAPABILITIES(/obj/item/solar_assembly)
	op("fixed", hand(), label("Touch"), wait(0), when(nameof(anchored)), when(req_empty_hand()), then(PROC_REF(touched)))
	op("wrench", tool(TOOL_WRENCH), label("Wrench"), wait(0), needs(req(PROC_REF(on_floor), because = MSG(solar_assembly/not_placed))), then(PROC_REF(wrenched)))
	op("glass", stack(/obj/item/stack/material, 2), label("Add glass"), wait(0), when(req(PROC_REF(held_is_glass))),
		needs(req(PROC_REF(on_floor), because = MSG(solar_assembly/not_placed)), req_is(nameof(anchored), TRUE, because = MSG(solar_assembly/unanchored))),
		says(MSG(solar_assembly/glassed)), then(PROC_REF(glassed)))
	op("electronics", item(/obj/item/tracker_electronics), label("Insert electronics"), wait(0), when(cond_not(nameof(tracker))),
		says(MSG(solar_assembly/electronics_in)), then(PROC_REF(electronics_in)))
	op("take_electronics", tool(TOOL_CROWBAR), label("Take out the electronics"), wait(0), when(nameof(tracker)),
		says(MSG(solar_assembly/electronics_out)), then(PROC_REF(electronics_out)))

TRACKED(/obj/item/solar_assembly, tracker)

/// Wrenched down it stays put (an empty hand does nothing to it).
/obj/item/solar_assembly/proc/touched(datum/act/op/A)
	return OP_OK

/obj/item/solar_assembly/proc/on_floor(datum/act/A)
	return isturf(loc) // ALLOW(reads): where an assembly lies is engine state, read only when a tool is applied to it

/obj/item/solar_assembly/proc/held_is_glass(datum/act/op/A)
	var/obj/item/stack/material/S = A.held
	return istype(S, /obj/item/stack/material/glass)

/obj/item/solar_assembly/proc/wrenched(datum/act/op/A)
	set_anchored(!anchored)
	act_message(A.actor, null, others = span_notice("%U% [anchored ? "wrenches" : "unwrenches"] the solar assembly [anchored ? "into" : "from"] place."))
	play_sfx(src, SFX_ITEMS_RATCHET)
	return OP_OK

/// The glass is on: the panel (or tracker) takes the assembly's place.
/obj/item/solar_assembly/proc/glassed(datum/act/op/A)
	play_sfx(src, SFX_MACHINES_CLICK)
	replace_with(src, tracker ? /obj/machinery/power/tracker : /obj/machinery/power/solar, A.held?.type)
	return OP_OK

/obj/item/solar_assembly/proc/electronics_in(datum/act/op/A)
	if(!global.consume(A.held, A.actor))
		return OP_OK
	set_tracker(1)
	return OP_OK

/obj/item/solar_assembly/proc/electronics_out(datum/act/op/A)
	new /obj/item/tracker_electronics(loc)
	set_tracker(0)
	return OP_OK

//
// Solar Control Computer
//

/obj/machinery/power/solar_control
	name = "solar panel control"
	desc = "A controller for solar panel arrays."
	icon = 'icons/obj/computer.dmi'
	icon_state = "solar"
	anchored = TRUE
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 250
	integrity_failure = 0.5
	var/id = 0
	var/cdir = 0
	var/targetdir = 0		// target angle in manual tracking (since it updates every game minute)
	var/track = 0			// 0= off  1=timed  2=auto (tracker)
	var/trackrate = 600		// 300-900 seconds
	EXPIRY_DECLARE(nexttime) // time for a panel to rotate of 1° in manual tracking
	var/tmp/obj/machinery/power/tracker/connected_tracker
	var/needs_panel_check	// Powernet has been updated, need to check if panels are still connected.
	var/connected_power		// Sum of power supplied by connected panels.
	/// Relation list of connected panels; each panel's controller_supply holds its last reported power.
	VAR_PRIVATE/list/connected_panels
	/// Relation list: panels still to update in the solar service's current pass.
	var/list/solar_pending
	/// Running power sum for the solar service's current pass.
	var/solar_pending_sum = 0
	var/auto_start = SOLAR_AUTO_START_NO
TRACKED(/obj/machinery/power/solar_control, cdir)

// Used for mapping in solar arrays which automatically start itself.
// Generally intended for far away and remote locations, where player intervention is rare.
// In the interest of backwards compatability, this isn't named auto_start, as doing so might break downstream maps.
/obj/machinery/power/solar_control/autostart
	auto_start = SOLAR_AUTO_START_YES

// Similar to above but controlled by the configuration file.
// Intended to be used for the main solar arrays, so individual servers can choose to have them start automatically or require manual intervention.
/obj/machinery/power/solar_control/config_start
	auto_start = SOLAR_AUTO_START_CONFIG

/obj/machinery/power/solar_control/Initialize(mapload)
	. = ..()
	set_panels(cdir)

// its panels and tracker lose their controller.
/obj/machinery/power/solar_control/on_destroy(force)
	for(var/obj/machinery/power/solar/M in connected_panels)
		M.unset_control()
	if(connected_tracker())
		connected_tracker().unset_control()
	..()

/obj/machinery/power/solar_control/proc/auto_start(forced = FALSE)
	// Automatically sets the solars, if allowed.
	if(forced || auto_start == SOLAR_AUTO_START_YES || (auto_start == SOLAR_AUTO_START_CONFIG && CONFIG_GET(flag/autostart_solars)) )
		track = 2 // Auto tracking mode.
		search_for_connected()
		if(connected_tracker())
			connected_tracker().set_angle(SSsolars.get_solar_angle(get_turf(src)))
		set_panels(cdir)

/obj/machinery/power/solar_control/proc/add_panel(obj/machinery/power/solar/P)
	var/sgen = P.get_power_supplied()
	if(P in connected_panels) // Just in case it was already in there
		connected_power -= P.controller_supply
	P.controller_supply = sgen
	rel_add(src, nameof(connected_panels), P)
	connected_power += sgen

/obj/machinery/power/solar_control/proc/remove_panel(obj/machinery/power/solar/P)
	if(P in connected_panels)
		connected_power -= P.controller_supply
		P.controller_supply = 0
	rel_remove(src, nameof(connected_panels), P)
	rel_remove(src, nameof(solar_pending), P) // leave the solar service's current pass

/obj/machinery/power/solar_control/proc/get_connected_panels()
	RETURN_TYPE(/list)
	return connected_panels

/obj/machinery/power/solar_control/drain_power()
	return -1


/obj/machinery/power/solar_control/disconnect_from_network()
	. = ..()
	registry_leave(REGISTRY_SOLAR_CONTROLS, src)
	needs_panel_check = TRUE

/obj/machinery/power/solar_control/connect_to_network(bind_now = TRUE)
	var/to_return = ..()
	if(power_region) //if connected and not already in solar_list...
		registry_join(REGISTRY_SOLAR_CONTROLS, src) //... add it
		needs_panel_check = TRUE
	return to_return

/obj/machinery/power/solar_control/power_network_changed(old_region, new_region)
	if(new_region)
		registry_join(REGISTRY_SOLAR_CONTROLS, src)
	else
		registry_leave(REGISTRY_SOLAR_CONTROLS, src)
	needs_panel_check = TRUE

//search for unconnected panels and trackers in the computer powernet and connect them
/obj/machinery/power/solar_control/proc/search_for_connected()
	if(power_region)
		for(var/obj/machinery/power/M in power_grid_nodes(power_region))
			if(istype(M, /obj/machinery/power/solar))
				var/obj/machinery/power/solar/S = M
				if(!S.control() && S.set_control(src)) //i.e unconnected
					add_panel(S)
			else if(istype(M, /obj/machinery/power/tracker))
				if(!connected_tracker()) //if there's already a tracker connected to the computer don't add another
					var/obj/machinery/power/tracker/T = M
					if(!T.control()) //i.e unconnected
						rel_set(src, nameof(connected_tracker), T)
						T.set_control(src)

//called by the sun controller, update the facing angle (either manually or via tracking) and rotates the panels accordingly
/obj/machinery/power/solar_control/proc/update()
	if(!operable())
		return

	switch(track)
		if(1)
			if(trackrate) //we're manual tracking. If we set a rotation speed...
				set_cdir(targetdir) //...the current direction is the targetted one (and rotates panels to it)
		if(2) // auto-tracking
			if(connected_tracker())
				connected_tracker().set_angle(SSsolars.get_solar_angle(get_turf(src)))

/obj/machinery/power/solar_control/draw(datum/look/look)
	..()
	if(broken_now())
		look.state("broken")
		return
	if(power_lost())
		look.state("c_unpowered")
		return
	look.state("solar")
	if(cdir > -1)
		look.overlay(image('icons/obj/computer.dmi', "solcon-o", FLY_LAYER, angle2dir(cdir)))

// The solar control computer (doc/rewrite/final_api.html section 16): it links the panels and the tracker on its network, turns the panels
// (by hand, at a set rate, or after the tracker), and supplies their sum. The solar system (solar_service.dm) updates the array every minute;
// every machine service interval the controller keeps its links honest and steps a manual rotation (control_step()). A screwdriver takes it
// apart into its frame.
CAPABILITIES(/obj/machinery/power/solar_control)
	membership(joins = REGISTRY_SOLAR_CONTROLS)
	ref_one(nameof(connected_tracker), /obj/machinery/power/tracker)
	ref_many(nameof(connected_panels), /obj/machinery/power/solar)
	ref_many(nameof(solar_pending), /obj/machinery/power/solar)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(control_step)), when = PROC_REF(works))
	op("disassemble", tool(TOOL_SCREWDRIVER), label("Disconnect the monitor"), wait(2 SECONDS), then(PROC_REF(disassemble_done)))
	interface("SolarControl")
	extend("ui_open", when(req_empty_hand()))
	op("azimuth", ui_act("azimuth", arg("adjust", num()), arg("value", num())), then(PROC_REF(ui_act_azimuth)))
	op("azimuth_rate", ui_act("azimuth_rate", arg("adjust", num()), arg("value", num())), then(PROC_REF(ui_act_azimuth_rate)))
	op("tracking", ui_act("tracking", arg("mode", num())), then(PROC_REF(ui_act_tracking)))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))

/obj/machinery/power/solar_control/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["array_angle"] = cdir
	data["rotation_rate"] = trackrate
	data["tracking_state"] = track
	data["generated"] = round(connected_power)
	data["generated_ratio"] = data["generated"] / round(max(length(connected_panels), 1) * GLOB.solar_gen_rate)

	data["sun_angle"] = SSsolars.get_solar_angle(get_turf(src))
	data["max_rotation_rate"] = 7200

	data["connected_panels"] = length(connected_panels)
	data["connected_tracker"] = (connected_tracker() ? TRUE : FALSE)

	return data

/obj/machinery/power/solar_control/proc/disassemble_done(datum/act/op/A)
	var/mob/user = A.actor
	. = OP_OK
	if (src.broken_now())
		to_chat(user, span_blue("The broken glass falls out."))
		var/obj/structure/frame/F = new /obj/structure/frame/computer(src.loc)
		new /obj/item/material/shard(src.loc)
		var/obj/item/circuitboard/solar_control/M = new /obj/item/circuitboard/solar_control(F)
		latent_materialize_all() // a walk needs real things (C5)
		for(var/obj/C in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			C.forceMove(src.loc)
		rel_set(F, nameof(F.circuit), M)
		F.state = 3
		F.icon_state = "computer_3"
		F.set_anchored(TRUE)
		spent(src, user)
	else
		to_chat(user, span_blue("You disconnect the monitor."))
		var/obj/structure/frame/F = new /obj/structure/frame/computer(src.loc)
		var/obj/item/circuitboard/solar_control/M = new /obj/item/circuitboard/solar_control(F)
		latent_materialize_all() // a walk needs real things (C5)
		for(var/obj/C in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			C.forceMove(src.loc)
		rel_set(F, nameof(F.circuit), M)
		F.state = 4
		F.icon_state = "computer_4"
		F.set_anchored(TRUE)
		spent(src, user)

/// It works while it is powered and whole.
/obj/machinery/power/solar_control/proc/works(datum/act/A)
	return operable()

/// One step: an unlinked tracker or panel off its network lets go, and a manual rotation turns the target a degree when it is due.
/obj/machinery/power/solar_control/proc/control_step(datum/act/timer/A)

	if(connected_tracker()) //NOTE : handled here so that we don't add trackers to the processing list
		if(connected_tracker().power_region != power_region)
			connected_tracker().unset_control()

	if(track==1 && trackrate) //manual tracking and set a rotation speed
		if(EXPIRY_EXPIRED(src, nexttime, CLOCK_WORLD)) //every time we need to increase/decrease the angle by 1°...
			targetdir = (targetdir + trackrate/abs(trackrate) + 360) % 360 	//... do it
			nexttime += 36000/abs(trackrate) //reset the counter for the next 1°

	if(needs_panel_check)
		needs_panel_check = FALSE
		for(var/obj/machinery/power/solar/S in connected_panels)
			if (S.power_region != power_region)
				S.unset_control()
	set_power_supply(connected_power)

/obj/machinery/power/solar_control/proc/ui_act_azimuth(datum/act/op/A, adjust_arg, value_arg)
	var/adjust = adjust_arg
	var/value = value_arg
	if(adjust)
		value = cdir + adjust
	if(value != null)
		set_cdir(value)
		set_panels(cdir)
		return TRUE
	return FALSE

/obj/machinery/power/solar_control/proc/ui_act_azimuth_rate(datum/act/op/A, adjust_arg, value_arg)
	var/adjust = adjust_arg
	var/value = value_arg
	if(adjust)
		value = trackrate + adjust
	if(value != null)
		trackrate = round(clamp(value, -7200, 7200), 0.01)
		if(trackrate)
			EXPIRY_SET(src, nexttime, 36000 / abs(trackrate), CLOCK_WORLD)
		return TRUE
	return TRUE

/obj/machinery/power/solar_control/proc/ui_act_tracking(datum/act/op/A, mode_arg)
	var/mode = mode_arg
	track = mode
	if(track == 2)
		if(connected_tracker())
			connected_tracker().set_angle(SSsolars.get_solar_angle(get_turf(src)))
			set_panels(cdir)
	else if(track == 1) //begin manual tracking
		targetdir = cdir
		if(trackrate)
			EXPIRY_SET(src, nexttime, 36000/abs(trackrate), CLOCK_WORLD)
		set_panels(targetdir)
	return TRUE

/obj/machinery/power/solar_control/proc/ui_act_refresh(datum/act/op/A)
	search_for_connected()
	return TRUE

/// rotates all connected panels to the passed angle, very expensive as it does them all at once in a single frame. This is what the solar world service does, but much more rude about it.
/obj/machinery/power/solar_control/proc/set_panels(cdir)
	var/sum = 0
	for(var/obj/machinery/power/solar/S in connected_panels)
		sum += S.update_power_generation(src)
	connected_power = sum
	set_power_supply(connected_power)

//
// MISC
//

/obj/item/paper/solar
	name = "paper- 'Going green! Setup your own solar array instructions.'"
	info = "<h1>Welcome</h1><p>At greencorps we love the environment, and space. With this package you are able to help mother nature and produce energy without any usage of fossil fuel or phoron! Singularity energy is dangerous while solar energy is safe, which is why it's better. Now here is how you setup your own solar array.</p><p>You can make a solar panel by wrenching the solar assembly onto a cable node. Adding a glass panel, reinforced or regular glass will do, will finish the construction of your solar panel. It is that easy!</p><p>Now after setting up 19 more of these solar panels you will want to create a solar tracker to keep track of our mother nature's gift, the sun. These are the same steps as before except you insert the tracker equipment circuit into the assembly before performing the final step of adding the glass. You now have a tracker! Now the last step is to add a computer to calculate the sun's movements and to send commands to the solar panels to change direction with the sun. Setting up the solar computer is the same as setting up any computer, so you should have no trouble in doing that. You do need to put a wire node under the computer, and the wire needs to be connected to the tracker.</p><p>Congratulations, you should have a working solar array. If you are having trouble, here are some tips. Make sure all solar equipment are on a cable node, even the computer. You can always deconstruct your creations if you make a mistake.</p><p>That's all to it, be safe, be green!</p>"

#undef SOLAR_AUTO_START_NO
#undef SOLAR_AUTO_START_YES
#undef SOLAR_AUTO_START_CONFIG

/// the control this refers to: a relation view, null once that is deleted.
/obj/machinery/power/solar/proc/control() as /obj/machinery/power/solar_control
	return control

/// the connected_tracker this refers to: a relation view, null once that is deleted.
/obj/machinery/power/solar_control/proc/connected_tracker() as /obj/machinery/power/tracker
	return connected_tracker
