//For synths who have no hands.
/obj/item/communicator/integrated
	name = "integrated communicator"
	desc = "A circuit used for long-range communications, able to be integrated into a system."

//A stupid hack because synths don't use languages properly or something.
//I don't want to go digging in saycode for a week, so BS it as translation software or something.

// Proc: open_connection_to_ghost()
// Parameters: 2 (refer to base definition for arguments)
// Description: Synths don't use languages properly, so this is a bandaid fix until that can be resolved..
/obj/item/communicator/integrated/open_connection_to_ghost(user, candidate)
	..(user, candidate)
	after(src, 0.1 SECONDS, PROC_REF(set_ghost_voice_universal))

/obj/item/communicator/integrated/proc/set_ghost_voice_universal()
	for(var/mob/living/voice/V in contents)
		V.set_universal_speak(1)
		V.set_universal_understand(1)

/// Lets synths use their communicators without hands (the Use Communicator command of their panels).
/obj/item/communicator/integrated/proc/use_by(mob/user)
	if(user.stat == DEAD)
		to_chat(user, "You can't do that because you are dead!")
		return

	attack_self(user)

/obj/item/communicator/integrated/tgui_static_data(mob/user)
	. = ..()
	if(isrobot(loc))
		var/mob/living/silicon/robot/robot_owner = loc
		.["theme"] = robot_owner.get_ui_theme()
