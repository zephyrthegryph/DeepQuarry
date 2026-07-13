/obj/effect/step_trigger/teleporter/to_mining
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER

/obj/effect/step_trigger/teleporter/from_mining
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER

/obj/effect/step_trigger/teleporter/to_solars
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/from_solars
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/wild
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/to_underdark
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/from_underdark
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/to_plains
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/from_plains
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/planetary_fall/virgo3b

/obj/effect/step_trigger/lost_in_space
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE
	var/deathmessage = "You drift off into space, floating alone in the void until your life support runs out."

/obj/effect/step_trigger/lost_in_space/Trigger(atom/movable/A) //replacement for shuttle dump zones because there's no empty space levels to dump to
	if(ismob(A))
		to_chat(A, span_danger("[deathmessage]"))
	qdel(A)

/obj/effect/step_trigger/lost_in_space/bluespace
	deathmessage = "Everything goes blue as your component particles are scattered throughout the known and unknown universe."
	var/last_sound = 0

/obj/effect/step_trigger/lost_in_space/bluespace/Trigger(A)
	if(world.time - last_sound > 5 SECONDS)
		last_sound = world.time
		playsound(src, 'sound/effects/supermatter.ogg', 75, 1)
	if(ismob(A) && prob(5))//lucky day
		var/destturf = locate(rand(5,world.maxx-5),rand(5,world.maxy-5),pick(using_map.station_levels))
		do_teleport(A, destturf, 0, 1, asoundin = 'sound/effects/phasein.ogg')
	else
		return ..()

//"Red" Armory Door
/obj/machinery/door/airlock/security/armory
	name = "Red Armory"
	//color = ""

/obj/machinery/door/airlock/security/armory/allowed(mob/user)
	if(get_security_level() in list("green","blue"))
		return FALSE

	return ..(user)

//Tether-unique network cameras
/obj/machinery/camera/network/tether
	network = list(NETWORK_TETHER)

/obj/machinery/camera/network/outside
	network = list(NETWORK_OUTSIDE)

/obj/tether_away_spawner/tether_outside
	name = "Tether Outside Spawner"
	prob_spawn = 75
	prob_fall = 50
	mobs_to_pick_from = list(
		/mob/living/simple_mob/animal/passive/gaslamp = 300
		)

// Landmarks for wildlife events

/obj/effect/landmark/wildlife/water
	name = "aquatic wildlife"
	wildlife_type = 1

/obj/effect/landmark/wildlife/forest
	name = "roaming wildlife"
	wildlife_type = 2

// SD Things

/obj/machinery/camera/network/halls
	network = list(NETWORK_HALLS)

/obj/item/paper/sdshield
	name = "ABOUT THE SHIELD GENERATOR"
	info = "<H1>ABOUT THE SHIELD GENERATOR</H1><BR><BR>If you&#39;re up here you are more than likely worried about hitting rocks or some other such thing. It is good to worry about such things as that is an inevitability.<BR><BR>The Stellar Delight is a rather compact vessel, so a setting of 55 to the range will just barely cover her aft. <BR><BR>It is recommended that you turn off all of the different protection types except multi dimensional warp and whatever it is you&#39;re worried about running into. (probably meteors (hyperkinetic)). <BR><BR>With only those two and all the other default settings, the shield uses more than 6 MW to run, which is more than the ship can ordinarily produce. AS SUCH, it is also recommended that you reduce the input cap to whatever you find reasonable (being as it defaults to 1 MW, which is the entirety of the stock power supply) and activate and configure the shield BEFORE you need it. <BR><BR>The shield takes some time to expand its range to the desired specifications, and on top of that, under the default low power setting, takes around 40 seconds to spool up. Once it is active, the fully charged internal capacitors will last for a few minutes before depleting fully. You can increase the passive energy use to decrease the spool up time, but it also uses the stored energy much faster, so, that is not recommended except in dire emergencies.<BR><BR>So, this shield is not intended to be run indefinitely, unless you seriously beef up the ship&#39;s engine and power supply.<BR><BR>Fortunately, if you&#39;ve got a good pilot, you shouldn&#39;t really need the shield generator except in rare cases and only for short distances. Still, it is a good idea to configure the shield to be ready before you need it.<BR><BR>Good luck out there - <I>Budly Gregington</I>"

/obj/item/book/manual/sd_guide
	name = "Stellar Delight User's Guide"
	icon = 'icons/obj/library.dmi'
	icon_state ="newscodex"
	item_state = "newscodex"
	author = "Central Command"		 // Who wrote the thing, can be changed by pen or PC. It is not automatically assigned
	title = "Stellar Delight User's Guide"
	dat = {"<html>
				<head>
				<style>
				h1 {font-size: 18px; margin: 15px 0px 5px;}
				h2 {font-size: 15px; margin: 15px 0px 5px;}
				h3 {font-size: 13px; margin: 15px 0px 5px;}
				li {margin: 2px 0px 2px 15px;}
				ul {margin: 5px; padding: 0px;}
				ol {margin: 5px; padding: 0px 15px;}
				body {font-size: 13px; font-family: Verdana;}
				</style>
				</head>
				<body>

				<h1>Stellar Delight Operations</h1>
				<br><br>
				Welcome to the Stellar Delight! Before you get started there are a few things you ought to know.
				<br><br>
				The Stellar Delight is a Nanotrasen response vessel operating in the Virgo-Erigone system. It's primary duty is in answering calls for help, investigating anomalies in space around the system, and generally responding to requests from Central Command or whoever else needs the services the vessel can provide. It has fully functioning security, medical, and research facilities, as well as a host of civillian facilities, in addition to the standard things one might expect to find on such a ship. That is to say, the ship doesn't have a highly defined specialization, it is just as capable as a small space station might be.
				<br><br>
				Notably though, there are some research facilities that are not safe to carry around. There is a refurbished Aerostat that has been set up over Virgo 2 that posesses a number of different, more dangerous research facilities.  The command staff of this vessel has access to its docking codes in their offices.
				<br><br>
				Mining and Exploration will probably also want to disembark to do their respective duties.
				<br><br>
				The ship is ordinarily protected from many space hazards by an array of point defense turrets, however, it should be noted that this defense network is not infallible. If the ship encounters a dangerous environment, occasionally hazardous material may slip past the network and damage the ship.
				<br><br><br>
				<h1>Before Moving the Ship</h1>
				<br><br>
				The ship requires power to fuel and run its engines and sensors. While there may be some charge in the ship at the start of the shift, it is <b>HIGHLY RECOMMENDED</b> that the engine be started before attempting to move the ship. If any of the components responsible for moving the ship lose power (including but not limited to the helm control console and the thrusters), then you will be incapable of adjusting the ship's speed or heading until the problem is resolved.
				<br><br>
				Additionally, the shield generator should be configured before the ship moves, as it takes time to calibrate before it can be activated. The shield should not be run indefinitely however, as it uses more power than the ship ordinarily generates. You can however activate it for a short time if you know that you need to proceed through a dangerous reigon of space. For more information, see the configuration guide sheet in the shield control room on deck 3, aft of the Command Office section.
				<br><br><br>
				<h1>Starting and Moving the Ship</h1>
				<br><br>
				The ship can of course move around on its own, but a few steps need to/should be taken before you can do so.
				<br><br>
				-FIRST. <b>You should appoint a pilot.</b> If there isn't a pilot, or the pilot isn't responding, you should fax for a pilot. If no pilots respond to the fax within a reasonable timeframe, then, if you are qualified to fly Nanotrasen spacecraft you may fly the ship. Appointing a pilot to the bridge however should always be done even if you know how to fly and have access to the helm control console. <i><b>Refusing to attempt to appoint a pilot and just flying the ship yourself can be grounds for demotion to pilot.</i></b>
				<br><br>
				-SECOND. In order for the ship to move one must start the engines. The ship's fuel pump in Atmospherics must be turned on and configured. Atmospheric technicians may elect to modify the fuel mix to help the ship go faster or make the fuel last longer. Either way, once the fuel pump is on, you may use the engine control console on the bridge to activate the engines.
				<br><br>
				Once these steps have been taken, the helm control console should respond to input commands from the pilot.
				<br><br><br>
				<h1>Disembarking</h1>
				<br><br>
				Being a response vessel, the Stellar Delight has 3 shuttles in total.
				<br><br>
				The mining and exploration shuttles are located in the aft of deck 1 between their respective departments. Both of these shuttles are short jump shuttles, meaning, they are not suitable for more than ferrying people back and forth between the ship and the present destination. They do have a small range that they can traverse in their bluespace hops, but they must be within one 'grid square' of a suitable landing site to jump. As such, it is recommended that you avoid flying away from wherever either of these shuttles are without establishing a flight plan with the away teams to indicate a time of returning. In cases where the mining team and the exploration team want to go to different places, it may be necessary to fly from one location to the other now and then to facilitate both operations. However, it is recommended that exploration and mining be encouraged to enter the same operations areas, as the mining team is poorly armed, and the exploration team is ideally equipped for offsite defense and support of ship personnel.
				<br><br>
				There is also the Starstuff, a long range capable shuttle which is ordinarily docked on the port landing pad of deck 3. This shuttle is meant for general crew transport, but does require a pilot to be flown.
				<br><br>
				In cases where the shuttles will be docking with another facility, such as the Science outpost on the Virgo 2 Aerostat, docking codes may be required in order to be accessed. Anywhere requiring such codes will need to have them entered into the given shuttle's short jump console. It is recommended that anyone operating such a shuttle take note of the Stellar Delight's docking codes, as they will need them to dock with the ship. Any Nanotrasen owned facility that requires them that your ship has authorization to access will have the codes stored in the Command Offices.
				<br><br>
				A final note on disembarking. While it may not necessarily be their job to do so, it is highly encouraged for the Command staff to attempt to involve volunteers in off ship operations as necessary. Just make sure to let let it be known what kind of operation is happening when you ask. This being a response ship, it is very good to get as much help to handle whatever the issue is as thoroughly as possible.
				<br><br>
				All that said, have a safe trip. - Central Command Officer <i>Alyssa Trems</i>				</body>
			</html>
			"}

/obj/item/multitool/scioutpost
	name = "science outpost linked multitool"
	desc = "It has the data for the science outpost's quantum pad pre-loaded... assuming you didn't override it."

/obj/item/multitool/scioutpost/Initialize(mapload)
	. = ..()
	for(var/obj/machinery/power/quantumpad/scioutpost/outpost in world)
		connectable = outpost
		if(connectable)
			icon_state = "multitool_red"
		return

/obj/machinery/power/quantumpad/scioutpost

//Special map objects
/obj/effect/landmark/map_data/virgo3b
	height = 5

/obj/machinery/atmospherics/unary/vent_pump/positive
	use_power = USE_POWER_IDLE
	icon_state = "map_vent_out"
	external_pressure_bound = ONE_ATMOSPHERE * 1.1

/obj/machinery/computer/shuttle_control/aerostat_shuttle
	name = "aerostat ferry control console"
	shuttle_tag = "Aerostat Ferry"

/obj/tether_away_spawner/aerostat_inside
	name = "Aerostat Indoors Spawner"
	faction = FACTION_AEROSTAT_INSIDE
	atmos_comp = TRUE
	prob_spawn = 100
	prob_fall = 50
	//guard = 20
	mobs_to_pick_from = list(
		/mob/living/simple_mob/mechanical/hivebot/ranged_damage/basic = 3,
		/mob/living/simple_mob/mechanical/hivebot/ranged_damage/ion = 1,
		/mob/living/simple_mob/mechanical/hivebot/ranged_damage/laser = 3,
		/mob/living/simple_mob/vore/aggressive/corrupthound = 1
	)

/obj/tether_away_spawner/aerostat_surface
	name = "Aerostat Surface Spawner"
	faction = FACTION_AEROSTAT_SURFACE
	atmos_comp = TRUE
	prob_spawn = 100
	prob_fall = 30
	//guard = 20
	mobs_to_pick_from = list(
		/mob/living/simple_mob/vore/jelly = 6,
		/mob/living/simple_mob/mechanical/viscerator = 6,
		/mob/living/simple_mob/vore/aggressive/corrupthound = 3,
		/mob/living/simple_mob/vore/oregrub = 2,
		/mob/living/simple_mob/vore/oregrub/lava = 1
	)

/obj/structure/old_roboprinter
	name = "old drone fabricator"
	desc = "Built like a tank, still working after so many years."
	icon = 'icons/obj/machines/drone_fab.dmi'
	icon_state = "drone_fab_idle"
	anchored = TRUE
	density = TRUE

/obj/structure/metal_edge
	name = "metal underside"
	desc = "A metal wall that extends downwards."
	icon = 'icons/turf/cliff.dmi'
	icon_state = "metal"
	anchored = TRUE
	density = FALSE


// === merged from maps/ during hard-fork flatten ===
/////////////////////////////////////////////////////////////////////////////////////
// Add objects that will be used in ALL away missions. Keep area specific stuff separate.
/obj/sc_away_spawner
	name = "RENAME ME, JERK"
	desc = "Spawns the mobs!"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	invisibility = INVISIBILITY_ABSTRACT
	mouse_opacity = 0
	density = 0
	anchored = 1

	//Weighted with values (not %chance, but relative weight)
	//Can be left value-less for all equally likely
	var/list/mobs_to_pick_from

	//When the below chance fails, the spawner is marked as depleted and stops spawning
	var/prob_spawn = 100	//Chance of spawning a mob whenever they don't have one
	var/prob_fall = 5		//Above decreases by this much each time one spawns

	//Settings to help mappers/coders have their mobs do what they want in this case
	var/faction				//To prevent infighting if it spawns various mobs, set a faction
	var/atmos_comp			//TRUE will set all their survivability to be within 20% of the current air
	//var/guard				//# will set the mobs to remain nearby their spawn point within this dist

	//Internal use only
	var/mob/living/simple_mob/my_mob
	var/depleted = FALSE

/obj/sc_away_spawner/Initialize(mapload)
	. = ..()

	if(!LAZYLEN(mobs_to_pick_from))
		log_mapping("Mob spawner at [x],[y],[z] ([get_area(src)]) had no mobs_to_pick_from set on it!")
		flags |= ATOM_INITIALIZED
		return INITIALIZE_HINT_QDEL
	START_PROCESSING(SSobj, src)

/obj/sc_away_spawner/process()
	if(my_mob && my_mob.stat != DEAD)
		return //No need

	if(LAZYLEN(loc.human_mobs(world.view)))
		return //I'll wait.

	if(prob(prob_spawn))
		prob_spawn -= prob_fall
		var/picked_type = pickweight(mobs_to_pick_from)
		my_mob = new picked_type(get_turf(src))
		my_mob.low_priority = TRUE

		if(faction)
			my_mob.faction = faction

		if(atmos_comp)
			var/turf/T = get_turf(src)
			var/datum/gas_mixture/env = T.return_air()
			if(env)
				var/env_temp = env.return_temperature()
				my_mob.minbodytemp = env_temp * 0.8
				my_mob.maxbodytemp = env_temp * 1.2

				my_mob.min_oxy = LINDA_GAS_AMT(env, GAS_O2) * 0.8
				my_mob.min_tox = LINDA_GAS_AMT(env, GAS_PHORON) * 0.8
				my_mob.min_n2 = LINDA_GAS_AMT(env, GAS_N2) * 0.8
				my_mob.min_co2 = LINDA_GAS_AMT(env, GAS_CO2) * 0.8
				my_mob.max_oxy = LINDA_GAS_AMT(env, GAS_O2) * 1.2
				my_mob.max_tox = LINDA_GAS_AMT(env, GAS_PHORON) * 1.2
				my_mob.max_n2 = LINDA_GAS_AMT(env, GAS_N2) * 1.2
				my_mob.max_co2 = LINDA_GAS_AMT(env, GAS_CO2) * 1.2
/* // AI TEMPORARY REMOVAL
		if(guard)
			my_mob.returns_home = TRUE
			my_mob.wander_distance = guard
*/
		return
	else
		STOP_PROCESSING(SSobj, src)
		depleted = TRUE
		return

/obj/effect/map_effect/portal/master/side_a/retreat_west
	portal_id = "retreat_west"

/obj/effect/map_effect/portal/master/side_b/retreat_west
	portal_id = "retreat_west"

/obj/effect/map_effect/portal/master/side_a/retreat_east
	portal_id = "retreat_east"

/obj/effect/map_effect/portal/master/side_b/retreat_east
	portal_id = "retreat_east"

/obj/machinery/smartfridge/survival_pod/casino
	icon = 'icons/obj/vending.dmi'
	icon_base = "smartfridge"
	icon_contents = "boxes"
	icon_state = "smartfridge"
	name = "Advanced storage"
