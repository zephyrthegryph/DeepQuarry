/turf/snow
	name = "snow"

	dynamic_lighting = 0
	icon = 'icons/turf/snow_new.dmi'
	icon_state = "snow"

	oxygen = MOLES_O2STANDARD * 1.15
	nitrogen = MOLES_N2STANDARD * 1.15

	temperature = TN60C
	var/list/crossed_dirs

/turf/snow/Entered(atom/A)
	if(ismob(A) && !A.is_incorporeal())
		var/mdir = "[A.dir]"
		if(LAZYACCESS(crossed_dirs, mdir))
			LAZYSET(crossed_dirs, mdir, min(LAZYACCESS(crossed_dirs, mdir) + 1, FOOTSTEP_SPRITE_AMT))
		else
			LAZYSET(crossed_dirs, mdir, 1)

		update_icon()

	. = ..()

DECLARE_APPEARANCE_PROC(/turf/snow, TYPE_PROC_REF(/atom, appearance_overlays), list())
/turf/snow/appearance_overlays()
	. = list()
	for(var/d in crossed_dirs)
		var/amt = LAZYACCESS(crossed_dirs, d)

		for(var/i in 1 to amt)
			. += image(icon, "footprint[i]", text2num(d))

