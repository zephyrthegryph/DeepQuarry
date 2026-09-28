#ifndef OVERRIDE_BAN_SYSTEM
//Blocks an attempt to connect before even creating our client datum thing.
/world/IsBanned(key, address, computer_id, type, real_bans_only=FALSE)
	if (!key || (!real_bans_only && (!address || !computer_id)))
		if(real_bans_only)
			return FALSE
		log_access("Failed Login (invalid data): [key] [address]-[computer_id]")
		return list("reason"="invalid login data", "desc"="Error: Could not check ban status, Please try again. Error message: Your computer provided invalid or blank information to the server on connection (byond username, IP, and Computer ID.) Provided information for reference: Username:'[key]' IP:'[address]' Computer ID:'[computer_id]'. (If you continue to get this error, please restart byond or contact byond support.)")

	if(ckey(key) in GLOB.admin_datums)
		return ..()

	//Guest Checking
	if(!CONFIG_GET(flag/guests_allowed) && IsGuestKey(key))
		log_access("Failed Login: [key] - Guests not allowed")
		message_admins(span_blue("Failed Login: [key] - Guests not allowed"))
		return list("reason"="guest", "desc"="\nReason: Guests not allowed. Please sign in with a byond account.")

	//check if the IP address is a known TOR node
	if(config && CONFIG_GET(flag/ToRban) && ToRban_isbanned(address))
		log_access("Failed Login: [src] - Banned: ToR")
		message_admins(span_blue("Failed Login: [src] - Banned: ToR"))
		//ban their computer_id and ckey for posterity
		AddBan(ckey(key), computer_id, "Use of ToR", "Automated Ban", 0, 0)
		return list("reason"="Using ToR", "desc"="\nReason: The network you are using to connect has been banned.\nIf you believe this is a mistake, please request help at [CONFIG_GET(string/banappeals)]")


	if(CONFIG_GET(flag/ban_legacy_system))

		//Ban Checking
		. = CheckBan( ckey(key), computer_id, address )
		if(.)
			log_suspicious_login("Failed Login: [key] [computer_id] [address] - Banned [.["reason"]]")
			message_admins(span_blue("Failed Login: [key] id:[computer_id] ip:[address] - Banned [.["reason"]]"))
			return .

		return ..()	//default pager ban stuff

	// The database ban check can't run here: this hook must answer at once and a query answers
	// later. The login gate runs it (/client/proc/login_ban_check(), in log_client_to_db()'s
	// flow) and holds the client until it answers.
	return ..()	//default pager ban stuff
#endif
