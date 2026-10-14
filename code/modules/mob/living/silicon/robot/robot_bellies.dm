/mob/living/silicon/robot/proc/update_multibelly()
	var/list/icon_bellies = list() //Clear any belly options that may not exist now
	var/list/capacity = list()
	var/list/fullness = list()
	vore_icon_bellies = icon_bellies
	vore_capacity_ex = capacity
	set_vore_fullness_ex(fullness)
	if(!sprite_datum) // A22
		set_vore_light_states(null) // A22: no stale light keys from the previous sprite
		return
	if(length(sprite_datum.belly_capacity_list))
		for(var/belly in sprite_datum.belly_capacity_list) //vore icons list only contains a list of names with no associated data
			capacity[belly] = LAZYACCESS(sprite_datum.belly_capacity_list, belly) //I dont know why but this wasnt working when I just
			fullness[belly] = 0 //set the lists equal to the old lists
			icon_bellies += belly
	else if(sprite_datum.has_vore_belly_sprites)
		capacity = list("sleeper" = 1)
		fullness = list("sleeper" = 0)
		icon_bellies = list("sleeper")
		if(sprite_datum.has_sleeper_light_indicator)
			sprite_datum.belly_light_list = list("sleeper")
	vore_icon_bellies = icon_bellies
	vore_capacity_ex = capacity
	set_vore_fullness_ex(fullness)
	PUBLISH(src, belly_change) //Set how full the newly defined bellies are, if they're already full; the belly lights follow it

/// A belly's struggle sprite shows over the belly for a moment.
/mob/living/silicon/robot/vs_animate(belly_class)
	if(!sprite_datum.has_vore_struggle_sprite)
		return
	if(belly_class == "sleeper" && !belly_display_fullness(belly_class))
		return
	var/vs_fullness = vore_fullness_ex[belly_class]
	if(resting)
		look_flash(src, "[sprite_datum.get_belly_resting_overlay(src, vs_fullness, belly_class)]-struggle", 1.2 SECONDS)
	else
		look_flash(src, "[sprite_datum.get_belly_overlay(src, vs_fullness, belly_class)]-struggle", 1.2 SECONDS)
