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
/mob/living/silicon/robot/var/transform_sounds_left = 0
TRACKED(/mob/living/silicon/robot, transform_sounds_left)
/// The lockdown state from before the transform animation, restored when it ends.
/mob/living/silicon/robot/var/transform_prev_lockcharge

/// A drill sound, or the end of the lockdown (its every() runs while transform_sounds_left is set).
/mob/living/silicon/robot/proc/transform_animation_sounds(datum/act/A)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(transform_sounds_left > 1)
		play_sfx(src, SFX_ITEMS_DRILL_USE)
		set_transform_sounds_left(transform_sounds_left - 1)
		return
	set_transform_sounds_left(0)
	transform_animation_end_lockdown(transform_prev_lockcharge)

/mob/living/silicon/robot/proc/transform_animation_end_lockdown(prev_lockcharge)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!prev_lockcharge)
		SetLockdown(0)
	set_anchored(FALSE)
	notransform = FALSE
