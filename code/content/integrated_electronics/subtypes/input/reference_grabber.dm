/obj/item/integrated_circuit/input/reference_grabber // Allows grabbing non-adjacet refs, and their coords. (relative)
	name = "reference grabber"
	desc = "A handheld mechanism that can be aimed to attain distant references."
	extended_desc = "When used, it will capture the reference of the target, and output coordinates relative to the user."
	icon_state = "video_camera"
	complexity = 10
	inputs = list()
	outputs = list(
		"clicked ref" = IC_PINTYPE_REF,
		"X" = IC_PINTYPE_NUMBER,
		"Y" = IC_PINTYPE_NUMBER
	)
	activators = list(
		"on success" = IC_PINTYPE_PULSE_OUT,
		"on failure" = IC_PINTYPE_PULSE_OUT
	)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH

/obj/item/integrated_circuit/input/reference_grabber/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	if(!assembly() || user.get_active_hand() != assembly())
		activate_pin(2) // Failure pin, not in assembly, or not held.
		return

	if(!target || get_dist(user, target) > 7 || !(target in view(user)))
		activate_pin(2) // Failure pin, out of range or not visible.
		return

	set_pin_data(IC_OUTPUT, 1, ic_ref(target))
	set_pin_data(IC_OUTPUT, 2, target.x - user.x)
	set_pin_data(IC_OUTPUT, 3, target.y - user.y)
	push_data()
	activate_pin(1) // Success pin
