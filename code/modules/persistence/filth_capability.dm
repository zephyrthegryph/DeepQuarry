// Filth participates in persistence using the actual native initialization context.
CAPABILITY_TYPE(persistent_filth, CAP_PERSISTENT_FILTH, /datum/capability/persistent_filth, key = NONE, track_type = /datum/persistent/filth)

/datum/capability/persistent_filth
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/persistent_filth/on_holder_init(datum/act/eval/A)
	var/atom/holder = A.holder
	if(!isatom(holder))
		return
	if(!A.mapload || !CONFIG_GET(flag/persistence_ignore_mapload))
		SSpersistence.track_value(holder, track_type)
