/turf/snow
	name = "snow"

	dynamic_lighting = 0
	icon = 'icons/turf/snow_new.dmi'
	icon_state = "snow"

	oxygen = MOLES_O2STANDARD * 1.15
	nitrogen = MOLES_N2STANDARD * 1.15

	initial_temperature = TN60C
	var/list/crossed_dirs

TRACKED(/turf/snow, crossed_dirs)

/turf/snow/Entered(atom/A)
	if(ismob(A) && !A.is_incorporeal())
		var/mdir = "[A.dir]"
		var/list/footprints = crossed_dirs ? crossed_dirs.Copy() : list()
		footprints[mdir] = min((footprints[mdir] || 0) + 1, FOOTSTEP_SPRITE_AMT)
		set_crossed_dirs(footprints)

	. = ..()

/turf/snow/draw(datum/look/look)
	..()
	for(var/d in crossed_dirs)
		var/amt = LAZYACCESS(crossed_dirs, d)

		for(var/i in 1 to amt)
			look.overlay(look_overlay_image(icon, "footprint[i]", dir = text2num(d)))

