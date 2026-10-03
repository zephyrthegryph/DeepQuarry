// The crew transfer system's API (code/modules/vote/transfer_service.dm declares the system).
//
//   SStransfer.modify_hard_end(user)   admin prompt to move the shift's hard end
//   SStransfer.get_hard_end()          the shift's hard end, in deciseconds of round time

/datum/system/transfer/proc/modify_hard_end(client/user)
	om_ask(user, /datum/om/prompt/number, PROC_REF(hard_end_entered), default = shift_hard_end / 600, title = "Shift End", message = "Modify the shift end timer (Input in Minutes)", requires = PROMPT_ADMIN(R_ADMIN|R_EVENT|R_SERVER))

///Accessor proc for getting the shift hard end.
/datum/system/transfer/proc/get_hard_end()
	return shift_hard_end
