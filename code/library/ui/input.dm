// The engine queues window input; the presentation library supplies tgui dispatch.
/datum/tgui/input_window_action(action, list/payload, datum/state)
	return on_act_message(action, payload, state)
