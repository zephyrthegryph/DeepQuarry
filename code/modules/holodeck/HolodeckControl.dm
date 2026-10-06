/obj/machinery/computer/HolodeckControl
	name = "holodeck control console"
	desc = "A computer used to control a nearby holodeck."
	icon_keyboard = "tech_key"
	icon_screen = "holocontrol"

	use_power = USE_POWER_IDLE
	active_power_usage = 8000 //8kW for the scenery + 500W per holoitem
	var/item_power_usage = 500

	var/tmp/area/linkedholodeck
	var/tmp/area/target
	active = 0
	/// Objects the current program projected (a relation view; derez() deletes them).
	var/list/obj/holographic_objs
	/// Holocarp the current program spawned (a relation view).
	var/list/mob/living/simple_mob/animal/space/carp/holodeck/holographic_mobs
	var/damaged = 0
	var/safety_disabled = 0
	var/tmp/mob/last_to_emag
	/// Program-change spam throttle: inside the short window clicks are ignored, inside the long one they warn.
	COOLDOWN_DECLARE(change_short_cooldown)
	COOLDOWN_DECLARE(change_long_cooldown)
	/// Same two-tier throttle for gravity toggles.
	COOLDOWN_DECLARE(gravity_short_cooldown)
	COOLDOWN_DECLARE(gravity_long_cooldown)

	var/projection_area = /area/holodeck/alphadeck
	var/current_program
	var/powerdown_program = "Turn Off"
	var/default_program = "Empty Court"

	var/static/list/supported_programs = list(
	"Empty Court" 		= new/datum/holodeck_program(/area/holodeck/source_emptycourt, list('sound/music/THUNDERDOME.ogg')),
	"Boxing Ring" 		= new/datum/holodeck_program(/area/holodeck/source_boxingcourt, list('sound/music/THUNDERDOME.ogg')),
	"Basketball" 		= new/datum/holodeck_program(/area/holodeck/source_basketball, list('sound/music/THUNDERDOME.ogg')),
	"Thunderdome"		= new/datum/holodeck_program(/area/holodeck/source_thunderdomecourt, list('sound/music/THUNDERDOME.ogg')),
	"Beach" 			= new/datum/holodeck_program(/area/holodeck/source_beach),
	"Desert" 			= new/datum/holodeck_program(/area/holodeck/source_desert,
													list(
														'sound/ambience/desert/desertnight1.ogg',
														'sound/ambience/desert/desertnight2.ogg',
														'sound/ambience/desert/desertnight3.ogg',
														'sound/ambience/desert/desertnight4.ogg'
														)
													),
	"Snowfield" 		= new/datum/holodeck_program(/area/holodeck/source_snowfield,
													list(
														'sound/effects/weather/snowstorm/snowstorm_loop.ogg'
														)
													),
	"Space" 			= new/datum/holodeck_program(/area/holodeck/source_space,
													list(
														'sound/ambience/ambispace.ogg',
														'sound/music/main.ogg',
														'sound/music/space.ogg',
														'sound/music/traitor.ogg',
														)
													),
	"Picnic Area" 		= new/datum/holodeck_program(/area/holodeck/source_picnicarea, list('sound/music/title2.ogg')),
	"Theatre" 			= new/datum/holodeck_program(/area/holodeck/source_theatre),
	"Meetinghall" 		= new/datum/holodeck_program(/area/holodeck/source_meetinghall),
	"Courtroom" 		= new/datum/holodeck_program(/area/holodeck/source_courtroom, list('sound/music/traitor.ogg')),
	"Chessboard"		= new/datum/holodeck_program(/area/holodeck/source_chess),
	"Micro Building Area"		= new/datum/holodeck_program(/area/holodeck/source_smoleworld), // add
	"Gym"				= new/datum/holodeck_program(/area/holodeck/source_gym), // add
	"Game Room"			= new/datum/holodeck_program(/area/holodeck/source_game_room), // add
	"Patient Ward"		= new/datum/holodeck_program(/area/holodeck/source_patient_ward), // add
	"Inside"			= new/datum/holodeck_program(/area/holodeck/the_uwu_zone, list('sound/vore/sunesound/prey/loop.ogg')), // add
	"Turn Off" 			= new/datum/holodeck_program(/area/holodeck/source_plating, list())
	)

	var/static/list/restricted_programs = list(
	"Burnoff Test Simulation"	= new/datum/holodeck_program(/area/holodeck/source_burntest, list()),
	"Wildlife Simulation" 		= new/datum/holodeck_program(/area/holodeck/source_wildlife, list())
	)

EXTEND_INTERACTIONS(/obj/machinery/computer/HolodeckControl, \
)

/**
 * Open the UI!
 */

/**
 * Data for the TGUI UI
 */
/obj/machinery/computer/HolodeckControl/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["currentProgram"] = current_program
	data["safetyDisabled"] = safety_disabled
	var/list/merged_1 = ui_data_obj_machinery_computer_HolodeckControl(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/computer/HolodeckControl's window data.
/obj/machinery/computer/HolodeckControl/proc/ui_data_obj_machinery_computer_HolodeckControl(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/list/program_list = list()
	var/list/restricted_program_list = list()

	for(var/P in supported_programs)
		program_list.Add(P)

	for(var/P in restricted_programs)
		restricted_program_list.Add(P)

	data["supportedPrograms"] = program_list
	data["restrictedPrograms"] = restricted_program_list
	data["isSilicon"] = FALSE
	if(issilicon(user))
		data["isSilicon"] = TRUE

	data["emagged"] = emagged
	data["gravity"] = FALSE
	if(linkedholodeck().get_gravity())
		data["gravity"] = TRUE

	return data

/obj/machinery/computer/HolodeckControl/proc/ui_act_program(datum/act/op/A, program)
	var/prog = program
	if(prog in (supported_programs + restricted_programs))
		if(loadProgram(prog))
			current_program = prog
	return TRUE

/obj/machinery/computer/HolodeckControl/proc/ui_act_aioverride(datum/act/op/A)
	var/mob/user = A.actor
	if(!(A.authority & AUTH_REMOTE_ACCESS))
		return

	if(safety_disabled && emagged)
		return //if a traitor has gone through the trouble to emag the thing, let them keep it.

	safety_disabled = !safety_disabled
	update_projections()
	if(safety_disabled)
		message_admins("[key_name_admin(user)] overrode the holodeck's safeties")
		log_game("[key_name(user)] overrided the holodeck's safeties")
	else
		message_admins("[key_name_admin(user)] restored the holodeck's safeties")
		log_game("[key_name(user)] restored the holodeck's safeties")
	return TRUE

/obj/machinery/computer/HolodeckControl/proc/ui_act_gravity(datum/act/op/A)
	toggleGravity(linkedholodeck())
	return TRUE

DECLARE_EMAG_REPEATABLE(/obj/machinery/computer/HolodeckControl, PROC_REF(on_emag), null)
/obj/machinery/computer/HolodeckControl/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	play_sfx(src, SFX_EFFECTS_SPARKS4)
	rel_set(src, nameof(last_to_emag), user) //emag again to change the owner
	if (!emagged)
		set_emagged(1)
		safety_disabled = 1
		update_projections()
		to_chat(user, span_notice("You vastly increase projector power and override the safety and security protocols."))
		to_chat(user, "Warning.  Automatic shutoff and derezing protocols have been corrupted.  Please call [using_map.company_name] maintenance and do not use the simulator.")
		log_game("[key_name(user)] emagged the Holodeck Control Computer")
		return 1
	return

/obj/machinery/computer/HolodeckControl/proc/update_projections()
	if (safety_disabled)
		item_power_usage = 2500
		for(var/obj/item/holo/esword/H in linkedholodeck())
			H.injury_kind = H.active ? INJURY_CUT : INJURY_BLUNT
	else
		item_power_usage = initial(item_power_usage)
		for(var/obj/item/holo/esword/H in linkedholodeck())
			H.injury_kind = initial(H.injury_kind)

	for(var/mob/living/simple_mob/animal/space/carp/holodeck/C in holographic_mobs)
		C.set_safety(!safety_disabled)
		if (last_to_emag())
			rel_clear(C, nameof(C.friends))
			rel_add(C, nameof(C.friends), last_to_emag())

/obj/machinery/computer/HolodeckControl/Initialize(mapload)
	. = ..()
	current_program = powerdown_program
	linkedholodeck = locate(projection_area) // an area: a plain var
	if(!linkedholodeck())
		to_chat(world, span_danger("Holodeck computer at [x],[y],[z] failed to locate projection area."))

//This could all be done better, but it works for now.
// the holodeck shuts down.
CAPABILITIES(/obj/machinery/computer/HolodeckControl)
	started_work(step = PROC_REF(work_step))
	ref_many(nameof(holographic_objs))
	ref_many(nameof(holographic_mobs))
	interface("Holodeck")
	without("ui_open")
	op("program", ui_act("program", arg("program", schema_text(4096))), then(PROC_REF(ui_act_program)))
	op("AIoverride", ui_act("AIoverride"), then(PROC_REF(ui_act_aioverride)))
	op("gravity", ui_act("gravity"), then(PROC_REF(ui_act_gravity)))

/obj/machinery/computer/HolodeckControl/on_destroy(force)
	emergencyShutdown()
	..()

DAMAGE_REACTION(/obj/machinery/computer/HolodeckControl, DAMAGE_EXPLOSION, PROC_REF(holodeck_blast_shutdown))

/// A blast shuts the holodeck down.
/obj/machinery/computer/HolodeckControl/proc/holodeck_blast_shutdown(datum/damage_packet/packet)
	emergencyShutdown()

/obj/machinery/computer/HolodeckControl/power_change()
	. = ..()
	if (. && active && (has_stat(NOPOWER)))
		emergencyShutdown()

/// Watches its holograms (and draws power for them) while a program runs or holograms exist;
/// otherwise it sleeps until a program loads (its UI).
/obj/machinery/computer/HolodeckControl/proc/work_step(datum/act/timer/A)
	if(!active && !length(holographic_objs) && !length(holographic_mobs))
		return PROCESS_KILL
	for(var/item in holographic_objs) // do this first, to make sure people don't take items out when power is down.
		if(!(get_turf(item) in linkedholodeck()))
			derez(item, 0)

	for(var/mob/living/simple_mob/animal/space/carp/holodeck/C in holographic_mobs)
		if (get_area(C.loc) != linkedholodeck())
			rel_remove(src, nameof(holographic_mobs), C)
			C.derez()

	if(!operable())
		return
	if(active)
		use_power(item_power_usage * (length(holographic_objs) + length(holographic_mobs)))

		if(!checkInteg(linkedholodeck()))
			damaged = 1
			loadProgram(powerdown_program, 0)
			set_active(0)
			set_use_power(USE_POWER_IDLE)
			for(var/mob/M in range(10,src))
				M.show_message("The holodeck overloads!")

			for(var/turf/T in linkedholodeck())
				if(prob(30))
					fx_sparks(T, 2)
				T.ex_act(3)
				T.hotspot_expose(1000,500,1)

/obj/machinery/computer/HolodeckControl/proc/derez(obj/obj , silent = 1)
	rel_remove(src, nameof(holographic_objs), obj)

	if(obj == null)
		return

	if(isobj(obj))
		var/mob/M = obj.loc
		if(ismob(M))
			M.remove_from_mob(obj)

	if(!silent)
		var/obj/oldobj = obj
		visible_message("The [oldobj.name] fades away!")
	spent(obj)

/obj/machinery/computer/HolodeckControl/proc/checkInteg(area/A)
	for(var/turf/T in area_contents_of_type(A, /turf))
		if(istype(T, /turf/space))
			return 0

	return 1

//Why is it called toggle if it doesn't toggle?
/obj/machinery/computer/HolodeckControl/proc/togglePower(toggleOn = 0)
	if(toggleOn)
		loadProgram(default_program, 0)
	else
		loadProgram(powerdown_program, 0)

		if(!linkedholodeck().get_gravity())
			linkedholodeck().gravitychange(1)

		set_active(0)
		set_use_power(USE_POWER_IDLE)

/obj/machinery/computer/HolodeckControl/proc/loadProgram(prog, check_delay = 1)
	if(!prog)
		return

	var/datum/holodeck_program/HP
	if(prog in supported_programs)
		HP = supported_programs[prog]
	else if(prog in restricted_programs)
		HP = restricted_programs[prog]
	if(!HP)
		return

	var/area/A = locate(HP.target)
	if(!A)
		return

	if(check_delay)
		if(COOLDOWN_TIMELEFT(src, change_long_cooldown))
			if(COOLDOWN_TIMELEFT(src, change_short_cooldown))//To prevent super-spam clicking, reduced process size and annoyance -Sieve
				return 0
			for(var/mob/M in range(3,src))
				M.show_message(span_warningplain(span_bold("ERROR. Recalibrating projection apparatus.")))
				start_change_cooldowns()
				return 0

	start_change_cooldowns()
	set_active(1)
	set_use_power(USE_POWER_ACTIVE)

	for(var/item in holographic_objs)
		derez(item)

	for(var/mob/living/simple_mob/animal/space/carp/holodeck/C in holographic_mobs)
		rel_remove(src, nameof(holographic_mobs), C)
		C.derez()

	for(var/obj/effect/decal/cleanable/blood/B in linkedholodeck())
		spent(B, src)

	for(var/obj/effect/landmark/L in linkedholodeck())
		spent(L, src)

	// The program's objects are cloned into the room (entity_clone, via copy_contents_to()); the
	// holodeck tracks them in a relation roster and derezzes them itself (derez()) on the next
	// program or a shutdown. They are world objects players can carry, so they are not owned here;
	// one destroyed elsewhere just leaves the roster.
	for(var/obj/holo_obj in A.copy_contents_to(linkedholodeck(), 1))
		rel_add(src, nameof(holographic_objs), holo_obj)
	for(var/obj/holo_obj in holographic_objs)
		holo_obj.alpha *= 0.8 //give holodeck objs a slight transparency

	if(HP.ambience)
		linkedholodeck().forced_ambience = HP.ambience
	else
		linkedholodeck().forced_ambience = list()

	for(var/mob/living/M in mobs_in_area(linkedholodeck()))
		if(M.mind)
			linkedholodeck().play_ambience(M, initial = TRUE)

	linkedholodeck().sound_env = A.sound_env

	if(prog == powerdown_program)
		linkedholodeck().requires_power = TRUE
	else
		linkedholodeck().requires_power = FALSE
	linkedholodeck().power_change()

	for(var/obj/effect/landmark/L in linkedholodeck())
		L.delete_me = TRUE
		if(L.name=="Atmospheric Test Start")
			after(src, 2 SECONDS, PROC_REF(atmos_test_ignite), with = list(get_turf(L)))
		if(L.name=="Holocarp Spawn")
			rel_add(src, nameof(holographic_mobs), new /mob/living/simple_mob/animal/space/carp/holodeck(L.loc))

		if(L.name=="Holocarp Spawn Random")
			if(prob(4)) //With 4 spawn points, carp should only appear 15% of the time.
				rel_add(src, nameof(holographic_mobs), new /mob/living/simple_mob/animal/space/carp/holodeck(L.loc))
		spent(L, src)

		update_projections()

	return 1

/// Starts both tiers of the program-change throttle together.
/obj/machinery/computer/HolodeckControl/proc/start_change_cooldowns()
	COOLDOWN_START(src, change_short_cooldown, 1.5 SECONDS)
	COOLDOWN_START(src, change_long_cooldown, 2.5 SECONDS)

/obj/machinery/computer/HolodeckControl/proc/toggleGravity(area/A)
	if(COOLDOWN_TIMELEFT(src, gravity_long_cooldown))
		if(COOLDOWN_TIMELEFT(src, gravity_short_cooldown))//To prevent super-spam clicking
			return
		for(var/mob/M in range(3,src))
			M.show_message(span_warningplain(span_bold("ERROR. Recalibrating gravity field.")))
			start_change_cooldowns()
			return

	COOLDOWN_START(src, gravity_short_cooldown, 1.5 SECONDS)
	COOLDOWN_START(src, gravity_long_cooldown, 2.5 SECONDS)
	set_active(1)
	set_use_power(USE_POWER_IDLE)

	if(A.get_gravity())
		A.gravitychange(0)
	else
		A.gravitychange(1)

/obj/machinery/computer/HolodeckControl/proc/emergencyShutdown()
	//Turn it back to the regular non-holographic room
	loadProgram(powerdown_program, 0)

	if(!linkedholodeck().get_gravity())
		linkedholodeck().gravitychange(1)

	set_active(0)
	set_use_power(USE_POWER_IDLE)

/obj/machinery/computer/HolodeckControl/proc/atmos_test_ignite(turf/T)
	fx_sparks(T, 2)
	if(T)
		heat_set_solid(T, 5000)  // arena-authoritative; not the stale DM mirror
		T.hotspot_expose(50000,50000,1)

/// the linkedholodeck this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/HolodeckControl/proc/linkedholodeck() as /area
	return linkedholodeck

/// the last_to_emag this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/HolodeckControl/proc/last_to_emag() as /mob
	return last_to_emag

/// the target this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/HolodeckControl/proc/target() as /area
	return target
