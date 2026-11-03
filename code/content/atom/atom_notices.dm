// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// From SSatoms InitAtom, only when the atom was not deleted, did not fail initialization and has a loc: (created, mapload)
ACTION(atom_after_successful_initialized_on, created, mapload, FIXED, notice = /datum/notice/atom_after_successful_initialized_on)

/// From /atom/atom_break(damage_flag): the atom crossed its integrity_failure threshold. (damage_flag)
ACTION(atom_broken, damage_flag, FIXED, notice = /datum/notice/atom_broken)

/// From base of atom/setDir(): (old_dir, new_dir). Called before the direction changes.
ACTION(atom_dir_change, old_dir, new_dir, FIXED, notice = /datum/notice/atom_dir_change)

/// From base of atom/emp_act(severity): (severity, protection)
ACTION(atom_emp_act, severity, protection, FIXED, notice = /datum/notice/atom_emp_act)

/// From base of atom/Entered(): (atom/movable/arrived, atom/old_loc, list/atom/old_locs)
ACTION(atom_entered, arrived, old_loc, FIXED, notice = /datum/notice/atom_entered)

/// Sent from the atom that just Entered src. From base of atom/Entered(): (/atom/destination, atom/old_loc, list/atom/old_locs)
ACTION(atom_entering, destination, old_loc, FIXED, notice = /datum/notice/atom_entering)

/// From base of atom/Exited(): `gone` left the atom for `new_loc`.
ACTION(atom_exited, gone, new_loc, FIXED, notice = /datum/notice/atom_exited)

/// From base of [/atom/proc/extinguish]: the atom's fire was put out (a burning mob's fire_stacks status hears it on its owner).
ACTION(atom_extinguish, FIXED, notice = /datum/notice/atom_extinguish)

/// From base of atom/fire_act(): (exposed_temperature, exposed_volume)
ACTION(atom_fire_act, exposed_temperature, exposed_volume, FIXED, notice = /datum/notice/atom_fire_act)

/// From internal loop in /atom/proc/propagate_radiation_pulse: (atom/pulse_source)
ACTION(atom_propagate_rad_pulse, pulse_source, FIXED, notice = /datum/notice/atom_propagate_rad_pulse)

/// From base of [/atom/proc/take_damage], once the damage landed (after armour): (damage_amount, damage_type, damage_flag, sound_effect, attack_dir, aurmor_penetration)
ACTION(atom_take_damage, damage_amount, damage_type, damage_flag, sound_effect, attack_dir, aurmor_penetration, FIXED, notice = /datum/notice/atom_take_damage)

/// From base of atom/used_in_craft(): (atom/result)
ACTION(atom_used_in_craft, result_, FIXED, notice = /datum/notice/atom_used_in_craft)

/// Notification: `user` examined the atom. Handlers
/// append lines to `texts`, the examine output list.
ACTION(examine, user, texts, FIXED, notice = /datum/notice/examine)

/// Notification: the atom was hit by thrown `source`.
ACTION(hitby, source_, throwingdatum, FIXED, notice = /datum/notice/hitby)
