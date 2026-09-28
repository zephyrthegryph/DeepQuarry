ADMIN_VERB_VISIBILITY(set_server_fps, ADMIN_VERB_VISIBLITY_FLAG_MAPPING_DEBUG)
ADMIN_VERB(set_server_fps, R_DEBUG, "Set Server FPS", "Sets game speed in frames-per-second. Can potentially break the game", ADMIN_CATEGORY_DEBUG_DANGEROUS)
	var/cfg_fps = CONFIG_GET(number/fps)
	var/_answer_a1 = verb_ask(user, "a1", args, /datum/om/prompt/number, message = "Sets game frames-per-second. Can potentially break the game (default: [cfg_fps])", title = "FPS", default = world.fps)
	if(isnull(_answer_a1))
		return
	var/new_fps = round(_answer_a1)

	if(new_fps <= 0)
		to_chat(user, span_danger("Error: set_server_fps(): Invalid world.fps value. No changes made."), confidential = TRUE)
		return
	if(new_fps > cfg_fps * 1.5)
		var/_answer_a2 = verb_ask(user, "a2", args, /datum/om/prompt/choice/alert, message = "You are setting fps to a high value:\n\t[new_fps] frames-per-second\n\tconfig.fps = [cfg_fps]", title = "Warning!", choices = list("Confirm","ABORT-ABORT-ABORT"))
		if(isnull(_answer_a2))
			return
		if(_answer_a2 != "Confirm")
			return

	var/msg = "[key_name(user)] has modified world.fps to [new_fps]"
	log_admin(msg, 0)
	message_admins(msg, 0)
	//SSblackbox.record_feedback("nested tally", "admin_toggle", 1, list("Set Server FPS", "[new_fps]")) // If you are copy-pasting this, ensure the 4th parameter is unique to the new proc!
	feedback_add_details("admin_verb", "SETFPS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	CONFIG_SET(number/fps, new_fps)
	world.change_fps(new_fps)
