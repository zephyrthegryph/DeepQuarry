/mob/living/silicon/robot/proc/transform_with_anim()
	do_transform_animation()

/mob/living/silicon/robot/proc/do_transform_animation()
	notransform = TRUE
	dir = SOUTH
	var/obj/effect/temp_visual/decoy/fading/fivesecond/ANM = new /obj/effect/temp_visual/decoy/fading/fivesecond(loc, src)
	ANM.layer = layer - 0.01
	new /obj/effect/temp_visual/small_smoke(loc)
	alpha = 0
	animate(src, alpha = 255, time = 50)
	transform_prev_lockcharge = lockcharge
	SetLockdown(1)
	set_anchored(TRUE)
	set_transform_sounds_left(7) // six drill sounds, then the lockdown ends

/// Transform animation in progress: drill sounds still to play, plus one for the end of the lockdown.
OM_FIELD(/mob/living/silicon/robot, transform_sounds_left, 0, CHANGE_MOB_CONDITIONS)
/// The lockdown state from before the transform animation, restored when it ends.
/mob/living/silicon/robot/var/transform_prev_lockcharge
DECLARE_REPEAT(/mob/living/silicon/robot, 0.8 SECONDS, transform_animation_sounds, "transform_sounds_left")

/// DECLARE_REPEAT while the transform animation runs: a drill sound, or the end of the lockdown.
/mob/living/silicon/robot/proc/transform_animation_sounds()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(transform_sounds_left > 1)
		play_sfx(src, SFX_ITEMS_DRILL_USE)
		set_transform_sounds_left(transform_sounds_left - 1)
		return
	set_transform_sounds_left(0)
	transform_animation_end_lockdown(transform_prev_lockcharge)
	return REPEAT_STOP

/mob/living/silicon/robot/proc/transform_animation_end_lockdown(prev_lockcharge)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!prev_lockcharge)
		SetLockdown(0)
	set_anchored(FALSE)
	notransform = FALSE
