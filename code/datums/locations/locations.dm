/datum/locations
	var/name
	var/desc
	var/list/contents = list()
	var/parent

/datum/locations/New(creator)
	if(creator)
		parent = creator

//Galaxy

/datum/locations/milky_way
	name = "Milky Way Galaxy"
	desc = "The galaxy we all live in."

/datum/locations/milky_way/New()
	contents.Add(
		new /datum/locations/sol(src),
		new /datum/locations/tau_ceti(src),
		new /datum/locations/nyx(src),
		new /datum/locations/qerrvallis(src),
		new /datum/locations/s_randarr(src),
		new /datum/locations/uueoa_esa(src),
		new /datum/locations/vir(src)
		)

