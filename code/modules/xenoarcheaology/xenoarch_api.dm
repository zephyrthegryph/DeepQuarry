// The xenoarchaeology system's API (code/modules/xenoarcheaology/xenoarch_service.dm declares the system).
//
//   SSxenoarch.continual_generation(user)   a z-level ran out of large artifacts: place more where `user` stands

/datum/system/xenoarch/proc/continual_generation(mob/living/user)
	generate_more_artifacts(user)
