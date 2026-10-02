GLOBAL_DATUM_INIT(solo, /datum/solo, new)
GLOBAL_DATUM_INIT(multi_line,
	/datum/solo_multi,
	new)
GLOBAL_DATUM_INIT(bare, /datum, new)
GLOBAL_DATUM_INIT(not_new, /datum/solo_null, null)
/datum/solo
	var/list/a = list()
/datum/solo/child
	var/list/b = list()
/datum/solo_multi
	var/list/c = list()
/datum/solo_null
	var/list/d = list()
/datum/solo_hidden
	var/list/e = list()
/datum/solo_maps
	var/list/f = list()
/datum/world_service
	var/list/root = list()
/datum/world_service/thing
	var/list/a = list()
/datum/world_service/thing/deeper
	var/list/b = list()
/datum/world_servicex
	var/list/near_miss = list()
/datum/controller
	var/list/root = list()
/datum/controller/x
	var/list/c = list()
/datum/controllers
	var/list/d = list()
