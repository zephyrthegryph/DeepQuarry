
GLOBAL_LIST_EMPTY(gravity_generators)

//
// Gravity Generator
//


#define GRAV_NEEDS_SCREWDRIVER 0
#define GRAV_NEEDS_WELDING 1
#define GRAV_NEEDS_PLASTEEL 2
#define GRAV_NEEDS_WRENCH 3

//
// Abstract Generator
//

/obj/machinery/gravity_generator
	name = "gravitational generator"
	desc = "A device which produces a graviton field when set up."
	icon = 'icons/obj/machines/gravity_generator.dmi'
	anchored = TRUE
	density = TRUE
	unacidable = TRUE
	use_power = USE_POWER_OFF
	var/sprite_number = 0

	pixel_y = 16

MSG_DEF(gravgen/screwed, "You secure the screws of the framework.", "%U% secures the screws of %T%'s framework.")
MSG_DEF(gravgen/mended, "You mend the damaged framework.", "%U% mends %T%'s damaged framework.")
MSG_DEF(gravgen/plated, "You add the plating to the framework.", "%U% adds plating to %T%'s framework.")
MSG_DEF(gravgen/secured, "You secure the plating to the framework.", "%U% secures the plating to %T%'s framework.")

// The gravity generator (doc/rewrite/final_api.html section 16): a main part and the eight parts around it (one machine to a player: every part
// answers for the main one). Hits barely touch it: a devastating blast or a blob may break it. A broken generator is repaired by a ladder on
// any of its parts: screwdriver, welder, 10 plasteel, wrench.
CAPABILITIES(/obj/machinery/gravity_generator)
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(gravgen_blast_break))))
	extend(/datum/act/hit/blob, instead(then(PROC_REF(gravgen_blob_break))))
	op("repair_screws", tool(TOOL_SCREWDRIVER), label("Secure the screws"), wait(0), when(PROC_REF(needs_screws)), says(MSG(gravgen/screwed)), then(PROC_REF(repair_stepped)))
	op("repair_weld", lit_welder(fuel = 0), label("Mend the framework"), wait(0), when(PROC_REF(needs_welding)), says(MSG(gravgen/mended)), then(PROC_REF(repair_stepped)))
	op("repair_plate", stack(/obj/item/stack/material/plasteel, 10), label("Add plating"), wait(0), when(PROC_REF(needs_plasteel)), says(MSG(gravgen/plated)), then(PROC_REF(repair_stepped)))
	op("repair_wrench", tool(TOOL_WRENCH), label("Secure the plating"), wait(0), when(PROC_REF(needs_wrench)), says(MSG(gravgen/secured)), then(PROC_REF(repair_finished)))

/// The main part this part answers for (the main part answers for itself).
/obj/machinery/gravity_generator/proc/grav_main()
	return null

/// The repair ladder's rung the generator is on, or null while it is whole.
/obj/machinery/gravity_generator/proc/repair_rung()
	var/obj/machinery/gravity_generator/main/M = grav_main()
	if(!M || !M.has_stat(BROKEN))
		return null
	return M.broken_state

/obj/machinery/gravity_generator/proc/needs_screws(datum/act/A)
	return repair_rung() == GRAV_NEEDS_SCREWDRIVER

/obj/machinery/gravity_generator/proc/needs_welding(datum/act/A)
	return repair_rung() == GRAV_NEEDS_WELDING

/obj/machinery/gravity_generator/proc/needs_plasteel(datum/act/A)
	return repair_rung() == GRAV_NEEDS_PLASTEEL

/obj/machinery/gravity_generator/proc/needs_wrench(datum/act/A)
	return repair_rung() == GRAV_NEEDS_WRENCH

/// A rung of the repair done.
/obj/machinery/gravity_generator/proc/repair_stepped(datum/act/op/A)
	var/obj/machinery/gravity_generator/main/M = grav_main()
	M.set_broken_state(M.broken_state + 1)
	play_sfx(src, SFX_MACHINES_CLICK, 1.5)
	return OP_OK

/// The last rung: the generator is whole again.
/obj/machinery/gravity_generator/proc/repair_finished(datum/act/op/A)
	var/obj/machinery/gravity_generator/main/M = grav_main()
	M.atom_fix()
	return OP_OK

/// Very sturdy: only a devastating blast breaks it, and nothing else of a blast lands.
/obj/machinery/gravity_generator/proc/gravgen_blast_break(datum/act/hit/explosion/A)
	if(A.packet.severity == 1)
		atom_break()
	return TRUE

/// A blob sometimes breaks it, and does nothing else to it.
/obj/machinery/gravity_generator/proc/gravgen_blob_break(datum/act/hit/blob/A)
	if(prob(20))
		atom_break()
	return TRUE

/obj/machinery/gravity_generator/draw(datum/look/look)
	..()
	look.state("[get_status()]_[sprite_number]")

/obj/machinery/gravity_generator/proc/get_status()
	return "off"

// You aren't allowed to move.
/obj/machinery/gravity_generator/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	spent(src)

// a broken part takes the whole generator down.
/obj/machinery/gravity_generator/part/on_destroy(force)
	if(main_part)
		destroyed(main_part)
	atom_break()
	..()

//
// Part generator which is mostly there for looks
//

/obj/machinery/gravity_generator/part
	var/tmp/obj/machinery/gravity_generator/main/main_part

/obj/machinery/gravity_generator/part
	/// The charge overlay the main part shows on this, its middle part.
	var/shown_overlay

TRACKED(/obj/machinery/gravity_generator/part, shown_overlay)

CAPABILITIES(/obj/machinery/gravity_generator/part)
	ref_one(nameof(main_part), /obj/machinery/gravity_generator/main)
	op("use", hand(), label("Use"), wait(0), when(req_empty_hand()), then(PROC_REF(forward_hand)))

/obj/machinery/gravity_generator/part/grav_main()
	return main_part

/// A hand on a part opens the generator's window.
/obj/machinery/gravity_generator/part/proc/forward_hand(datum/act/op/A)
	if(main_part)
		perform_op(A.actor, main_part, "ui_open")
	return OP_OK

/// The middle part shows the generator's charge.
/obj/machinery/gravity_generator/part/draw(datum/look/look)
	..()
	look.overlay(shown_overlay, when = shown_overlay)

/obj/machinery/gravity_generator/part/get_status()
	return main_part?.get_status()

/obj/machinery/gravity_generator/part/atom_break(damage_flag)
	. = ..()
	if(main_part && !main_part.has_stat(BROKEN))
		main_part.atom_break(damage_flag)

//
// Generator which spawns with the station.
//
/obj/machinery/gravity_generator/main/station
	use_power = USE_POWER_ACTIVE
	current_overlay = "activated"

/obj/machinery/gravity_generator/main/station/Initialize(mapload)
	. = ..()
	setup_parts()
	var/obj/machinery/gravity_generator/part/M = middle
	if(istype(M))
		M.set_shown_overlay(current_overlay)

//
// Generator an admin can spawn
//
/obj/machinery/gravity_generator/main/station/admin
	use_power = USE_POWER_OFF

//
// Main Generator with the main code
//

/obj/machinery/gravity_generator/main
	icon_state = "on_8"
	idle_power_usage = 0
	active_power_usage = 30000 // Gravity consumption change
	power_channel = ENVIRON
	sprite_number = 8
	use_power = USE_POWER_IDLE

	on = TRUE
	var/breaker = TRUE
	/// The eight part objects around it (owned: created here, destroyed with it).
	var/list/obj/machinery/gravity_generator/part/parts
	var/tmp/obj/middle
	var/charge_count = 100
	var/current_overlay = null
	var/broken_state = 0
	var/list/levels
	var/list/areas
	/// GRAVGEN_IDLE, GRAVGEN_UP or GRAVGEN_DOWN: spinning up or down (spin_step()) or settled.
	var/charging_state = GRAVGEN_IDLE

TRACKED(/obj/machinery/gravity_generator/main, charging_state)
TRACKED(/obj/machinery/gravity_generator/main, broken_state)
TRACKED(/obj/machinery/gravity_generator/main, current_overlay)

// The main part: its window and breaker, its eight parts (owned), and its spin (spin_step(), every machine service interval while it spins
// and is whole).
CAPABILITIES(/obj/machinery/gravity_generator/main)
	after_init(0, then(PROC_REF(find_levels)))
	owns_many(nameof(parts), /obj/machinery/gravity_generator/part)
	ref_one(nameof(middle), /obj)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(spin_step)), when = PROC_REF(spinning))
	interface("GravityGenerator")
	extend("ui_open", when(req_empty_hand()))
	op("gentoggle", ui_act("gentoggle"), then(PROC_REF(ui_act_gentoggle)))

/obj/machinery/gravity_generator/main/grav_main()
	return src

/// Spinning up or down, and whole (a broken generator doesn't spin; operable() would also stop the spin-down on power loss).
/obj/machinery/gravity_generator/main/proc/spinning(datum/act/A)
	return charging_state != GRAVGEN_IDLE && !has_stat(BROKEN)

/// The charge overlay on the middle part.
/obj/machinery/gravity_generator/main/proc/set_charge_overlay(overlay_state)
	if(overlay_state == current_overlay)
		return
	set_current_overlay(overlay_state)
	var/obj/machinery/gravity_generator/part/M = middle
	if(istype(M))
		M.set_shown_overlay(overlay_state)

/// Finds its levels and areas, once the overmap sectors exist.
/obj/machinery/gravity_generator/main/proc/find_levels(datum/act/A) //Needs to happen after overmap sectors are initialized so we can figure out where we are
	update_list()
	update_areas()

// gravity goes off on its levels; its owned parts go with it.
/obj/machinery/gravity_generator/main/on_destroy(force)
	investigate_log("was destroyed!", "gravity")
	set_on(FALSE)
	update_list()
	if(!gravity_in_level())
		update_gravity(FALSE)
	..() // its parts (owned) are destroyed with it

/obj/machinery/gravity_generator/main/proc/setup_parts()
	var/turf/our_turf = get_turf(src)
	// 9x9 block obtained from the bottom middle of the block
	var/list/spawn_turfs = block(locate(our_turf.x - 1, our_turf.y + 2, our_turf.z), locate(our_turf.x + 1, our_turf.y, our_turf.z))
	var/count = 10
	for(var/turf/T in spawn_turfs)
		count--
		if(T == our_turf) // Skip our turf.
			continue
		var/obj/machinery/gravity_generator/part/part = new(T)
		if(count == 5) // Middle
			rel_set(src, nameof(middle), part)
		if(count <= 3) // Their sprite is the top part of the generator
			part.set_density(FALSE)
			part.plane = MOB_PLANE
			part.layer = ABOVE_MOB_LAYER
		part.sprite_number = count
		rel_set(part, nameof(part.main_part), src)
		rel_add(src, nameof(parts), part)

/obj/machinery/gravity_generator/main/proc/connected_parts()
	return length(parts) == 8

/obj/machinery/gravity_generator/main/atom_break(damage_flag)
	. = ..()
	if(!.)
		return
	for(var/obj/machinery/gravity_generator/M in parts)
		if(!M.has_stat(BROKEN))
			M.atom_break(damage_flag)
	set_charge_overlay(null)
	charge_count = 0
	breaker = FALSE
	set_power()
	set_gravity_state(0)
	investigate_log("has broken down.", "gravity")

/obj/machinery/gravity_generator/main/atom_fix()
	. = ..()
	for(var/obj/machinery/gravity_generator/M in parts)
		if(M.has_stat(BROKEN))
			M.atom_fix()
	set_broken_state(FALSE)
	set_power()
	update_list()
	update_areas()

// Interaction

// Fixing the gravity generator.
/obj/machinery/gravity_generator/main/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["breaker"] = breaker
	data["charge_count"] = charge_count
	data["charging_state"] = charging_state
	data["on"] = on
	data["operational"] = (has_stat(BROKEN)) ? FALSE : TRUE
	return data

/obj/machinery/gravity_generator/main/proc/ui_act_gentoggle(datum/act/op/A)
	var/mob/user = A.actor
	breaker = !breaker
	investigate_log("was toggled [breaker ? span_green("ON") : span_red("OFF")] by [key_name(user)].", "gravity")
	set_power()
	return TOPIC_REFRESH

// Power and Icon States

/obj/machinery/gravity_generator/main/power_change()
	. = ..()
	investigate_log("has [has_stat(NOPOWER) ? "lost" : "regained"] power.", "gravity")
	set_power()

/obj/machinery/gravity_generator/main/get_status()
	if(has_stat(BROKEN))
		return "fix[min(broken_state, 3)]"
	return on || charging_state != GRAVGEN_IDLE ? "on" : "off"

// Set the charging state based on power/breaker.
/obj/machinery/gravity_generator/main/proc/set_power()
	var/new_state = FALSE
	if(!operable() || !breaker)
		new_state = FALSE
	else if(breaker)
		new_state = TRUE

	// Charging state FSM
	switch(charging_state)
		if(GRAVGEN_UP)
			if(!new_state) // Can start spin down during spin up
				set_charging_state(GRAVGEN_DOWN)
		if(GRAVGEN_DOWN)
			if(new_state) // Can start spin up during spin down
				set_charging_state(GRAVGEN_UP)
		if(GRAVGEN_IDLE)
			if(!new_state && use_power == USE_POWER_ACTIVE) // Can start spin down during running
				set_charging_state(GRAVGEN_DOWN)
			else if(new_state && use_power == USE_POWER_IDLE) // Can start spin up during stopped
				set_charging_state(GRAVGEN_UP)

	investigate_log("is now [charging_state == GRAVGEN_UP ? "charging" : "discharging"].", "gravity")

// Set the state of the gravity.
/obj/machinery/gravity_generator/main/proc/set_gravity_state(new_state)
	set_charging_state(GRAVGEN_IDLE)
	set_use_power(new_state ? USE_POWER_ACTIVE : USE_POWER_IDLE)

	// Sound the alert if gravity was just enabled or disabled.
	var/alert = FALSE
	if(SSticker.IsRoundInProgress())
		if(new_state) // If we turned on and the game is live.
			if(gravity_in_level() == FALSE)
				// alert = TRUE No alarm! Gravity is fine :)
				investigate_log("was brought online and is now producing gravity for this level.", "gravity")
				message_admins("The gravity generator was brought online [ADMIN_JMP(src)]")
		else
			if(gravity_in_level() == TRUE)
				alert = TRUE
				investigate_log("was brought offline and there is now no gravity for this level.", "gravity")
				message_admins("The gravity generator was brought offline with no backup generator. [ADMIN_JMP(src)]")

	update_list()
	update_gravity(new_state)

	if(alert)
		shake_everyone()

// Charge/Discharge and turn on/off gravity when you reach 0/100 percent.
// Also emit radiation and handle the overlays.
/// Spins up or down while charging (its every(), gated on spinning()).
/obj/machinery/gravity_generator/main/proc/spin_step(datum/act/timer/A)
	if(charging_state != GRAVGEN_IDLE)
		if(charging_state == GRAVGEN_UP && charge_count >= 100)
			set_gravity_state(1)
		else if(charging_state == GRAVGEN_DOWN && charge_count <= 0)
			set_gravity_state(0)
		else
			if(charging_state == GRAVGEN_UP)
				charge_count += 2
			else if(charging_state == GRAVGEN_DOWN)
				charge_count -= 2

			if(charge_count % 4 == 0 && prob(75)) // Let them know it is charging/discharging.
				play_sfx(src, SFX_EFFECTS_EMPULSE)

			if(prob(25)) // To help stop "Your clothes feel warm." spam.
				pulse_radiation()

			var/overlay_state = null
			switch(charge_count)
				if(0 to 20)
					overlay_state = null
				if(21 to 40)
					overlay_state = "startup"
				if(41 to 60)
					overlay_state = "idle"
				if(61 to 80)
					overlay_state = "activating"
				if(81 to 100)
					overlay_state = "activated"

			set_charge_overlay(overlay_state)

/obj/machinery/gravity_generator/main/proc/pulse_radiation()
	radiation_pulse(
		src,
		max_range = 7,
		threshold = RAD_HEAVY_INSULATION,
		chance = DEFAULT_RADIATION_CHANCE * 2,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = charge_count * 2
	)

/obj/machinery/gravity_generator/main/proc/update_gravity(on)
	for(var/area/A in src.areas)
		A.gravitychange(on)

// Shake everyone on the z level to let them know that gravity was enagaged/disenagaged.
/obj/machinery/gravity_generator/main/proc/shake_everyone()
	var/sound/alert_sound = sound('sound/effects/alert.ogg')
	for(var/mob/M as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!(M.z in levels))
			continue
		M.update_gravity(M.mob_get_gravity())
		shake_camera(M, 15, 1)
		M.playsound_local(src, null, 50, 1, 0.5, S = alert_sound)

/obj/machinery/gravity_generator/main/proc/gravity_in_level()
	var/my_z = get_z(src)
	if(!my_z)
		return FALSE
	if(GLOB.gravity_generators["[my_z]"])
		return length(GLOB.gravity_generators["[my_z]"])
	return FALSE

/obj/machinery/gravity_generator/main/proc/update_list()
	LAZYCLEARLIST(levels)
	var/my_z = get_z(src)

	//Actually doing it special this time instead of letting using_map decide
	if(using_map.use_overmap)
		var/obj/effect/overmap/visitable/S = get_overmap_sector(my_z)
		if(S)
			levels = S.get_space_zlevels() //Just the spacey ones
		else
			levels = GetConnectedZlevels(my_z)
	else
		levels = GetConnectedZlevels(my_z)

	for(var/z in levels)
		if(!GLOB.gravity_generators["[z]"])
			GLOB.gravity_generators["[z]"] = list()
		if(use_power == USE_POWER_ACTIVE)
			GLOB.gravity_generators["[z]"] |= src
		else
			GLOB.gravity_generators["[z]"] -= src

/obj/machinery/gravity_generator/main/proc/update_areas()
	LAZYCLEARLIST(areas)
	for(var/area/A)
		if(istype(A, /area/shuttle))
			continue //Skip shuttle areas
		if(A.z in levels)
			LAZYADD(areas, A)

// Misc
// Taking out the comments on this. It will be needed.
/obj/item/paper/guide/gravity/
	name = "paper- 'Generate your own gravity!'"
	info = {"<h1>Gravity Generator Instructions For Dummies</h1>
	<p>Surprisingly, gravity isn't that hard to make! All you have to do is inject deadly radioactive minerals into a ball of
	energy and you have yourself gravity! You can turn the machine on or off when required but you must remember that the generator
	will EMIT RADIATION when charging or discharging, you can tell it is charging or discharging by the noise it makes, so please WEAR PROTECTIVE CLOTHING.</p>
	<br>
	<h3>It blew up!</h3>
	<p>Don't panic! The gravity generator was designed to be easily repaired. If, somehow, the sturdy framework did not survive then
	please proceed to panic; otherwise follow these steps.</p><ol>
	<li>Secure the screws of the framework with a screwdriver.</li>
	<li>Mend the damaged framework with a welding tool.</li>
	<li>Add additional plasteel plating.</li>
	<li>Secure the additional plating with a wrench.</li></ol>"}


#undef GRAV_NEEDS_SCREWDRIVER
#undef GRAV_NEEDS_WELDING
#undef GRAV_NEEDS_PLASTEEL
#undef GRAV_NEEDS_WRENCH


