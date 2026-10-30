// The crew transfer system's API (code/modules/vote/transfer_service.dm declares the system).
//
//   SStransfer.modify_hard_end(user)   admin prompt to move the shift's hard end
//   SStransfer.get_hard_end()          the shift's hard end, in deciseconds of round time

/datum/system/transfer/proc/modify_hard_end(client/user)
	open_request(src, /datum/prompt/number, PROC_REF(hard_end_entered), answerer = user, title = "Shift End", question = "Modify the shift end timer (Input in Minutes)", default = shift_hard_end / 600, rights = R_ADMIN|R_EVENT|R_SERVER, timeout = 0)

///Accessor proc for getting the shift hard end.
/datum/system/transfer/proc/get_hard_end()
	return shift_hard_end
