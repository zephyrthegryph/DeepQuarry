/**
 * Possible 'state' options for change_state(state) are:
 * idle: Not doing anything, with yellow template exposed
 * work: busy doing work
 * pause: paused work
 */
// cruciform forge from Eris
/obj/structure/prop/machine/nt_cruciforge
	icon = 'icons/obj/props/decor.dmi'
	icon_state = "nt_cruciforge"

/obj/structure/prop/machine/nt_cruciforge/change_state(state)
	. = ..()
	switch(state)
		if("idle")
			set_icon_state("nt_cruciforge")
			flick("nt_cruciforge_finish", src) // 8ds
		if("work")
			set_icon_state("nt_cruciforge_work")
			flick("nt_cruciforge_start", src) // 8ds
		if("pause")
			set_icon_state("nt_cruciforge_pause")

/obj/structure/prop/machine/nt_cruciforge/starts_working
	icon_state = "nt_cruciforge_work"
