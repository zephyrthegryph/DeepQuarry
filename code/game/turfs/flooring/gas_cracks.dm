/************************************************************************
 * Mapper information:
 * Intended for POI spawns, surrounded by mineral turf walls that DO NOT CAVEGEN
 * These turfs must be surrounded by atmos of the exact same type, or be isolated
 * by walls. They may be placed next to eachother freely. They do not use the planet's
 * atmos. They start as compressed pockets of gas for miners to uncover.
 *
 * If these are given a /sif or other planet override they should be safe to use anywhere.
 * As these cracks do not produce gas on their own. They just have the atmos at init, and
 * produce gas when mined with a deep drill rig.
 *
 * Be careful when mapping them to avoid active edges.
************************************************************************/

/turf/simulated/floor/gas_crack
	icon = 'icons/turf/flooring/asteroid.dmi'
	desc = "Rough sand with a huge crack. It seems to be nothing in particular."
	description_info = "Fluid pumps can be used to frack for reagents in nearby ores, and a mining drill can also bore through trapped gas deposits beneath it."
	name = "cracked sand"
	icon_state = "asteroid_cracked"
	initial_flooring = /datum/decl/flooring/rock
	var/list/gas_type = null
	oxygen = 0
	nitrogen = 0

/turf/simulated/floor/gas_crack/pump_reagents(datum/reagents/R, volume)
	// pick random turfs in range, then use their deep ores to get some extra reagents
	var/i = 0
	while(i++ < 4) // Do this a few times
		var/turf/simulated/mineral/M = pick(orange(5,src))
		if(!istype(M) || !M.resources)
			return
		for(var/metal in GLOB.deepore_fracking_reagents)
			if(!(metal in M.resources))
				continue
			var/list/ore_list = GLOB.deepore_fracking_reagents[metal]
			if(!ore_list || !ore_list.len)
				continue
			if(prob(60))
				var/reagent_id = pick(ore_list)
				if(reagent_id)
					R.add_reagent(reagent_id, round(volume, 0.1))

