#define BP_MAX_ROOM_SIZE 300
/// Blueprint prompts: the creator is still standing where they started (the prompt's target turf) and able.
#define BLUEPRINT_PROMPT_REQUIRES list(CHECK(/datum/om/check/in_range, 0), /datum/om/check/not_incapacitated)

// WARNING: ESOTERIC BULLSHIT INSIDE OF THIS FILE.
// This is a port of /tg/'s blueprints that also have Virgo modifications as well.
// However it is heavily modified and lacking the 't-ray' scanner functionality that /TG/ has. We have our own t-rays after all.
// This works and uses a bunch of really odd hacks and trickery to get it to all function.
// If you're looking at this a few years from now and going 'What the hell were they thinking' just know that this was the best we had at the time.

// Now that I've scared away half the people looking at this file, here's the relevant info:

// Banning areas: Go to global_lists_vr, jump to the GLOB.BUILDABLE_AREA_TYPES and read the comments left there.

// These areas are defined here so they can be blacklisted in global_lists_vr
/area/tether/elevator

	name = "Tether Elevator"

/area/submap/virgo2
	name = "Submap Area"

/area/submap/casino_event
	name = "\improper Space Casino"

/obj/item/areaeditor
	name = "area modification item"
	icon = 'icons/obj/items.dmi'
	icon_state = "blueprints"
	attack_verb = list("attacked", "bapped", "hit")
	in_use = FALSE
	preserve_item = 1
	var/uses_charges = 0 					// If the area editor has limited uses.
	var/initial_charges = 25
	var/charges = 25 // The amount of uses the area editor has. //
	var/station_master = 1					// If the areaeditor can add charges to others.
	var/wire_schematics = 0					// If the areaeditor can see wires.
	var/can_override = 0						// If you want the areaeditor to override the 'Don't make a new area where one already exists' logic. Only given to CE blueprints.

	var/can_create_areas_in = AREA_SPACE	// Must be standing in space to create
	var/can_create_areas_into = AREA_SPACE	// New areas will only overwrite space area turfs.
	var/can_expand_areas_in = AREA_STATION	// Must be standing in station to expand
	var/can_expand_areas_into = AREA_SPACE	// Can expand station areas only into space.
	var/can_rename_areas_in = AREA_STATION	// Only station areas can be reanamed

	var/const/ROOM_ERR_LOLWAT = 0 			// Don't touch these three consts or BYOND will literally tear out your throat
	var/const/ROOM_ERR_SPACE = -1
	var/const/ROOM_ERR_TOOLARGE = -2
	var/const/ROOM_ERR_FORBIDDEN = -3

	var/list/areaColor_turfs
	var/legend = 0 //If viewing wires or not.

/obj/item/areaeditor/examine(mob/user)
	. =..()
	if(uses_charges && !isnull(charges))
		. += "There appears to be enough space for a total of [charges] more changes!"
		if(!charges)
			. += "There seems to be no more room for any more edits!"

TRACKED(/obj/item/areaeditor, charges)

CAPABILITIES(/obj/item/areaeditor)
	// the old attack_self: read it
	op("read", in_hand(), label("Read"), then(PROC_REF(read_editor)))
	// another editor tops up a limited one's charges (a master refills it; a limited one gives the number asked)
	op("add_charges", item(/obj/item/areaeditor), label("Add material"),
		asks(/datum/prompt/number, fields = list("title" = computed(PROC_REF(donor_title)), "question" = computed(PROC_REF(charges_question)), "default" = computed(PROC_REF(missing_charges)), "min_value" = 0, "max_value" = computed(PROC_REF(donor_charges)), "timeout" = 0), when = PROC_REF(asks_charges)),
		then(PROC_REF(interaction_item)))
	// the old object verbs
	op("room_colors", menu(), label("Show Room Colors"), needs(carried()), then(PROC_REF(verb_room_colors)))
	op("area_colors", menu(), label("Show Area Colors"), needs(carried()), then(PROC_REF(verb_area_colors)))
	op("remove_colors", menu(), label("Remove Area Colors"), needs(carried()), then(PROC_REF(verb_remove_colors)))

/obj/item/areaeditor/proc/verb_room_colors(datum/act/op/A)
	seeRoomColors_effect(A.actor)
	return OP_OK

/obj/item/areaeditor/proc/verb_area_colors(datum/act/op/A)
	seeAreaColors_effect(A.actor)
	return OP_OK

/obj/item/areaeditor/proc/verb_remove_colors(datum/act/op/A)
	seeAreaColors_remove_effect(A.actor)
	return OP_OK

/// The old attack_self: the editor's page (a plain area editor only builds it; the blueprints show theirs).
/obj/item/areaeditor/proc/read_editor(datum/act/op/A)
	areaeditor_text(A.actor)
	return OP_OK

/// The number is asked when this editor is short of charges and the other is a limited one with charges to give.
/obj/item/areaeditor/proc/asks_charges(datum/act/op/A)
	var/obj/item/areaeditor/blueprint = A.held
	return uses_charges && charges < initial_charges && !blueprint.station_master && blueprint.uses_charges && blueprint.charges

/obj/item/areaeditor/proc/donor_title(datum/act/op/A)
	return "[A.held]"

/obj/item/areaeditor/proc/charges_question(datum/act/op/A)
	return "How many charges do you want to add to the [src]?"

/obj/item/areaeditor/proc/missing_charges(datum/act/op/A)
	return initial_charges - charges

/obj/item/areaeditor/proc/donor_charges(datum/act/op/A)
	var/obj/item/areaeditor/blueprint = A.held
	return blueprint.charges

/// Old attackby: another editor adds material to a limited one.
/obj/item/areaeditor/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/areaeditor/blueprint = A.held
	if(!uses_charges || charges >= initial_charges) //Do we have a reason to add charges?
		return OP_DECLINE
	if(blueprint.station_master) //Master can refill.
		set_charges(initial_charges)
		to_chat(user, span_notice("You add some more writing material to the [src] with the [blueprint]!"))
		return OP_PASS
	if(!blueprint.uses_charges || !blueprint.charges) // The item it's being hit by doesn't use charges OR doesn't have any charges.
		to_chat(user, span_warning("You can't add find any suitable material to add from the [blueprint]!"))
		return OP_PASS
	var/datum/prompt/R = A.answer
	if(isnull(R?.value))
		to_chat(user, span_notice("You decide not to add any more material."))
		return OP_PASS
	var/to_add = min(R.value, initial_charges - charges)
	if(blueprint.charges >= to_add)
		to_chat(user, span_notice("You add some more writing material to the [src] with the [blueprint]!"))
		blueprint.set_charges(blueprint.charges - to_add)
		set_charges(charges + to_add)
	else
		charges_not_added(user)
	return OP_PASS

/// Old attack_self: builds the area editing page, which subtypes add to and show. Convert this to TGUI some time.
/obj/item/areaeditor/proc/areaeditor_text(mob/user)
	add_fingerprint(user)
	. = "<BODY><HTML><head><title>[src]</title></head> \
				<h2>[station_name()] [src.name]</h2>"
	switch(get_area_type(get_area(user)))
		if(AREA_SPACE)
			. += "<p>According to the [src.name], you are now in an unclaimed territory.</p>"
		if(AREA_SPECIAL)
			. += "<p>This place is not noted on the [src.name].</p>"
			return //If we're in a special area, no modifying.
	if(!uses_charges || (uses_charges && charges)) //No charges OR it has charges available.
		. += "<p><a href='byond://?src=[REF(src)];create_area=1'>Create or modify an existing area (3x3 space) (1 Charge)</a></p>"
		. += "<p><a href='byond://?src=[REF(src)];create_area_whole=1'>Create new area or merge two areas. (Whole Room.) (5 Charges)</a></p>"
		. += "There is a note on the corner of the [src.name]: Use 3x3 for fine-tuning and including walls into your area!"
	if(uses_charges)
		if(!charges) //We're out!
			. += "Your [src.name] has been completely filled! You would need to get some extra blueprint paper from the CE's blueprints to expand further!"
		else
			. += "Your [src.name] seems like it has enough room for [charges] more edits!"

TOPIC_ACTION(/obj/item/areaeditor, "create_area", PROC_REF(topic_create_area))
TOPIC_ACTION(/obj/item/areaeditor, "create_area_whole", PROC_REF(topic_create_area_whole))

// The editor works only in the active hand of someone able to use it.
/obj/item/areaeditor/topic_allowed(mob/user, list/href_list)
	. = ..()
	if(!.)
		return
	if(user.restrained() || user.stat || user.get_active_hand() != src)
		return FALSE

/obj/item/areaeditor/proc/topic_create_area(mob/user, list/args)
	if(in_use)
		return
	var/area/A = get_area(user)
	if(A.flag_check(BLUE_SHIELDED))
		to_chat(user, span_warning("You cannot edit restricted areas."))
		return
	in_use = TRUE
	create_area(user, src)
	in_use = FALSE
	updateUsrDialog(user)
	return TRUE

/obj/item/areaeditor/proc/topic_create_area_whole(mob/user, list/args)
	if(in_use)
		return
	in_use = TRUE
	create_area_whole(user, src)
	in_use = FALSE
	updateUsrDialog(user)
	return TRUE

//Station Wire Tool.
/obj/item/wire_reader //Not really a blueprint, but it's included here as such.
	name = "wire schematics"
	desc = "A blueprint detailing the various internal wiring of machinery around the station."
	icon = 'icons/obj/items.dmi'
	icon_state = "blueprints"
	attack_verb = list("attacked", "bapped", "hit")
	preserve_item = 1
	var/legend = 1

CAPABILITIES(/obj/item/wire_reader)
	op("read_wires", in_hand(), label("Read"), then(PROC_REF(interaction_read_wires)))

/// Old attack_self. Convert this to TGUI some time.
/obj/item/wire_reader/proc/interaction_read_wires(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = "<BODY><HTML><head><title>[src]</title></head> \
				<h2>[station_name()] [src.name]</h2>"
	if(legend == TRUE)
		. += view_station_wire_devices(user);
	else
		//legend is a wireset
		. += "<a href='byond://?src=[REF(src)];view_legend=1'><< Back</a>"
		. += view_station_wire_set(user, legend)

	// structured TGUI AdminReport; byond:// links forwarded to host.
	dq_admin_report_html(user, "[src]", ., src)

TOPIC_ACTION(/obj/item/wire_reader, "view_wireset", PROC_REF(topic_view_wireset), TOPIC_TEXT("view_wireset", MAX_NAME_LEN))
TOPIC_ACTION(/obj/item/wire_reader, "view_legend", PROC_REF(topic_view_legend))

/obj/item/wire_reader/proc/topic_view_wireset(mob/user, list/args)
	legend = args["view_wireset"]
	attack_self(user)
	return TRUE

/obj/item/wire_reader/proc/topic_view_legend(mob/user, list/args)
	legend = TRUE
	attack_self(user)
	return TRUE

/obj/item/wire_reader/proc/view_station_wire_devices(mob/user)
	var/message = "<br>You examine the wire legend.<br>"
	for(var/wireset in GLOB.wire_color_directory)
		//if(wireset == "Grid Checker")//Uncomment this in if you want the grid checker minigame to not be revealed here.
		//	continue
		message += "<br><a href='byond://?src=[REF(src)];view_wireset=[url_encode(wireset)]'>[GLOB.wire_name_directory[wireset]]</a>"
	message += "</p>"
	return message

/obj/item/wire_reader/proc/view_station_wire_set(mob/user, wireset)
	//for some reason you can't use wireset directly as a derefencer so this is the next best :/
	for(var/device in GLOB.wire_color_directory)
		if("[device]" == wireset) //I know... don't change it...
			var/message = "<p><b>[GLOB.wire_name_directory[device]]:</b>"
			for(var/Col in GLOB.wire_color_directory[device])
				var/wire_name = GLOB.wire_color_directory[device][Col]
				if(!findtext(wire_name, WIRE_DUD_PREFIX)) //don't show duds
					message += "<p><span style='color: [Col]'>[Col]</span>: [wire_name]</p>"
			message += "</p>"
			return message
	return ""

//Station blueprints!!!
/obj/item/areaeditor/blueprints
	name = "station blueprints"
	desc = "Blueprints of the station. There is a \"Classified\" stamp and several coffee stains on it."
	//var/list/image/showing = list()	//For viewing pipes. Unused.
	//var/client/viewing 	//For viewing pipes. Unused.
	can_override = 1 //In case there is a reason for building in a non-blacklisted, non-buildable area.

/obj/item/areaeditor/blueprints/engineers
	name = "writing blueprints"
	desc = "A piece of paper that allows for expansion of the station and creation of new areas. There is a \"For Official Use Only\" stamp on it. NOT to be mistaken with the station blueprints." // purdev (some spelling fixes)
	station_master = 0
	uses_charges = 1
	can_override = 1 // This will allow easier building on the planets, dont think blueprint grief is too big of a problem. -Lotion

/// Old attack_self: the area editor's page, plus the station and wiring pages, shown.
/obj/item/areaeditor/blueprints/read_editor(datum/act/op/A)
	interaction_read_blueprints(A.actor)
	return OP_OK

/obj/item/areaeditor/blueprints/proc/interaction_read_blueprints(mob/user)
	. = areaeditor_text(user)
	var/area/A = get_area(user)
	if(!legend)
		if(get_area_type(get_area(user)) == AREA_STATION)
			. += "<p>According to \the [src], you are now in <b>\"[html_encode(A.name)]\"</b>.</p>"
			. += "<p><a href='byond://?src=[REF(src)];edit_area=1'>Change area name</a></p>" //You can change the name without charges.
		if(wire_schematics)
			. += "<p><a href='byond://?src=[REF(src)];view_legend=1'>View wire colour legend</a></p>"
	else
		if(legend == TRUE)
			. += "<a href='byond://?src=[REF(src)];exit_legend=1'><< Back</a>"
			. += view_wire_devices(user);
		else
			//legend is a wireset
			. += "<a href='byond://?src=[REF(src)];view_legend=1'><< Back</a>"
			. += view_wire_set(user, legend)
	// structured TGUI AdminReport; byond:// links forwarded to host.
	dq_admin_report_html(user, "[src]", ., src)

TOPIC_ACTION(/obj/item/areaeditor/blueprints, "edit_area", PROC_REF(topic_edit_area))
TOPIC_ACTION(/obj/item/areaeditor/blueprints, "exit_legend", PROC_REF(topic_exit_legend))
TOPIC_ACTION(/obj/item/areaeditor/blueprints, "view_legend", PROC_REF(topic_view_legend))
TOPIC_ACTION(/obj/item/areaeditor/blueprints, "view_wireset", PROC_REF(topic_view_wireset), TOPIC_TEXT("view_wireset", MAX_NAME_LEN))

/obj/item/areaeditor/blueprints/proc/topic_edit_area(mob/user, list/args)
	if(get_area_type(get_area(user))!=AREA_STATION)
		return
	if(in_use)
		return
	in_use = TRUE
	edit_area(user)
	in_use = FALSE
	attack_self(user)
	return TRUE

/obj/item/areaeditor/blueprints/proc/topic_exit_legend(mob/user, list/args)
	legend = FALSE
	attack_self(user)
	return TRUE

/obj/item/areaeditor/blueprints/proc/topic_view_legend(mob/user, list/args)
	if(wire_schematics) //No href hacks allow for you, my friend!
		legend = TRUE
	attack_self(user)
	return TRUE

/obj/item/areaeditor/blueprints/proc/topic_view_wireset(mob/user, list/args)
	if(wire_schematics) //No href hacks allow for you, my friend!
		legend = args["view_wireset"]
	attack_self(user)
	return TRUE

//Code for viewing pipes or whatnot. Think t-ray scanner.
//Code for viewing pipes or whatnot. Think t-ray scanner.
//Code for viewing pipes or whatnot. Think t-ray scanner.
/obj/item/areaeditor/blueprints/dropped(mob/user, equipping, slot)
	if(equipping)
		return ..()
	..()
	if(length(areaColor_turfs))
		seeAreaColors_remove_effect(user)
	legend = FALSE

/obj/item/areaeditor/proc/get_area_type(area/A)
	if(!A)
		return 0
	if(A.outdoors)
		return AREA_SPACE

	for(var/type in GLOB.BUILDABLE_AREA_TYPES)
		if(istype(A,type))
			return AREA_SPACE

	for(var/type in GLOB.SPECIALS)
		if(istype(A,type))
			return AREA_SPECIAL
	return AREA_STATION

/obj/item/areaeditor/blueprints/proc/view_wire_devices(mob/user)
	var/message = "<br>You examine the wire legend.<br>"
	for(var/wireset in GLOB.wire_color_directory)
		//if(wireset == "Grid Checker")//Uncomment this in if you want the grid checker minigame to not be revealed here.
		//	continue
		message += "<br><a href='byond://?src=[REF(src)];view_wireset=[url_encode(wireset)]'>[GLOB.wire_name_directory[wireset]]</a>"
	message += "</p>"
	return message

/obj/item/areaeditor/blueprints/proc/view_wire_set(mob/user, wireset)
	//for some reason you can't use wireset directly as a derefencer so this is the next best :/
	for(var/device in GLOB.wire_color_directory)
		if("[device]" == wireset) //I know... don't change it...
			var/message = "<p><b>[GLOB.wire_name_directory[device]]:</b>"
			for(var/Col in GLOB.wire_color_directory[device])
				var/wire_name = GLOB.wire_color_directory[device][Col]
				if(!findtext(wire_name, WIRE_DUD_PREFIX)) //don't show duds
					message += "<p><span style='color: [Col]'>[Col]</span>: [wire_name]</p>"
			message += "</p>"
			return message
	return ""

/obj/item/areaeditor/proc/charges_not_added(mob/user)
	to_chat(user, span_notice("You decide not to add any more material to the [src]"))

/obj/item/areaeditor/proc/edit_area(mob/user)
	var/area/A = get_area(user)
	open_request(src, /datum/prompt/text/blueprint_rename_area, PROC_REF(area_renamed), answerer = user, area_to_rename = A)

/// Re-checked on the answer: the blueprint is still in hand.
/datum/prompt/text/blueprint_rename_area
	title = "Area Creation"
	question = "New area name"
	max_len = MAX_NAME_LEN
	name_text = TRUE
	ask_flags = ASK_HELD | ASK_CAPABLE
	timeout = 0
	var/area/area_to_rename

CAPABILITIES(/datum/prompt/text/blueprint_rename_area)
	ref_one(nameof(area_to_rename), /area)

/datum/prompt/text/blueprint_rename_area/prepare(datum/act/A)
	..()
	var/area/captured_area = area_to_rename
	rel_clear(src, nameof(area_to_rename))
	rel_set(src, nameof(area_to_rename), captured_area)

/datum/prompt/text/blueprint_rename_area/recheck_extra()
	return QDELETED(area_to_rename) ? "gone" : null

/obj/item/areaeditor/proc/area_renamed(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/text/blueprint_rename_area/ask = context.answer
	var/mob/user = ask.answerer
	var/str = ask.value
	var/area/A = ask.area_to_rename
	var/prevname = "[A.name]"
	if(!str || !length(str) || str==prevname) //cancel
		return
	if(length(str) > 50)
		to_chat(user, span_warning("The given name is too long. The area's name is unchanged."))
		return

	rename_area(A, str)

	to_chat(user, span_notice("You rename the '[prevname]' to '[str]'."))
	log_and_message_admins("has changed the area '[prevname]' title to '[str]'.", user)
	A.update_areasize()
	interact(user)
	return TRUE

//Blueprint Subtypes

/obj/item/areaeditor/blueprints/cyborg
	name = "station schematics"
	desc = "A digital copy of the station blueprints stored in your memory."

/proc/set_area_machinery(area/area, title, oldtitle)
	if(!oldtitle) // or replacetext goes to infinite loop
		return
	for(var/obj/machinery/alarm/airpanel in area_contents_of_type(area, /obj/machinery/alarm))
		airpanel.name = replacetext(airpanel.name,oldtitle,title)
	for(var/obj/machinery/power/apc/apcpanel in area_contents_of_type(area, /obj/machinery/power/apc))
		apcpanel.name = replacetext(apcpanel.name,oldtitle,title)
		apcpanel.update_area() //DECIDE IF THIS IS WANTED OR NOT. This can mean that the APC will overwrite the current APC the area being expanded has since areas cant have multiple APCs.
	for(var/obj/machinery/atmospherics/unary/vent_scrubber/scrubber in area_contents_of_type(area, /obj/machinery/atmospherics/unary/vent_scrubber))
		scrubber.name = replacetext(scrubber.name,oldtitle,title)
	for(var/obj/machinery/atmospherics/unary/vent_pump/vent in area_contents_of_type(area, /obj/machinery/atmospherics/unary/vent_pump))
		vent.name = replacetext(vent.name,oldtitle,title)
	area.air_devices_retitled(oldtitle, title)
	for(var/obj/machinery/door/door in area_contents_of_type(area, /obj/machinery/door))
		door.name = replacetext(door.name,oldtitle,title)
	for(var/obj/machinery/firealarm/firepanel in area_contents_of_type(area, /obj/machinery/firealarm))
		firepanel.name = replacetext(firepanel.name,oldtitle,title)
	area.update_areasize()
	//TODO: much much more. Unnamed airlocks, cameras, etc.

/proc/detect_room(turf/origin, list/break_if_found, max_size=INFINITY)
	if(origin.blocks_air)
		return list(origin)

	. = list()
	var/list/checked_turfs = list()
	var/list/found_turfs = list(origin)
	while(length(found_turfs))
		var/turf/sourceT = found_turfs[1]
		found_turfs.Cut(1, 2)
		var/dir_flags = checked_turfs[sourceT]
		for(var/dir in GLOB.alldirs)
			if(length(.) > max_size)
				return
			if(dir_flags & dir) // This means we've checked this dir before, probably from the other turf
				continue
			var/turf/checkT = get_step(sourceT, dir)
			if(!checkT)
				continue

			checked_turfs[sourceT] |= dir
			checked_turfs[checkT] |= turn(dir, 180)
			.[sourceT] |= dir
			.[checkT] |= turn(dir, 180)
			if(break_if_found[checkT.type] || break_if_found[checkT.loc.type])
				return FALSE

			//The below checks to make sure air can pass between the two turfs. If not, it can't be added to the area.
			//This means walls can not be added to an area. The turf must first be added and then the wall.
			//UNCOMMENT THIS IF YOU WANT THE BLUEPRINTS TO NOT ADD WALLS TO AN AREA.
			//I personally think adding walls to an area is a big deal, so this is commented out.

			//BEGIN ESOTERIC BULLSHIT
			//to_chat(world, "Origin: [origin.c_airblock(checkT)] SourceT: [sourceT.c_airblock(checkT)] 0=NB 1=AB 2=ZB, 3=B")
			/*
			if(origin.c_airblock(checkT)) //If everything breaks and it doesn't want to work, turn on the above debug and check this line. C.L. 0 = not blocked.
				continue
			*/
			//END ESOTERIC BULLSHIT

			found_turfs += checkT // Since checkT is connected, add it to the list to be processed
		if(found_turfs.len)
			found_turfs += origin //If this isn't done, it just adds the 8 tiles around the user.
		return found_turfs

/proc/create_area(mob/creator, obj/item/areaeditor/AO)
	if(AO && istype(AO,/obj/item/areaeditor))
		if(AO.uses_charges && AO.charges < 1)
			to_chat(creator, span_warning("You need more paper before you can even think of editing this area!"))
			return

	var/list/turfs = detect_room(get_turf(creator), GLOB.area_or_turf_fail_types, BP_MAX_ROOM_SIZE*2)
	if(!turfs)
		to_chat(creator, span_warning("The new area must have a floor and not a part of a shuttle."))
		return
	if(length(turfs) > BP_MAX_ROOM_SIZE)
		to_chat(creator, span_warning("The room you're in is too big. It is [length(turfs) >= BP_MAX_ROOM_SIZE *2 ? "more than 100" : ((length(turfs) / BP_MAX_ROOM_SIZE)-1)*100]% larger than allowed."))
		return
	var/list/areas = list("New Area" = /area)

	for(var/i in 1 to length(turfs))
		var/area/place = get_area(turfs[i])
		if(GLOB.blacklisted_areas[place.type])
			continue
		if(!place.requires_power || (place.flag_check(BLUE_SHIELDED)))
			continue // No expanding powerless rooms etc
		areas[place.name] = place

	open_request(AO, /datum/prompt/choice/blueprint_expand, TYPE_PROC_REF(/obj/item/areaeditor, create_area_chosen), answerer = creator, subject = get_turf(creator), choices = areas, editor = AO, turfs = turfs)

/obj/item/areaeditor/proc/create_area_chosen(datum/act/request/context)
	var/datum/prompt/choice/blueprint_expand/ask = context.request
	if(!context.answer)
		if(isnull(ask.value) && ask.captures_live())
			to_chat(ask.answerer, span_warning("No choice selected. No adjustments made."))
		return
	create_area_chosen_apply(context)

/obj/item/areaeditor/proc/create_area_chosen_apply(datum/act/request/context)
	var/datum/prompt/choice/blueprint_expand/ask = context.request
	var/area_choice = ask.choices[ask.value]
	if(isarea(area_choice))
		create_area_commit(ask.answerer, src, ask.turfs, area_choice)
		return
	open_request(src, /datum/prompt/text/blueprint_area_name, PROC_REF(create_area_named), answerer = ask.answerer, subject = ask.subject, editor = src, turfs = ask.turfs)

/obj/item/areaeditor/proc/create_area_named(datum/act/request/context)
	if(!context.answer)
		return
	create_area_named_apply(context)

/obj/item/areaeditor/proc/create_area_named_apply(datum/act/request/context)
	var/datum/prompt/text/blueprint_area_name/ask = context.request
	var/mob/creator = ask.answerer
	var/str = ask.value
	if(!length(str)) //cancel
		return
	if(length(str) > 50)
		to_chat(creator, span_warning("Name too long."))
		return
	for(var/area/A in world) //Check to make sure we're not making a duplicate name. Sanity.
		if(A.name == str)
			to_chat(creator, span_warning("An area in the world alreay has this name."))
			return
	var/area/oldA = get_area(get_turf(creator))
	var/area/newA = new /area
	newA.setup(str)
	newA.has_gravity = oldA.has_gravity
	create_area_commit(creator, src, ask.turfs, newA, TRUE)

/// The blueprint's area expansion, once the creator has picked (and maybe named) the area.
/proc/create_area_commit(mob/creator, obj/item/areaeditor/AO, list/turfs, area/newA, annoy_admins = FALSE)
	var/area/oldA = get_area(get_turf(creator))

	for(var/i in 1 to length(turfs)) //Fix lighting. Praise the lord.
		var/turf/thing = turfs[i]
		thing.assign_area(newA)
		thing.change_area(oldA, newA)

	set_area_machinery(newA, newA.name, oldA.name)// Change the name and area defines of all the machinery to the correct area.
	oldA.power_check() //Simply makes the area turn the power off if you nicked an APC from it.
	to_chat(creator, span_notice("You have created a new area, named [newA.name]. It is now weather proof, and constructing an APC will allow it to be powered."))
	if(annoy_admins)
		message_admins("[key_name(creator, creator.client)] just made a new area called [newA.name] ](<A href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=\ref[creator]'>?</A>) at ([creator.x],[creator.y],[creator.z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[creator.x];Y=[creator.y];Z=[creator.z]'>JMP</a>)")
	log_game("[key_name(creator, creator.client)] just made a new area called [newA.name]")
	if(AO && istype(AO,/obj/item/areaeditor))
		if(AO.uses_charges)
			AO.set_charges(AO.charges - (1))

	var/list/zLevels = using_map.station_levels.Copy()
	for(var/datum/planet/PL in SSplanets.planets)
		zLevels -= PL.expected_z_levels
	for(var/obj/machinery/gravity_generator/main/GG in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(GG.z in zLevels)
			GG.update_areas()
	return TRUE

// USED FOR VARIANT ROOM CREATION.
// OLD CODE. DON'T TOUCH OR 100 RABID SQUIRRELS WILL DEVOUR YOU.
// I say old code, but it truly isn't. It's a bastardization of the new create_area code and the old create_area code.
// In essence, it does a few things: Ensure no blacklisted areas are nearby, get the nearby areas (to allow merging), and allow you to make a whole near area.
/obj/item/areaeditor/proc/create_area_whole(mob/creator, override = 0) //Gets the entire enclosed space and makes a new area out of it. Can overwrite old areas.
	if(uses_charges && charges < 5)
		to_chat(creator, span_warning("You need more paper before you can even think of editing this area!"))
		return

	var/res = detect_room_ex(get_turf(creator), can_create_areas_into, GLOB.area_or_turf_fail_types)
	if(!res)
		to_chat(creator, span_warning("There is an area forbidden from being edited here! Use the fine-tune area creator! (3x3)"))
		return

	if(!istype(res,/list))
		switch(res)
			if(ROOM_ERR_SPACE)
				to_chat(creator, span_warning("The new area must be completely airtight!"))
				return
			if(ROOM_ERR_TOOLARGE)
				to_chat(creator, span_warning("The new area too large!"))
				return
			if(ROOM_ERR_FORBIDDEN)
				to_chat(creator, span_warning("There is an area forbidden from being edited here!"))
				return
			else
				to_chat(creator, span_warning("Error! Please notify administration!"))
				return
	var/list/turf/turfs = res

	var/list/areas = list("New Area" = /area)	//The list of areas surrounding the user.
	var/can_make_new_area = 1					//If they can make a new area here or not.

	var/list/nearby_turfs_to_check = detect_room(get_turf(creator), GLOB.area_or_turf_fail_types, BP_MAX_ROOM_SIZE*2) //Get the nearby areas.

	if(!nearby_turfs_to_check)
		to_chat(creator, span_warning("The new area must have a floor and not a part of a shuttle."))
		return
	if(length(turfs) > BP_MAX_ROOM_SIZE)
		to_chat(creator, span_warning("The room you're in is too big. It is [length(turfs) >= BP_MAX_ROOM_SIZE *2 ? "more than 100" : ((length(turfs) / BP_MAX_ROOM_SIZE)-1)*100]% larger than allowed."))
		return

	for(var/i in 1 to length(nearby_turfs_to_check))
		var/area/place = get_area(nearby_turfs_to_check[i])
		if(GLOB.blacklisted_areas[place.type])
			if(!creator.lastarea != place) //Stops them from merging a blacklisted area to make it larger. Allows them to merge a blacklisted area into an allowed area. (Expansion!)
				continue
		if(!GLOB.BUILDABLE_AREA_TYPES[place.type]) //TODOTODOTODO
			can_make_new_area = 0
		if(!place.requires_power || (place.flag_check(BLUE_SHIELDED)))
			continue // No expanding powerless rooms etc
		areas[place.name] = place

	//They can select an area they want to turn their current area into.
	open_request(src, /datum/prompt/choice/blueprint_whole_area, PROC_REF(whole_area_chosen), answerer = creator, subject = get_turf(creator), choices = areas, turfs = turfs, can_make_new_area = can_make_new_area)

/obj/item/areaeditor/proc/whole_area_chosen(datum/act/request/context)
	var/datum/prompt/choice/blueprint_whole_area/ask = context.request
	if(!context.answer)
		if(isnull(ask.value) && ask.captures_live())
			to_chat(ask.answerer, span_warning("No changes made."))
		return
	whole_area_chosen_apply(context)

/obj/item/areaeditor/proc/whole_area_chosen_apply(datum/act/request/context)
	var/datum/prompt/choice/blueprint_whole_area/ask = context.request
	var/mob/creator = ask.answerer
	var/area_choice = ask.choices[ask.value]
	var/area/oldA = get_area(get_turf(creator))
	if(isarea(area_choice))
		open_request(src, /datum/prompt/choice/blueprint_whole_confirm, PROC_REF(whole_area_confirmed), answerer = creator, subject = ask.subject, question = "Are you sure you want to change [oldA.name] into [area_choice]?", turfs = ask.turfs, chosen_area = area_choice)
		return
	if(!ask.can_make_new_area && !can_override)
		to_chat(creator, span_warning("Making a new area here would be meaningless. Renaming it would be a better option."))
		return
	open_request(src, /datum/prompt/text/blueprint_area_name, PROC_REF(whole_area_named), answerer = creator, subject = ask.subject, turfs = ask.turfs)

/obj/item/areaeditor/proc/whole_area_named(datum/act/request/context)
	if(!context.answer)
		return
	whole_area_named_apply(context)

/obj/item/areaeditor/proc/whole_area_named_apply(datum/act/request/context)
	var/datum/prompt/text/blueprint_area_name/ask = context.request
	var/mob/creator = ask.answerer
	var/str = ask.value
	if(!length(str)) //cancel
		return
	if(length(str) > 50)
		to_chat(creator, span_warning("Name too long."))
		return
	for(var/area/A in world) //Check to make sure we're not making a duplicate name. Sanity.
		if(A.name == str)
			to_chat(creator, span_warning("An area in the world alreay has this name."))
			return
	var/area/oldA = get_area(get_turf(creator))
	open_request(src, /datum/prompt/choice/blueprint_whole_confirm, PROC_REF(whole_area_confirmed), answerer = creator, subject = ask.subject, question = "Are you sure you want to change [oldA.name] into a new area named [str]?", turfs = ask.turfs, new_name = str)

/obj/item/areaeditor/proc/whole_area_confirmed(datum/act/request/context)
	var/datum/prompt/choice/blueprint_whole_confirm/ask = context.request
	if(!context.answer || ask.value != "Yes")
		if((isnull(ask.value) || ask.value == "No") && ask.captures_live())
			to_chat(ask.answerer, span_warning("No changes made."))
		return
	whole_area_confirmed_apply(context)

/obj/item/areaeditor/proc/whole_area_confirmed_apply(datum/act/request/context)
	var/datum/prompt/choice/blueprint_whole_confirm/ask = context.request
	var/mob/creator = ask.answerer
	var/list/turf/turfs = ask.turfs
	var/area/oldA = get_area(get_turf(creator))
	var/str = ask.new_name
	var/area/newA = ask.chosen_area
	if(str)
		newA = new /area
		newA.setup(str)
		newA.has_gravity = oldA.has_gravity

	if(str) //New area, new name.
		newA.setup(str)
	else
		newA.setup(newA.name)

	for(var/i in 1 to length(turfs)) //Fix lighting. Praise the lord.
		var/turf/thing = turfs[i]
		thing.assign_area(newA)
		thing.change_area(oldA, newA)

	move_turfs_to_area(turfs, newA)
	newA.has_gravity = oldA.has_gravity
	set_area_machinery(newA, newA.name, oldA.name)
	oldA.power_check() //Simply makes the area turn the power off if you nicked an APC from it.
	to_chat(creator, span_notice("You have created a new area, named [newA.name]. It is now weather proof, and constructing an APC will allow it to be powered."))
	message_admins("[key_name(creator, creator.client)] just made a new area called [newA.name] ](<A href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=\ref[creator]'>?</A>) at ([creator.x],[creator.y],[creator.z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[creator.x];Y=[creator.y];Z=[creator.z]'>JMP</a>)")
	log_game("[key_name(creator, creator.client)] just made a new area called [newA.name]")
	set_charges(charges - (5))

	after(src, 0.5 SECONDS, "interact")
	return

/proc/move_turfs_to_area(list/turf/turfs, area/A)
	for(var/T in turfs)
		ChangeArea(T, A)

/obj/item/areaeditor/proc/detect_room_ex(turf/first, allowedAreas = AREA_SPACE, list/forbiddenAreas = list(), visual)
	if(!istype(first))
		return ROOM_ERR_LOLWAT
	if(!visual && forbiddenAreas[first.loc.type] || forbiddenAreas[first.type]) //Is the area of the starting turf a banned area? Is the turf a banned area?
		return ROOM_ERR_FORBIDDEN
	var/list/turf/found = list()
	var/list/turf/pending = list(first)
	while(pending.len)
		if (found.len+pending.len > BP_MAX_ROOM_SIZE)
			return ROOM_ERR_TOOLARGE
		var/turf/T = pending[1] //why byond havent list::pop()?
		pending -= T
		for (var/dir in GLOB.cardinal)
			var/turf/NT = get_step(T,dir)
			if (!isturf(NT) || (NT in found) || (NT in pending))
				continue
			if(!visual && forbiddenAreas[NT.loc.type])
				return ROOM_ERR_FORBIDDEN
			// We ask ZAS to determine if its airtight.  Thats what matters anyway right?
			if(SSair.air_blocked(T, NT))
				// Okay thats the edge of the room
				if(get_area_type(NT.loc) == AREA_SPACE && SSair.air_blocked(NT, NT))
					found += NT // So we include walls/doors not already in any area
				continue
			if (istype(NT, /turf/space))
				return ROOM_ERR_SPACE //omg hull breach we all going to die here
			if (istype(NT, /turf/simulated/shuttle))
				return ROOM_ERR_SPACE // Unsure why this, but was in old code. Trusting for now.
			if (NT.loc != first.loc && !(get_area_type(NT.loc) & allowedAreas))
				// Edge of a protected area.  Lets stop here...
				continue
			if (!istype(NT, /turf/simulated))
				// Great, unsimulated... eh, just stop searching here
				continue
			// Okay, NT looks promising, lets continue the search there!
			pending += NT
		found += T
	// end while
	return found

//Nice verbs for the engineer to see where areas start/end.

/obj/item/areaeditor/proc/seeRoomColors_effect(mob/user)

	// If standing somewhere we can expand from, use expand perms, otherwise create
	var/canOverwrite = (get_area_type(get_area(user)) & can_expand_areas_in) ? can_expand_areas_into : can_create_areas_into
	var/res = detect_room_ex(get_turf(user), canOverwrite, visual = 1)
	if(!istype(res, /list))
		switch(res)
			if(ROOM_ERR_SPACE)
				to_chat(user, span_warning("The new area must be completely airtight!"))
				return
			if(ROOM_ERR_TOOLARGE)
				to_chat(user, span_warning("The new area too large!"))
				return
			else
				to_chat(user, span_danger("Error! Please notify administration!"))
				return
	// Okay we got a room, lets color it
	seeAreaColors_remove_effect(user)
	var/icon/green = new('icons/misc/debug_group.dmi', "green")
	for(var/turf/T in res)
		user << image(green, T, "blueprints", TURF_LAYER)
		LAZYADD(areaColor_turfs, T)
	to_chat(user, span_notice("The space covered by the new area is highlighted in green."))

/obj/item/areaeditor/proc/seeAreaColors_effect(mob/user)

	// Remove any existing
	seeAreaColors_remove_effect(user)

	to_chat(user, span_notice("\The [src] shows nearby areas in different colors."))
	var/i = 0
	for(var/area/A in range(user))
		if(get_area_type(A) == AREA_SPACE)
			continue // Don't overlay all of space!
		var/icon/areaColor = new('icons/misc/debug_rebuild.dmi', "[++i]")
		to_chat(user, "- [A] as [i]")
		for(var/turf/T in contents_of(A))
			user << image(areaColor, T, "blueprints", TURF_LAYER)
			LAZYADD(areaColor_turfs, T)

/obj/item/areaeditor/proc/seeAreaColors_remove_effect(mob/user)

	LAZYCLEARLIST(areaColor_turfs)
	if(user?.client?.images.len)
		for(var/image/i in user.client.images)
			if(i.icon_state == "blueprints")
				user.client.images.Remove(i)

//GLOBAL VERB FOR PAPER TO ENABLE ANYONE TO MAKE AN AREA IN BUILDABLE AREAS.
//THIS IS 70 TILES. ANYTHING LARGER SHOULD USE ACTUAL BLUEPRINTS.

/obj/item/paper
	var/created_area = 0
	var/area_cooldown = 0

TRACKED(/obj/item/paper, created_area)

MSG_DEF_SELF(paper/area_made, "This paper has already been used to create an area.")

/// The paper's "Create Area" verb (declared with the paper, paper.dm): one area per paper, and not too often.
/obj/item/paper/proc/create_area_effect(datum/act/op/A)
	var/mob/user = A.actor
	if(!COOLDOWN_FINISHED(src, area_cooldown))
		to_chat(user, span_warning("You recently used this paper to try to create an area, wait one minute before using it again."))
		return OP_OK
	COOLDOWN_START(src, area_cooldown, 60 SECONDS) //Anti spam.

	create_new_area(user)
	add_fingerprint(user)
	return OP_OK

/proc/get_new_area_type(area/A) //1 = can build in. 0 = can not build in.
	if (!A)
		return 0
	if(A.outdoors) //ALWAYS able to build outdoors. This means if it's missed in GLOB.BUILDABLE_AREA_TYPES it's fine.
		return 1

	for (var/type in GLOB.BUILDABLE_AREA_TYPES) //This works well.
		if ( istype(A,type) )
			return 1

	for (var/type in GLOB.SPECIALS)
		if ( istype(A,type) )
			return 0
	return 0 //If it's not a buildable area, don't let them build in it.

/proc/detect_new_area(turf/first, user) //Heavily simplified version for creating an area yourself.
	if(!istype(first)) //Not on a turf.
		to_chat(user, span_warning("You can not create a room here."))
		return
	if(get_new_area_type(first.loc) == 1) //Are they in an area they can build? I tried to do this BUILDABLE_AREA_TYPES[first.loc.type] but it refused.
		var/list/turf/found = list()
		var/list/turf/pending = list(first)
		while(pending.len)
			if (found.len+pending.len > 70)
				return 1 //TOOLARGE
			var/turf/T = pending[1]
			pending -= T
			for (var/dir in GLOB.cardinal)
				var/turf/NT = get_step(T,dir)
				if (!isturf(NT) || (NT in found) || (NT in pending))
					continue
				if(!get_new_area_type(NT.loc) == 1) //The contains somewhere that is NOT a buildable area.
					return 3 //NOT A BUILDABLE AREA

				if(SSair.air_blocked(T, NT)) //Is the room airtight?
					// Okay thats the edge of the room
					if(get_new_area_type(NT.loc) == 1 && SSair.air_blocked(NT, NT))
						found += NT // So we include walls/doors not already in any area
					continue
				if (istype(NT, /turf/space))
					return 2 //SPACE
				if (istype(NT, /turf/simulated/shuttle))
					return 2 //SPACE
				if (NT.loc != first.loc && !(get_new_area_type(NT.loc) & 1))
					// Edge of a protected area.  Lets stop here...
					continue
				if (!istype(NT, /turf/simulated))
					// Great, unsimulated... eh, just stop searching here
					continue
				// Okay, NT looks promising, lets continue the search there!
				pending += NT
			found += T
		// end while
		return found
	else
		return 3

/proc/create_new_area(mob/creator) //Heavily simplified version of the blueprint version.
	var/res = detect_new_area(get_turf(creator), creator)
	if(!res)
		to_chat(creator, span_warning("Something went wrong."))
		return

	if(!istype(res,/list))
		switch(res)
			if(1)
				to_chat(creator, span_warning("The new area too large! You can only have an area that is up to 70 tiles."))
				return
			if(2)
				to_chat(creator, span_warning("The new area must be completely airtight and not be part of a shuttle!"))
				return
			if(3)
				to_chat(creator, span_warning("There is an area not permitted to be built in somewhere in the room!"))
				return
			else
				to_chat(creator, span_warning("Error! Please notify administration!"))
				return
	var/list/turf/turfs = res

	var/list/nearby_turfs_to_check = detect_room(get_turf(creator), GLOB.area_or_turf_fail_types, 70) //Get the nearby areas.

	if(!nearby_turfs_to_check)
		to_chat(creator, span_warning("The new area must have a floor and not a part of a shuttle."))
		return
	if(length(turfs) > 70) //Sanity
		to_chat(creator, span_warning("The room you're in is too big. It can only be 70 tiles in size, excluding walls."))
		return

	open_request(creator, /datum/prompt/text/blueprint_new_area, TYPE_PROC_REF(/mob, create_new_area_named), answerer = creator, subject = get_turf(creator), turfs = turfs)

/datum/prompt/text/blueprint_new_area
	title = "Area Name"
	question = "What would you like to name the area?"
	max_len = MAX_NAME_LEN
	name_text = TRUE
	encode = FALSE
	timeout = 0
	var/list/turfs

/datum/prompt/text/blueprint_new_area/proc/captures_live()
	return !QDELETED(answerer) && !QDELETED(subject)

/datum/prompt/text/blueprint_new_area/recheck_extra()
	. = ..()
	if(.)
		return
	if(!captures_live())
		return "gone"
	var/turf/at = get_turf(answerer)
	var/turf/tt = get_turf(subject)
	if(!at || !tt || at.z != tt.z || get_dist(at, tt) > 0)
		return "too far away"
	if(answerer.incapacitated())
		return "not able to"

/mob/proc/create_new_area_named(datum/act/request/context)
	var/datum/prompt/text/blueprint_new_area/ask = context.request
	if(!context.answer)
		if(isnull(ask.value) && ask.captures_live())
			to_chat(ask.answerer, span_warning("No new area made. Cancelling."))
		return
	create_new_area_named_apply(context)

/mob/proc/create_new_area_named_apply(datum/act/request/context)
	var/datum/prompt/text/blueprint_new_area/ask = context.request
	var/mob/creator = src
	var/str = sanitizeSafe(ask.value, MAX_NAME_LEN)
	if(!str || !length(str)) //sanity
		to_chat(creator, span_warning("No new area made. Cancelling."))
		return
	if(length(str) > MAX_NAME_LEN)
		to_chat(creator, span_warning("Name too long."))
		return
	for(var/area/A in world) //Check to make sure we're not making a duplicate name. Sanity.
		if(A.name == str)
			to_chat(creator, span_warning("An area in the world alreay has this name."))
			return
	var/list/turf/turfs = ask.turfs
	var/area/oldA = get_area(get_turf(creator))
	var/area/newA = new /area
	newA.setup(str)
	newA.has_gravity = oldA.has_gravity
	newA.setup(str)

	for(var/i in 1 to length(turfs)) //Fix lighting. Praise the lord.
		var/turf/thing = turfs[i]
		thing.assign_area(newA)
		thing.change_area(oldA, newA)

	move_turfs_to_area(turfs, newA)
	newA.has_gravity = oldA.has_gravity
	set_area_machinery(newA, newA.name, oldA.name)
	oldA.power_check() //Simply makes the area turn the power off if you nicked an APC from it.
	to_chat(creator, span_notice("You have created a new area, named [newA.name]. It is now weather proof, and constructing an APC will allow it to be powered."))
	message_admins("[key_name(creator, creator.client)] just made a new area called [newA.name] ](<A href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=\ref[creator]'>?</A>) at ([creator.x],[creator.y],[creator.z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[creator.x];Y=[creator.y];Z=[creator.z]'>JMP</a>)")
	log_game("[key_name(creator, creator.client)] just made a new area called [newA.name]")

	var/list/zLevels = using_map.station_levels.Copy()
	for(var/datum/planet/PL in SSplanets.planets)
		zLevels -= PL.expected_z_levels
	for(var/obj/machinery/gravity_generator/main/GG in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(GG.z in zLevels)
			GG.update_areas()
	return

#undef BP_MAX_ROOM_SIZE

/datum/prompt/choice/blueprint_expand
	title = "Area Expansion"
	question = "Choose an area to expand or make a new area"
	timeout = 0
	var/list/turfs
	var/tmp/obj/item/areaeditor/editor
	var/editor_expected = FALSE

CAPABILITIES(/datum/prompt/choice/blueprint_expand)
	ref_one(nameof(editor), /obj/item/areaeditor)

/datum/prompt/choice/blueprint_expand/prepare(datum/act/A)
	. = ..()
	var/obj/item/areaeditor/captured_editor = editor
	editor_expected = !isnull(captured_editor)
	rel_clear(src, nameof(editor))
	rel_set(src, nameof(editor), captured_editor)

/datum/prompt/choice/blueprint_expand/proc/captures_live()
	if(QDELETED(answerer) || QDELETED(subject))
		return FALSE
	if(editor_expected && QDELETED(editor))
		return FALSE
	return TRUE

/datum/prompt/choice/blueprint_expand/recheck_extra()
	. = ..()
	if(.)
		return
	if(!captures_live())
		return "gone"
	var/turf/at = get_turf(answerer)
	var/turf/tt = get_turf(subject)
	if(!at || !tt || at.z != tt.z || get_dist(at, tt) > 0)
		return "too far away"
	if(answerer.incapacitated())
		return "not able to"

/datum/prompt/text/blueprint_area_name
	title = "Blueprint Editing"
	question = "New area name"
	timeout = 0
	var/list/turfs
	max_len = MAX_NAME_LEN
	name_text = TRUE
	var/tmp/obj/item/areaeditor/editor
	var/editor_expected = FALSE

CAPABILITIES(/datum/prompt/text/blueprint_area_name)
	ref_one(nameof(editor), /obj/item/areaeditor)

/datum/prompt/text/blueprint_area_name/prepare(datum/act/A)
	. = ..()
	var/obj/item/areaeditor/captured_editor = editor
	editor_expected = !isnull(captured_editor)
	rel_clear(src, nameof(editor))
	rel_set(src, nameof(editor), captured_editor)

/datum/prompt/text/blueprint_area_name/proc/captures_live()
	if(QDELETED(answerer) || QDELETED(subject))
		return FALSE
	if(editor_expected && QDELETED(editor))
		return FALSE
	return TRUE

/datum/prompt/text/blueprint_area_name/recheck_extra()
	. = ..()
	if(.)
		return
	if(!captures_live())
		return "gone"
	var/turf/at = get_turf(answerer)
	var/turf/tt = get_turf(subject)
	if(!at || !tt || at.z != tt.z || get_dist(at, tt) > 0)
		return "too far away"
	if(answerer.incapacitated())
		return "not able to"

/datum/prompt/choice/blueprint_whole_area
	title = "Area Expansion"
	question = "What area do you want to turn the area YOU ARE CURRENTLY STANDING IN to? Or do you want to make a new area?"
	timeout = 0
	var/list/turfs
	var/can_make_new_area

/datum/prompt/choice/blueprint_whole_area/proc/captures_live()
	if(QDELETED(answerer) || QDELETED(subject))
		return FALSE
	return TRUE

/datum/prompt/choice/blueprint_whole_area/recheck_extra()
	. = ..()
	if(.)
		return
	if(!captures_live())
		return "gone"
	var/turf/at = get_turf(answerer)
	var/turf/tt = get_turf(subject)
	if(!at || !tt || at.z != tt.z || get_dist(at, tt) > 0)
		return "too far away"
	if(answerer.incapacitated())
		return "not able to"

/datum/prompt/choice/blueprint_whole_confirm
	title = "READ CAREFULLY"
	question = ""
	timeout = 0
	var/list/turfs
	choices = list("No", "Yes")
	buttons = TRUE
	var/new_name
	var/tmp/area/chosen_area
	var/chosen_area_expected = FALSE

CAPABILITIES(/datum/prompt/choice/blueprint_whole_confirm)
	ref_one(nameof(chosen_area), /area)

/datum/prompt/choice/blueprint_whole_confirm/prepare(datum/act/A)
	. = ..()
	var/area/captured_chosen_area = chosen_area
	chosen_area_expected = !isnull(captured_chosen_area)
	rel_clear(src, nameof(chosen_area))
	rel_set(src, nameof(chosen_area), captured_chosen_area)

/datum/prompt/choice/blueprint_whole_confirm/proc/captures_live()
	if(QDELETED(answerer) || QDELETED(subject))
		return FALSE
	if(chosen_area_expected && QDELETED(chosen_area))
		return FALSE
	return TRUE

/datum/prompt/choice/blueprint_whole_confirm/recheck_extra()
	. = ..()
	if(.)
		return
	if(!captures_live())
		return "gone"
	var/turf/at = get_turf(answerer)
	var/turf/tt = get_turf(subject)
	if(!at || !tt || at.z != tt.z || get_dist(at, tt) > 0)
		return "too far away"
	if(answerer.incapacitated())
		return "not able to"

/datum/prompt/choice/blueprint_expand/begin()
	if(!captures_live())
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/text/blueprint_area_name/begin()
	if(!captures_live())
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/blueprint_whole_area/begin()
	if(!captures_live())
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/blueprint_whole_confirm/begin()
	if(!captures_live())
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()
