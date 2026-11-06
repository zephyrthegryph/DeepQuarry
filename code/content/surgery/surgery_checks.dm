// check if mob is lying down on something we can operate him on.
// The RNG with table/rollerbeds comes into play in the surgery ops (surgery_ops.dm) so that a slip can be used instead.
/// `stance` is the stance of the interaction doing the surgery: self-surgery only when helping.
/proc/can_operate(mob/living/carbon/M, mob/living/user, stance)
	if(M != user)
		. = M.lying
	else if(user && kind_of(user).self_surgery && stance == I_HELP)    // You can, technically, always operate on yourself after standing still. Inadvised, but you can.
		. = TRUE
	return .

// Returns an instance of a valid surgery surface.
/mob/living/proc/get_surgery_cleanliness(mob/living/user)
	if(!lying && user != src)
		return null // Not lying down means no surface (blocks surgery)
	var/cleanliness = 0
	for(var/obj/O in contents_of(loc)) // Looks for the best surface.
		if(rules_of(O).surgery_cleanliness)
			if(!cleanliness || cleanliness < rules_of(O).surgery_cleanliness)
				cleanliness = rules_of(O).surgery_cleanliness
	if(!cleanliness) //We have no good objects on the turf. Time to check the floor!
		var/turf/T = get_turf(src)
		if(dq_get_was_bloodied(T)) //floor is contaminated
			return 0
		//Turf generally start with a germ level of 110 and cap out at 200.
		//Can use sterilizine to lower germs of the floor, or space cleaner.
		cleanliness = CLAMP(100 - T.germs(), 0, 25)

	return cleanliness
