// These pins can only contain directions (1,2,4,8...) or null.
/datum/integrated_io/dir
	name = "dir pin"

/datum/integrated_io/dir/ask_for_pin_data(mob/user)
	var/new_data = rerun_ask(user, "k6", PROC_REF(ask_for_pin_data), args, /datum/om/prompt/number, message = "Please type in a valid dir number.  Valid dirs are;\nNorth/Fore = [NORTH],\nSouth/Aft = [SOUTH],\nEast/Starboard = [EAST],\nWest/Port = [WEST],\nNortheast = [NORTHEAST],\nNorthwest = [NORTHWEST],\nSoutheast = [SOUTHEAST],\nSouthwest = [SOUTHWEST],\nUp = [UP],\nDown = [DOWN]", title = "[src] dir writing")
	if(isnull(new_data))
		return
	if(isnum(new_data) && holder.check_interactivity(user) )
		to_chat(user, span_notice("You input [new_data] into the pin."))
		write_data_to_pin(new_data)

/datum/integrated_io/dir/write_data_to_pin(new_data)
	if(isnull(new_data) || (new_data in (GLOB.alldirs + list(UP, DOWN))))
		data = new_data
		holder.on_data_written()

/datum/integrated_io/dir/display_pin_type()
	return IC_FORMAT_DIR

/datum/integrated_io/dir/display_data(input)
	if(!isnull(data))
		return "([dir2text(data)])"
	return ..()
