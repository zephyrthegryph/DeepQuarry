// Concrete carriers of lifecycle declarations; the engine calls its virtual hooks.
/atom/movable/lifeform_place(atom/holder)
	return forceMove(holder)

/mob/lifeform_learn(language)
	return add_language(language)

/datum/registry_mirror_join(id)
	var/datum/registry/legacy = build_registries()[id]
	if(legacy && !legacy.has(src))
		legacy.add(src)

/datum/registry_mirror_leave(id)
	var/datum/registry/legacy = build_registries()[id]
	if(legacy?.has(src))
		legacy.remove(src)
