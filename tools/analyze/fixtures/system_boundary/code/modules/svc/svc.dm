GLOBAL_DATUM_INIT(foo_service, /datum/world_service/foo, new)
/datum/world_service/foo
/datum/world_service/foo/proc/in_folder()
	return GLOB.foo_service.state
