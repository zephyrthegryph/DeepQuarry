// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// Called right after the atom changes the value of light_color to a different one, from base of [/atom/proc/set_light_color]: (old_color)
ACTION(atom_update_light_color, old_color, FIXED, notice = /datum/notice/atom_update_light_color)

/// Called right after the atom changes the value of light_flags to a different one, from base of [/atom/proc/set_light_flags]: (old_flags)
ACTION(atom_update_light_flags, old_flags, FIXED, notice = /datum/notice/atom_update_light_flags)

/// Called right after the atom changes the value of light_on to a different one, from base of [/atom/proc/set_light_on]: (old_value)
ACTION(atom_update_light_on, old_value, FIXED, notice = /datum/notice/atom_update_light_on)

/// Lighting: Called right after the atom changes the value of light_power to a different one, from base of [/atom/proc/set_light_power]: (old_power)
ACTION(atom_update_light_power, old_power, FIXED, notice = /datum/notice/atom_update_light_power)

/// Called right after the atom changes the value of light_range to a different one, from base of [/atom/proc/set_light_range]: (old_range)
ACTION(atom_update_light_range, old_range, FIXED, notice = /datum/notice/atom_update_light_range)
