// These pins can only contain directions (1,2,4,8...) or null.
/datum/integrated_io/dir
	name = "dir pin"

/datum/prompt/number/typed_pin_dir
	var/original_client_ckey

/datum/integrated_io/dir/ask_for_pin_data(mob/user)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/number/typed_pin_dir, PROC_REF(pin_input_entered), answerer = user, original_client_ckey = original_client_ckey, timeout = 0, question = "Please type in a valid dir number.  Valid dirs are;\nNorth/Fore = [NORTH],\nSouth/Aft = [SOUTH],\nEast/Starboard = [EAST],\nWest/Port = [WEST],\nNortheast = [NORTHEAST],\nNorthwest = [NORTHWEST],\nSoutheast = [SOUTHEAST],\nSouthwest = [SOUTHWEST],\nUp = [UP],\nDown = [DOWN]", title = "[src] dir writing", min_value = 0, max_value = INFINITY, step = 1)

/datum/integrated_io/dir/proc/pin_input_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/typed_pin_dir/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : A.actor
	if(!user)
		return
	var/new_data = A.answer.answer_value
	if(isnum(new_data) && holder().check_interactivity(user) )
		to_chat(user, span_notice("You input [new_data] into the pin."))
		write_data_to_pin(new_data)

/datum/integrated_io/dir/write_data_to_pin(new_data)
	if(isnull(new_data) || (new_data in (GLOB.alldirs + list(UP, DOWN))))
		data = new_data
		holder().on_data_written()

/datum/integrated_io/dir/display_pin_type()
	return IC_FORMAT_DIR

/datum/integrated_io/dir/display_data(input)
	if(!isnull(data))
		return "([dir2text(data)])"
	return ..()
