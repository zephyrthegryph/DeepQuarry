/obj/effect/decal/cleanable/blood/gibs/robot
	name = "robot debris"
	desc = "It's a useless heap of junk... <i>or is it?</i>"
	icon = 'icons/mob/robots.dmi'
	icon_state = "gib1"
	basecolor = SYNTH_BLOOD_COLOUR
	random_icon_states = list("gib1", "gib2", "gib3", "gib4", "gib5", "gib6", "gib7")
	generic_filth = FALSE
	persistent = FALSE

/// Drawn in the picture's own colours.
/obj/effect/decal/cleanable/blood/gibs/robot/wet_color()
	return "#FFFFFF"

/obj/effect/decal/cleanable/blood/gibs/robot/cleanable_look(datum/look/look)
	look.set_color(shown_color())
	dried_look(look)
	janitor_hud(look)

/obj/effect/decal/cleanable/blood/gibs/robot/dry()	//pieces of robots do not dry up like
	return

/obj/effect/decal/cleanable/blood/gibs/robot/streak(list/directions)
	streak_async(directions)

/obj/effect/decal/cleanable/blood/gibs/robot/streak_splat()
	if (prob(40))
		new /obj/effect/decal/cleanable/blood/oil(src.loc)
	else if (prob(10))
		fx_sparks(src, 3)

/obj/effect/decal/cleanable/blood/gibs/robot/limb
	random_icon_states = list("gibarm", "gibleg")

/obj/effect/decal/cleanable/blood/gibs/robot/up
	random_icon_states = list("gib1", "gib2", "gib3", "gib4", "gib5", "gib6", "gib7","gibup1","gibup1") //2:7 is close enough to 1:4

/obj/effect/decal/cleanable/blood/gibs/robot/down
	random_icon_states = list("gib1", "gib2", "gib3", "gib4", "gib5", "gib6", "gib7","gibdown1","gibdown1") //2:7 is close enough to 1:4

/obj/effect/decal/cleanable/blood/oil
	basecolor = SYNTH_BLOOD_COLOUR
	generic_filth = FALSE
	persistent = FALSE

/obj/effect/decal/cleanable/blood/oil/dry()
	return

/obj/effect/decal/cleanable/blood/oil/streak
	random_icon_states = list("mgibbl1", "mgibbl2", "mgibbl3", "mgibbl4", "mgibbl5")
	amount = 2
