/datum/decl/emote/visible/spin
	key = "spin"
	check_restraints = TRUE
	emote_message_3p = "spins!"
	emote_delay = 2 SECONDS

/datum/decl/emote/visible/spin/do_extra(mob/user)
	if(istype(user))
		user.spin(20, 1)

/datum/decl/emote/visible/sidestep
	key = "sidestep"
	check_restraints = TRUE
	emote_message_3p = "steps rhythmically and moves side to side."

/datum/decl/emote/visible/sidestep/do_extra(mob/user)
	if(istype(user))
		animate(user, pixel_x = 5, time = 5)
		om_after(user, 0.3 SECONDS, GLOBAL_PROC_REF(emote_sidestep_back), user)

/datum/decl/emote/visible/flip
	key = "flip"
	emote_message_1p = "You do a flip!"
	emote_message_3p = "does a flip!"
	emote_sound = SFX_EFFECTS_BODYFALL4

/datum/decl/emote/visible/flip/do_extra(mob/user)
	. = ..()
	// Fancy flips
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.handle_flip_vr()
	else if(istype(user))
		user.SpinAnimation(7,1)

/datum/decl/emote/visible/flip/slip
	key = "sflip"
	emote_message_1p = "You barely avoid falling over!"
	emote_message_3p = "barely avoids falling over!"

/datum/decl/emote/visible/floorspin
	key = "floorspin"
	emote_message_1p = "You spin around on the floor!"
	emote_message_3p = "spins around on the floor!"
	var/static/list/spin_dirs = list(
		NORTH,
		SOUTH,
		EAST,
		WEST,
		EAST,
		SOUTH,
		NORTH,
		SOUTH,
		EAST,
		WEST,
		EAST,
		SOUTH,
		NORTH,
		SOUTH,
		EAST,
		WEST,
		EAST,
		SOUTH
	)

/datum/decl/emote/visible/floorspin/proc/spin_dir(mob/user)
	om_after_stagger(user, spin_dirs, 0.1 SECONDS, TYPE_PROC_REF(/atom, set_dir))

/datum/decl/emote/visible/floorspin/proc/spin_anim(mob/user)
	om_after(user, 0.1 SECONDS, TYPE_PROC_REF(/atom, SpinAnimation), 10, 1)

/proc/emote_sidestep_back(mob/user)
	animate(user, pixel_x = -5, time = 5)
	animate(pixel_x = user.default_pixel_x, pixel_y = user.default_pixel_x, time = 2)

/datum/decl/emote/visible/floorspin/do_extra(mob/user)
	. = ..()
	if(istype(user))
		spin_dir(user)
		spin_anim(user)
