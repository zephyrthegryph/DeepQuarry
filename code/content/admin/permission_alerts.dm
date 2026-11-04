/// Returns if the given client is an admin, REGARDLESS of if they're deadminned or not.
///proc/is_admin(client/client)
//	return !isnull(GLOB.admin_datums[client.ckey]) || !isnull(GLOB.deadmins[client.ckey])

/// Sends a message in the event that someone attempts to elevate their permissions through invoking a certain proc.
/// The offender is the admin whose advanced proc call is running (GLOB.AdminProcCaller, a ckey), not an ambient usr.
/proc/alert_to_permissions_elevation_attempt()
	var/message = " has tried to elevate permissions!"
	message_admins(key_name_admin(GLOB.AdminProcCaller) + message)
	log_admin(key_name(GLOB.AdminProcCaller) + message)
