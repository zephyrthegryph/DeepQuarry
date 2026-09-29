/proc/gibs(atom/location, datum/dna/MobDNA, gibber_type = /obj/effect/gibspawner/generic, fleshcolor, bloodcolor)
	new gibber_type(location,MobDNA,fleshcolor,bloodcolor)

/obj/effect/gibspawner
	var/sparks = 0 //whether sparks spread on Gib()
	var/list/gibtypes
	var/list/gibamounts
	var/list/gibdirections //of lists
	var/fleshcolor //Used for gibbed humans.
	var/bloodcolor //Used for gibbed humans.
	invisibility = INVISIBILITY_BADMIN // So a badmin can go view these by changing their see_invisible.
	icon = 'icons/effects/map_effects.dmi'
	icon_state = "gibspawn"

/obj/effect/gibspawner/Initialize(mapload, datum/dna/MobDNA, fleshcolor, bloodcolor)
	. = ..()

	if(fleshcolor) src.fleshcolor = fleshcolor
	if(bloodcolor) src.bloodcolor = bloodcolor
	Gib(loc,MobDNA)
	return INITIALIZE_HINT_QDEL

/obj/effect/gibspawner/proc/Gib(atom/location, datum/dna/MobDNA = null)
	if(length(gibtypes) != length(gibamounts) || length(gibamounts) != length(gibdirections))
		to_chat(world, span_filter_system(span_warning("Gib list length mismatch!")))
		log_world("Gib list length mismatch!")
		return

	var/obj/effect/decal/cleanable/blood/gibs/gib = null

	if(sparks)
		fx_sparks(get_turf(location), 2)

	for(var/i = 1, i<= length(gibtypes), i++)
		if(LAZYACCESS(gibamounts, i))
			for(var/j = 1, j<= LAZYACCESS(gibamounts, i), j++)
				var/gibType = LAZYACCESS(gibtypes, i)
				gib = new gibType(location)

				// Apply human species colouration to masks.
				if(fleshcolor)
					gib.fleshcolor = fleshcolor
				if(bloodcolor)
					gib.basecolor = bloodcolor

				gib.update_icon()

				gib.init_forensic_data()
				gib.add_blooddna(MobDNA,null)

				if(istype(location,/turf/))
					var/list/directions = LAZYACCESS(gibdirections, i)
					if(directions.len)
						gib.streak(directions)
