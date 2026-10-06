//So this is a bit weird, but I tried to make this as adaptable as I could
//There are two working parts of an overmap mob, but I made it look like there is only one as far as the players are concerned.
//The /obj/effect/overmap/visitable/simplemob is the part people will actually see. It follows the mob around and changes dir to look as mob-ish as it can.
//The /mob/living/simple_mob/vore/overmap is NOT VISIBLE normally, and is the part that actually does the work most of the time.
//Being a simplemob, the mob can wander around and affect the overmap in whatever way you might desire.
//Whatever it does, the /visitable/simplemob will follow it, and does all the functional parts relating to the OM
//including scanning, and housing Z levels people might land on.

//The MOB being invisible presents some problems though, which I am not entirely sure how to resolve
//Such as, being unable to be attacked by other mobs, and possibly unable to be attacked by players.
//This does not at all prevent the mob from attacking other things though
//so in general, please ensure that you never spawn these where players can ordinarily access them.

//The mob was made invisible though, because the sensors can't detect invisible objects, so when the /visitable/simplemob was made invisible
//it refused to show up on sensors, and a few simple changes to the sensors didn't rectify this. So, rather than adding in more spaghetti to make
//simplemobs scannable (WHICH I DID, AND IT WORKED SOMEHOW), Aronai and I found that this was the better solution for making all the parts function like I'd like.
//Since I also want it to be possible to land on the overmap object.

/////OM LANDMARK/////
/obj/effect/overmap/visitable/simplemob
	name = "unknown ship"
	icon = 'icons/obj/overmap.dmi'
	icon_state = "ship"
	scannable = TRUE
	known = FALSE
	in_space = FALSE				//Just cuz we don't want people getting here via map edge transitions normally.
	unknown_name = "unknown ship"
	unknown_state = "ship"

	var/mob/living/simple_mob/vore/overmap/parent_mob_type // a type path, never an instance
	var/mob/living/simple_mob/vore/overmap/parent

CAPABILITIES(/obj/effect/overmap/visitable/simplemob)
	param(nameof(parent), pos = 1, apply = PROC_REF(link_parent))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The marker of a mob made with no mob makes its own.
/obj/effect/overmap/visitable/simplemob/proc/link_parent(parent_mob)
	if(!parent_mob_type && !parent)
		log_and_message_admins("An improperly configured OM mob event tried to spawn, and was deleted.")
		spent(src)
		return
	if(!parent)
		var/mob/living/simple_mob/vore/overmap/P = new parent_mob_type(loc, src)
		rel_set(src, nameof(parent), P)
	om_mob_event_setup()

/obj/effect/overmap/visitable/simplemob/proc/om_mob_event_setup()
	scanner_desc = parent.scanner_desc
	observe(parent, /datum/notice/moved, src, then(PROC_REF(on_parent_moved)))
	skybox_pixel_x = rand(-100,100)
	if(known)
		name = initial(parent.name)
		icon = initial(parent.icon)
		icon_state = initial(parent.icon_state)
		color = initial(parent.color)
		desc = initial(parent.desc)

// Ownership is a tree: the mob owns its marker (child_om_marker, OWN);
// the marker's `parent` is only a relation back, cleared when the mob goes.

/obj/effect/overmap/visitable/simplemob/get_scan_data(mob/user)
	if(!known)
		known = TRUE
		name = initial(parent.name)
		icon = initial(parent.icon)
		icon_state = initial(parent.icon_state)
		color = initial(parent.color)
		desc = initial(parent.desc)

	var/dat = {"\[b\]Scan conducted at\[/b\]: [stationtime2text()] [stationdate2text()]\n\[b\]Grid coordinates\[/b\]: [x],[y]\n\n[scanner_desc]"}

	return dat

/obj/effect/overmap/visitable/simplemob/proc/on_parent_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	forceMove(parent.loc)
	set_dir(parent.dir)

/////OM MOB///// DO NOT SPAWN THESE ANYWHERE IN THE WORLD, THAT'S SCARY /////
/mob/living/simple_mob/vore/overmap
	invisibility = INVISIBILITY_ABSTRACT //We're making an overmap icon pretend to be a mob
	name = "DONT SPAWN ME"
	desc = "I'm a bad person I'm sorry"

	endurance = 100000
	movement_cooldown = 10

	see_in_dark = 10

	faction = FACTION_OVERMAP
	low_priority = FALSE
	devourable = FALSE
	digestable = FALSE

	harm_intent_damage = 1
	melee_damage_lower = 50
	melee_damage_upper = 100

	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	minbodytemp = 0
	maxbodytemp = 900

	mob_size = MOB_HUGE

	loot_list = list(/obj/random/underdark/uncertain)

	armor_spec = "melee=1000;bullet=1000;laser=1000;energy=1000;bomb=1000;bio=1000;rad=1000"

	var/scanner_desc
	var/obj/effect/overmap/visitable/simplemob/child_om_marker
	var/om_child_type
	var/shipvore = FALSE	//Enable this to allow the mob to eat spaceships by dragging them onto its sprite.

CAPABILITIES(/mob/living/simple_mob/vore/overmap)
	owns_one(nameof(child_om_marker), /obj/effect/overmap/visitable/simplemob)
	param(nameof(child_om_marker), pos = 1, apply = PROC_REF(link_marker))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A mob made with no marker makes its own.
/mob/living/simple_mob/vore/overmap/proc/link_marker(marker)
	if(child_om_marker)
		om_link(src, child_om_marker, /datum/om/relation/overmap_mob_marker)
	if(!om_child_type)
		log_and_message_admins("An improperly configured OM mob tried to spawn, and was deleted.")
		spent(src)
		return
	// Maps with no overmap can still spawn overmap mobs (e.g. admin
	// summon, unit tests). Skip the marker: there's nothing for it
	// to render against, and a marker that fails to initialise takes
	// us with it through the overmap_mob_marker relation.
	if(!using_map?.use_overmap)
		return
	if(!child_om_marker)
		var/obj/effect/overmap/visitable/simplemob/C = new om_child_type(loc, src)
		rel_set(src, nameof(child_om_marker), C)
		// The marker's Initialize() may have failed and deleted itself.
		if(!QDELETED(C))
			om_link(src, C, /datum/om/relation/overmap_mob_marker)


/// Overmap mob -> the marker that shows it. A marker destroyed on its own (not
/// by its mob, which owns it) takes the mob with it: the mob is invisible and
/// does nothing without the marker.
/datum/om/relation/overmap_mob_marker
	name = "overmap mob marker"
	source_single = TRUE
	target_single = TRUE

/datum/om/relation/overmap_mob_marker/on_unlink(mob/living/simple_mob/vore/overmap/source, obj/effect/overmap/target, datum/om/edge/edge)
	if(QDELETED(target) && !QDELETED(source))
		source.expire(0)

//SHIP

/obj/effect/overmap/visitable/ship/simplemob
	name = "unknown ship"
	icon = 'icons/obj/overmap.dmi'
	icon_state = "ship"
	scannable = TRUE
	known = FALSE
	in_space = FALSE				//Just cuz we don't want people getting here via map edge transitions normally.
	unknown_name = "unknown ship"
	unknown_state = "ship"

	var/mob/living/simple_mob/vore/overmap/parent_mob_type // a type path, never an instance
	var/mob/living/simple_mob/vore/overmap/parent

CAPABILITIES(/obj/effect/overmap/visitable/ship/simplemob)
	param(nameof(parent), pos = 1, apply = PROC_REF(link_parent))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The marker of a mob made with no mob makes its own.
/obj/effect/overmap/visitable/ship/simplemob/proc/link_parent(parent_mob)
	if(!parent_mob_type && !parent)
		log_and_message_admins("An improperly configured OM mob event tried to spawn, and was deleted.")
		spent(src)
		return
	if(!parent)
		var/mob/living/simple_mob/vore/overmap/P = new parent_mob_type(loc, src)
		rel_set(src, nameof(parent), P)
	om_mob_event_setup()

/obj/effect/overmap/visitable/ship/simplemob/proc/om_mob_event_setup()
	scanner_desc = parent.scanner_desc
	observe(parent, /datum/notice/moved, src, then(PROC_REF(on_parent_moved)))
	skybox_pixel_x = rand(-100,100)
	if(known)
		name = initial(parent.name)
		icon = initial(parent.icon)
		icon_state = initial(parent.icon_state)
		color = initial(parent.color)
		desc = initial(parent.desc)

// Ownership is a tree: the mob owns its marker (child_om_marker, OWN);
// the marker's `parent` is only a relation back, cleared when the mob goes.

/obj/effect/overmap/visitable/ship/simplemob/get_scan_data(mob/user)
	if(!known)
		known = TRUE
		name = initial(parent.name)
		icon = initial(parent.icon)
		icon_state = initial(parent.icon_state)
		color = initial(parent.color)
		desc = initial(parent.desc)

	var/dat = {"\[b\]Scan conducted at\[/b\]: [stationtime2text()] [stationdate2text()]\n\[b\]Grid coordinates\[/b\]: [x],[y]\n\n[scanner_desc]"}

	return dat

/obj/effect/overmap/visitable/ship/simplemob/proc/on_parent_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	forceMove(parent.loc)
	set_dir(parent.dir)
