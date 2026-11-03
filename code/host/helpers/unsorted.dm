//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/*
 * A large number of misc global procs.
 */

//Checks if all high bits in req_mask are set in bitfield
#define BIT_TEST_ALL(bitfield, req_mask) ((~(bitfield) & (req_mask)) == 0)

//Returns the middle-most value
//Returns whether or not A is the middle most value
/proc/InRange(A, lower, upper)
	if(A < lower) return 0
	if(A > upper) return 0
	return 1

/proc/Get_Angle(atom/movable/start,atom/movable/end)//For beams.
	if(!start || !end) return 0
	var/dy
	var/dx
	dy=(32*end.y+end.pixel_y)-(32*start.y+start.pixel_y)
	dx=(32*end.x+end.pixel_x)-(32*start.x+start.pixel_x)
	if(!dy)
		return (dx>=0)?90:270
	.=arctan(dx/dy)
	if(dy<0)
		.+=180
	else if(dx<0)
		.+=360

/proc/getline(atom/M,atom/N)//Ultra-Fast Bresenham Line-Drawing Algorithm
	var/px=M.x		//starting x
	var/py=M.y
	var/line[] = list(locate(px,py,M.z))
	var/dx=N.x-px	//x distance
	var/dy=N.y-py
	var/dxabs=abs(dx)//Absolute value of x distance
	var/dyabs=abs(dy)
	var/sdx=SIGN(dx)	//Sign of x distance (+ or -)
	var/sdy=SIGN(dy)
	var/x=dxabs>>1	//Counters for steps taken, setting to distance/2
	var/y=dyabs>>1	//Bit-shifting makes me l33t.  It also makes getline() unnessecarrily fast.
	var/j			//Generic integer for counting
	if(dxabs>=dyabs)	//x distance is greater than y
		for(j=0;j<dxabs;j++)//It'll take dxabs steps to get there
			y+=dyabs
			if(y>=dxabs)	//Every dyabs steps, step once in y direction
				y-=dxabs
				py+=sdy
			px+=sdx		//Step on in x direction
			line+=locate(px,py,M.z)//Add the turf to the list
	else
		for(j=0;j<dyabs;j++)
			x+=dxabs
			if(x>=dyabs)
				x-=dyabs
				px+=sdx
			py+=sdy
			line+=locate(px,py,M.z)
	return line

#define LOCATE_COORDS(X, Y, Z) locate(between(1, X, world.maxx), between(1, Y, world.maxy), Z)
/proc/getcircle(turf/center, radius) //Uses a fast Bresenham rasterization algorithm to return the turfs in a thin circle.
	if(!radius) return list(center)

	var/x = 0
	var/y = radius
	var/p = 3 - 2 * radius

	. = list()
	while(y >= x) // only formulate 1/8 of circle

		. += LOCATE_COORDS(center.x - x, center.y - y, center.z) //upper left left
		. += LOCATE_COORDS(center.x - y, center.y - x, center.z) //upper upper left
		. += LOCATE_COORDS(center.x + y, center.y - x, center.z) //upper upper right
		. += LOCATE_COORDS(center.x + x, center.y - y, center.z) //upper right right
		. += LOCATE_COORDS(center.x - x, center.y + y, center.z) //lower left left
		. += LOCATE_COORDS(center.x - y, center.y + x, center.z) //lower lower left
		. += LOCATE_COORDS(center.x + y, center.y + x, center.z) //lower lower right
		. += LOCATE_COORDS(center.x + x, center.y + y, center.z) //lower right right

		if(p < 0)
			p += 4*x++ + 6;
		else
			p += 4*(x++ - y--) + 10;

#undef LOCATE_COORDS

//Returns whether or not a player is a guest using their ckey as an input
/proc/IsGuestKey(key)
	READS_FROM() // a key's text only
	if (findtext(key, "Guest-", 1, 7) != 1) //was findtextEx
		return 0

	var/i = 7, ch, len = length(key)

	if(copytext(key, 7, 8) == "W") //webclient
		i++

	for (, i <= len, ++i)
		ch = text2ascii(key, i)
		if (ch < 48 || ch > 57)
			return 0
	return 1

//Ensure the frequency is within bounds of what it should be sending/recieving at
/proc/sanitize_frequency(f, low = PUBLIC_LOW_FREQ, high = PUBLIC_HIGH_FREQ)
	f = round(f)
	f = max(low, f)
	f = min(high, f)
	if ((f % 2) == 0) //Ensure the last digit is an odd number
		f += 1
	return f

//Turns 1479 into 147.9
/proc/format_frequency(f)
	return "[round(f / 10)].[f % 10]"

//Opposite of format, returns as a number
/proc/unformat_frequency(frequency)
	frequency = text2num(frequency)
	return frequency * 10

/// A mob picking its own name for a role (rename_self()).
/datum/prompt/text/rename_self
	title = "Name change"
	max_len = MAX_NAME_LEN
	name_text = TRUE
	timeout = 0
	var/role
	var/allow_numbers
	var/attempt
	var/started_at = 0

/datum/prompt/text/rename_self/prepare(datum/act/A)
	. = ..()
	question = "You are \a [role]. Would you like to change your name to something else?"

//Picks a string of symbols to display as the law number for hacked or ion laws
/proc/ionnum()
	return "[pick("1","2","3","4","5","6","7","8","9","0")][pick("!","@","#","$","%","^","&","*")][pick("!","@","#","$","%","^","&","*")][pick("!","@","#","$","%","^","&","*")]"

/// The question a borg is asked to choose which active AI to link to (open_request(borg, /datum/prompt/choice/ai_selection, ..., answerer = borg, choices = active_ais())).
/datum/prompt/choice/ai_selection
	question = "AI signals detected:"
	title = "AI selection"

// Format a power value in W, kW, MW, or GW.
/proc/DisplayPower(powerused)
	if(powerused < 1000) //Less than a kW
		return "[powerused] W"
	else if(powerused < 1000000) //Less than a MW
		return "[round((powerused * 0.001),0.01)] kW"
	else if(powerused < 1000000000) //Less than a GW
		return "[round((powerused * 0.000001),0.001)] MW"
	return "[round((powerused * 0.000000001),0.0001)] GW"

//Forces a variable to be posative
// returns the turf located at the map edge in the specified direction relative to A
// used for mass driver
/proc/get_edge_target_turf(atom/A, direction)

	var/turf/target = locate(A.x, A.y, A.z)
	if(!A || !target)
		return 0
		//since NORTHEAST == NORTH & EAST, etc, doing it this way allows for diagonal mass drivers in the future
		//and isn't really any more complicated

		// Note diagonal directions won't usually be accurate
	if(direction & NORTH)
		target = locate(target.x, world.maxy, target.z)
	if(direction & SOUTH)
		target = locate(target.x, 1, target.z)
	if(direction & EAST)
		target = locate(world.maxx, target.y, target.z)
	if(direction & WEST)
		target = locate(1, target.y, target.z)

	return target

// returns turf relative to A in given direction at set range
// result is bounded to map size
// note range is non-pythagorean
// used for disposal system
/proc/get_ranged_target_turf(atom/A, direction, range)

	var/x = A.x
	var/y = A.y
	if(direction & NORTH)
		y = min(world.maxy, y + range)
	if(direction & SOUTH)
		y = max(1, y - range)
	if(direction & EAST)
		x = min(world.maxx, x + range)
	if(direction & WEST)
		x = max(1, x - range)

	return locate(x,y,A.z)

// returns turf relative to A offset in dx and dy tiles
// bound to map limits
/proc/get_offset_target_turf(atom/A, dx, dy)
	var/x = min(world.maxx, max(1, A.x + dx))
	var/y = min(world.maxy, max(1, A.y + dy))
	return locate(x,y,A.z)

//returns random gauss number
/proc/GaussRand(sigma)
	var/x,y,rsq
	do
		x=2*rand()-1
		y=2*rand()-1
		rsq=x*x+y*y
	while(rsq>1 || !rsq)
	return sigma*y*sqrt(-2*log(rsq)/rsq)

//returns random gauss number, rounded to 'roundto'
/proc/GaussRandRound(sigma,roundto)
	return round(GaussRand(sigma),roundto)

//Will return the contents of an atom recursivly to a depth of 'searchDepth'
/atom/proc/GetAllContents(searchDepth = 5)
	var/list/toReturn = list()
	if(latent_contents_enabled())
		latent_materialize_all() // a search needs real things (C5)

	for(var/atom/part in contents)
		toReturn += part
		if((contents_count(part) || part?.latent_contents_enabled()) && searchDepth)
			toReturn += part.GetAllContents(searchDepth - 1)

	return toReturn

//Step-towards method of determining whether one atom can see another. Similar to viewers()
/proc/can_see(atom/source, atom/target, length=5) // I couldn't be arsed to do actual raycasting :I This is horribly inaccurate.
	var/turf/current = get_turf(source)
	var/turf/target_turf = get_turf(target)
	var/steps = 0

	if(!current || !target_turf)
		return 0

	while(current != target_turf)
		if(steps > length) return 0
		if(current.opacity) return 0
		for(var/atom/A in turf_contents_of_type(current, /atom))
			if(A.opacity) return 0
		current = get_step_towards(current, target_turf)
		steps++

	return 1

/proc/is_blocked_turf(turf/T)
	var/cant_pass = 0
	if(T.density) cant_pass = 1
	for(var/atom/A in turf_contents_of_type(T, /atom))
		if(A.density)//&&A.anchored
			cant_pass = 1
	return cant_pass

/* //If you uncomment and use this I will assimilate you. -C.L.
//Takes: Anything that could possibly have variables and a varname to check.
//Returns: 1 if found, 0 if not.
*/

//Returns: all the areas in the world
/proc/return_areas()
	var/list/area/areas = list()
	for(var/area/A in world)
		areas[A.name] = A
	return areas

//Returns: all the areas in the world, sorted.
/proc/return_sorted_areas()
	return sortTim(return_areas(), GLOBAL_PROC_REF(cmp_text_asc))

//Takes: Area type as text string or as typepath OR an instance of the area.
//Returns: A list of all turfs in areas of that type of that type in the world.
/proc/get_area_turfs(areatype)
	if(!areatype) return null
	if(istext(areatype)) areatype = text2path(areatype)
	if(isarea(areatype))
		var/area/areatemp = areatype
		areatype = areatemp.type

	var/list/turfs = new/list()
	for(var/area/N in world)
		if(istype(N, areatype))
			for(var/turf/T in N) turfs += T
	return turfs

//Takes: An instance of the area.
//Returns: A list of all turfs in that area.
//Side note: I don't know why this was never a thing. Did everyone just ignore the Blueprint item?! - C.L.
/proc/get_current_area_turfs(area/checked_area)
	if(!checked_area)
		return null

	var/list/turfs = new/list()
	for(var/turf/counted_turfs in contents_of(checked_area)) //Cheap. Efficient. Lovely.
		turfs += counted_turfs
	return turfs

//Takes: Area type as text string or as typepath OR an instance of the area.
//Returns: A list of all atoms	(objs, turfs, mobs) in areas of that type of that type in the world.
/proc/get_area_all_atoms(areatype)
	if(!areatype) return null
	if(istext(areatype)) areatype = text2path(areatype)
	if(isarea(areatype))
		var/area/areatemp = areatype
		areatype = areatemp.type

	var/list/atoms = new/list()
	for(var/area/N in world)
		if(istype(N, areatype))
			for(var/atom/A in N)
				atoms += A
	return atoms

//Takes: Area as an instance of the area.
//Returns: A list of all atoms	(objs, turfs, mobs) in the selected area.
/proc/get_current_area_atoms(area/checked_area)
	if(!checked_area)
		return null

	var/list/atoms = new/list()
	for(var/atom/A in contents_of(checked_area))
		atoms += A
	return atoms

/datum/coords //Simple datum for storing coordinates.
	var/x_pos = null
	var/y_pos = null
	var/z_pos = null

/proc/get_cardinal_dir(atom/A, atom/B)
	READS_FROM() // two places on the map, asked when a choice is made
	var/dx = abs(B.x - A.x)
	var/dy = abs(B.y - A.y)
	return get_dir(A, B) & (rand() * (dx+dy) < dy ? 3 : 12)

/proc/view_or_range(distance = world.view , center , type)
	switch(type)
		if("view")
			. = view(distance,center)
		if("range")
			. = range(distance,center)
	return

/proc/get_mob_with_client_list()
	var/list/mobs = list()
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if (M.client)
			mobs += M
	return mobs

/proc/parse_zone(zone)
	if(zone == BP_R_HAND) return "right hand"
	else if (zone == BP_L_HAND) return "left hand"
	else if (zone == BP_L_ARM) return "left arm"
	else if (zone == BP_R_ARM) return "right arm"
	else if (zone == BP_L_LEG) return "left leg"
	else if (zone == BP_R_LEG) return "right leg"
	else if (zone == BP_L_FOOT) return "left foot"
	else if (zone == BP_R_FOOT) return "right foot"
	else if (zone == BP_L_HAND) return "left hand"
	else if (zone == BP_R_HAND) return "right hand"
	else if (zone == BP_L_FOOT) return "left foot"
	else if (zone == BP_R_FOOT) return "right foot"
	else return zone

/proc/get(atom/current, type)
	while(current)
		if(istype(current, type))
			return current
		current = current.loc
	return null

/proc/get_turf_or_move(turf/location)
	return get_turf(location)

/proc/istool(O)
	if(O && is_type_in_list(O, GLOB.common_tools))
		return 1
	return 0

/proc/reverse_direction(dir)
	return GLOB.reverse_dir[dir]

/proc/gotwallitem(loc, dir)
	for(var/obj/O in contents_of(loc))
		if(O.flags & WALL_ITEM)
			//Direction works sometimes
			if(O.dir == dir)
				return 1

			//Some stuff doesn't use dir properly, so we need to check pixel instead
			switch(dir)
				if(SOUTH)
					if(O.pixel_y > 10)
						return 1
				if(NORTH)
					if(O.pixel_y < -10)
						return 1
				if(WEST)
					if(O.pixel_x > 10)
						return 1
				if(EAST)
					if(O.pixel_x < -10)
						return 1

	//Some stuff is placed directly on the wallturf (signs)
	for(var/obj/O in get_step(loc, dir))
		if(O.flags & WALL_ITEM)
			if(O.pixel_x == 0 && O.pixel_y == 0)
				return 1
	return 0

/proc/topic_link(datum/D, arglist, content)
	if(istype(arglist,/list))
		arglist = list2params(arglist)
	return "<a href='byond://?src=[REF(D)];[arglist]'>[content]</a>"

/proc/get_random_colour(simple, lower=0, upper=255)
	var/colour
	if(simple)
		colour = pick(list("FF0000","FF7F00","FFFF00","00FF00","0000FF","4B0082","8F00FF"))
	else
		for(var/i=1;i<=3;i++)
			var/temp_col = "[num2hex(rand(lower,upper), 2)]"
			if(length(temp_col )<2)
				temp_col  = "0[temp_col]"
			colour += temp_col
	return "#[colour]"

/proc/color_square(red, green, blue, hex)
	var/color = hex ? hex : "#[num2hex(red, 2)][num2hex(green, 2)][num2hex(blue, 2)]"
	return "<span style='font-face: fixedsys; font-size: 14px; background-color: [color]; color: [color]'>___</span>"

GLOBAL_DATUM(dview_mob, /mob/dview)

//Version of view() which ignores darkness, because BYOND doesn't have it.
/proc/dview(range = world.view, center, invis_flags = 0)
	if(!center)
		return
	if(!GLOB.dview_mob) // Debugging
		GLOB.dview_mob = new

	GLOB.dview_mob.loc = center // ALLOW(containment): dview mob: hot view() helper, abstract placement without Enter/Crossed

	GLOB.dview_mob.see_invisible = invis_flags

	. = view(range, GLOB.dview_mob)
	GLOB.dview_mob.loc = null // ALLOW(containment): dview mob: hot view() helper, abstract nullspace park

/mob/dview
	invisibility = INVISIBILITY_ABSTRACT
	density = FALSE

	anchored = TRUE

	see_in_dark = 1e6

/// We don't want to be in any mob registry; we're a dummy not a mob.
/mob/dview/skips_registry(registry_id)
	return TRUE

// The shared dview mob refuses deletion unless forced, then is replaced.
/mob/dview/lifecycle_keep(force)
	stack_trace("Attempt to delete the dview_mob: [log_info_line(src)]")
	return !force

/mob/dview/on_destroy(force)
	GLOB.dview_mob = new
	..()

/proc/screen_loc2turf(scr_loc, turf/origin)
	var/tX = splittext(scr_loc, ",")
	var/tY = splittext(tX[2], ":")
	var/tZ = origin.z
	tY = tY[1]
	tX = splittext(tX[1], ":")
	tX = tX[1]
	tX = max(1, min(world.maxx, origin.x + (text2num(tX) - (world.view + 1))))
	tY = max(1, min(world.maxy, origin.y + (text2num(tY) - (world.view + 1))))
	return locate(tX, tY, tZ)

// Displays something as commonly used (non-submultiples) SI units.
//ultra range (no limitations on distance, faster than range for distances > 8); including areas drastically decreases performance
/proc/urange(dist=0, atom/center=null, orange=0, areas=0)
	if(!dist)
		if(!orange)
			return list(center)
		else
			return list()

	if(!get_turf(center))
		return list()

	var/list/turfs = RANGE_TURFS(dist, center)
	if(orange)
		turfs -= get_turf(center)
	. = list()
	for(var/turf/T as anything in turfs)
		. += T
		. += T.contents
		if(areas)
			. |= T.loc

// Returns direction-string, rounded to multiples of 22.5, from the first parameter to the second
// N, NNE, NE, ENE, E, ESE, SE, SSE, S, SSW, SW, WSW, W, WNW, NW, NNW
/proc/get_adir(turf/A, turf/B)
	var/degree = Get_Angle(A, B)
	switch(round(degree%360, 22.5))
		if(0)
			return "North"
		if(22.5)
			return "North-Northeast"
		if(45)
			return "Northeast"
		if(67.5)
			return "East-Northeast"
		if(90)
			return "East"
		if(112.5)
			return "East-Southeast"
		if(135)
			return "Southeast"
		if(157.5)
			return "South-Southeast"
		if(180)
			return "South"
		if(202.5)
			return "South-Southwest"
		if(225)
			return "Southwest"
		if(247.5)
			return "West-Southwest"
		if(270)
			return "West"
		if(292.5)
			return "West-Northwest"
		if(315)
			return "Northwest"
		if(337.5)
			return "North-Northwest"

GLOBAL_TABLE(get_fancy_list_of_atom_types, GLOBAL_PROC_REF(build_get_fancy_list_of_atom_types))

GLOBAL_TABLE(get_fancy_list_of_datum_types, GLOBAL_PROC_REF(build_get_fancy_list_of_datum_types))

/proc/filter_fancy_list(list/L, filter as text)
	var/list/matches = list()
	for(var/key in L)
		var/value = L[key]
		if(findtext("[key]", filter) || findtext("[value]", filter))
			matches[key] = value
	return matches

/proc/IsValidSrc(datum/D)
	if(istype(D))
		return !QDELETED(D)
	return FALSE

/// No op
/proc/pass(...)
	return

// \ref behaviour got changed in 512 so this is necesary to replicate old behaviour.
// If it ever becomes necesary to get a more performant REF(), this lies here in wait
// #define REF(thing) (thing && istype(thing, /datum) && (thing:datum_flags & DF_USE_TAG) && thing:tag ? "[thing:tag]" : "\ref[thing]")
// Painlessly creates an <a href=...> element.
// First argument is where to send the Topic call to when clicked. Should be a reference to an object. This is generally src, but not always.
// Second one is for all the params that will be sent. Uses an assoc list (e.g. "value" = "5").
// Note that object refs will be converted to text, as if \ref[thing] was done. To get the ref back on Topic() side, you will need to use locate().
// Third one is the text that will be clickable.
/proc/href(href_src, list/href_params, href_text)
	return "<a href='byond://?src=[REF(href_src)];[list2params(href_params)]'>[href_text]</a>"

/proc/spiral_range(dist = 0, atom/center = null, orange = FALSE)
	var/list/atom_list = list()
	var/turf/t_center = get_turf(center)
	if(!t_center)
		return list()

	if(!orange)
		atom_list += t_center
		atom_list += t_center.contents

	if(!dist)
		return atom_list

	var/turf/checked_turf
	var/y
	var/x
	var/c_dist = 1

	while( c_dist <= dist )
		y = t_center.y + c_dist
		x = t_center.x - c_dist + 1
		for(x in x to t_center.x + c_dist)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				atom_list += checked_turf
				atom_list += checked_turf.contents

		y = t_center.y + c_dist - 1
		x = t_center.x + c_dist
		for(y in t_center.y - c_dist to y)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				atom_list += checked_turf
				atom_list += checked_turf.contents

		y = t_center.y - c_dist
		x = t_center.x + c_dist - 1
		for(x in t_center.x - c_dist to x)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				atom_list += checked_turf
				atom_list += checked_turf.contents

		y = t_center.y - c_dist + 1
		x = t_center.x - c_dist
		for(y in y to t_center.y + c_dist)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				atom_list += checked_turf
				atom_list += checked_turf.contents
		c_dist++

	return atom_list

/*
	get_holder_at_turf_level(): Similar to get_turf(), will return the "highest up" holder of this atom, excluding the turf.
	Example: A fork inside a box inside a locker will return the locker. Essentially, get_just_before_turf().
*/ //Credit to /vg/
/proc/get_holder_at_turf_level(const/atom/movable/O)
	if(!istype(O)) //atom/movable does not include areas
		return
	var/atom/A
	for(A=O, A && !isturf(A.loc), A=A.loc);  // semicolon is for the empty statement
	return A

/proc/split_into_3(total)
	if(!total || !isnum(total))
		return

	var/part1 = rand(0,total)
	var/part2 = rand(0,total)
	var/part3 = total-(part1+part2)

	if(part3<0)
		part1 = total-part1
		part2 = total-part2
		part3 = -part3

	return list(part1, part2, part3)

//Sender is optional
/proc/admin_chat_message(message = "Debug Message", color = "#FFFFFF", sender)
	if (!CONFIG_GET(string/chat_webhook_url) || !message)
		return
	var/query_string = "type=adminalert"
	query_string += "&key=[url_encode(CONFIG_GET(string/chat_webhook_key))]"
	query_string += "&msg=[url_encode(message)]"
	query_string += "&color=[url_encode(color)]"
	if(sender)
		query_string += "&from=[url_encode(sender)]"
	http_get_async("[CONFIG_GET(string/chat_webhook_url)]?[query_string]")

/proc/admin_action_message(admin = "INVALID", user = "INVALID", action = "INVALID", reason = "INVALID", time = "INVALID")
	if (!CONFIG_GET(string/chat_webhook_url) || !action)
		return
	var/query_string = "type=adminaction"
	query_string += "&key=[url_encode(CONFIG_GET(string/chat_webhook_key))]"
	query_string += "&admin=[url_encode(admin)]"
	query_string += "&user=[url_encode(user)]"
	query_string += "&action=[url_encode(action)]"
	query_string += "&reason=[url_encode(reason)]"
	query_string += "&time=[url_encode(time)]"
	http_get_async("[CONFIG_GET(string/chat_webhook_url)]?[query_string]")
