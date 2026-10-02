GLOBAL_DATUM_INIT(solo, /datum/solo, new)
GLOBAL_DATUM_INIT(multi_line,
	/datum/solo_multi,
	new)
/datum/solo
	var/list/a = list()
/datum/solo_multi
	var/list/c = list()
/datum/solo_hidden
	var/list/e = list()
/datum/world_service
	var/list/root = list()
/datum/world_service/thing
	var/list/a = list()
/datum/world_service/thing/deeper
	var/list/b = list()
/datum/world_service/thing/var/list/path_style = list()
/datum/world_servicex
	var/list/near_miss = list()
/datum/controller
	var/list/root = list()
/datum/controller/x
	var/list/c = list()
/datum/controllers
	var/list/d = list()
/datum/world_service/annotated
	var/list/never_asked = list() // ALLOW(instance_list): a singleton never asks the question, so this is unused
