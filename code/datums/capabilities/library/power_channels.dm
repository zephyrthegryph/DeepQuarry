// power_channels(): an area power controller's channels (equipment, lighting, environment), its main
// breaker and night-shift lighting (doc/rewrite/dx_conventions.md §2). It owns their UI data
// (data["caps"]["power"]), the channel indicator glows ("apco<channel>-<mode>" while the holder says
// power_channels_lit()) and the UI actions act_channel / act_breaker / act_nightshift, so the holder
// writes none of them. State stays on the holder, behind a small interface of well-known procs:
//	power_channel_mode(channel) / set_power_channel_mode(channel, mode)   POWER_CHANNEL_* / POWERCHAN_*
//	power_channel_load(channel)                                           watts
//	power_breaker() / set_power_breaker(on)
//	power_nightshift() / set_power_nightshift(mode)                         NIGHTSHIFT_*
//	power_nightshift_lit()
//	power_channels_lit()                                                  draw the glows now
//
//	. += power_channels()

/datum/capability/power_channels
	layer_name = "power"
	data_type = /datum/power_channels_data

/datum/power_channels_data
	/// The night lighting breaker cycles for a second after each switch.
	COOLDOWN_DECLARE(nightshift_cooldown)

/proc/power_channels()
	return list(new /datum/capability/power_channels)

/// Channel titles, by POWER_CHANNEL_* + 1.
GLOBAL_LIST_INIT(power_channel_titles, list("Equipment", "Lighting", "Environment"))

/datum/capability/power_channels/draw(atom/holder, datum/look/look)
	if(!holder.power_channels_lit())
		return
	for(var/channel in POWER_CHANNEL_EQUIPMENT to POWER_CHANNEL_ENVIRON)
		look.glow("apco[channel]-[holder.power_channel_mode(channel)]")

/datum/capability/power_channels/ui_data(atom/holder, mob/user, list/data)
	var/list/channels = list()
	for(var/channel in POWER_CHANNEL_EQUIPMENT to POWER_CHANNEL_ENVIRON)
		channels += list(list(
			"title" = GLOB.power_channel_titles[channel + 1],
			"powerLoad" = round(holder.power_channel_load(channel)),
			"status" = holder.power_channel_mode(channel),
			"topicParams" = list(
				"auto" = list("channel" = channel, "mode" = POWERCHAN_ON_AUTO),
				"on" = list("channel" = channel, "mode" = POWERCHAN_ON),
				"off" = list("channel" = channel, "mode" = POWERCHAN_OFF_AUTO),
			),
		))
	data["powerChannels"] = channels
	data["isOperating"] = holder.power_breaker()
	data["nightshiftLights"] = holder.power_nightshift_lit()
	data["nightshiftSetting"] = holder.power_nightshift()

/datum/capability/power_channels/ui_logged()
	return GLOB.power_channels_logged

GLOBAL_LIST_INIT(power_channels_logged, list("channel" = LOG_GAME, "breaker" = LOG_GAME, "nightshift" = LOG_GAME))

/// Sets one channel: channel POWER_CHANNEL_*, mode POWERCHAN_OFF_AUTO (off), POWERCHAN_ON or POWERCHAN_ON_AUTO.
/datum/capability/power_channels/proc/act_channel(mob/user, atom/holder, channel, mode)
	channel = ui_number(channel, POWER_CHANNEL_EQUIPMENT, POWER_CHANNEL_ENVIRON, round_to = 1)
	mode = ui_number(mode, POWERCHAN_OFF_AUTO, POWERCHAN_ON_AUTO, round_to = 1)
	if(isnull(channel) || isnull(mode))
		return refuse(user, null)
	holder.set_power_channel_mode(channel, mode)
	return TRUE

/datum/capability/power_channels/proc/act_breaker(mob/user, atom/holder)
	holder.set_power_breaker(!holder.power_breaker())
	return TRUE

/datum/capability/power_channels/proc/act_nightshift(mob/user, atom/holder, nightshift)
	nightshift = ui_number(nightshift, NIGHTSHIFT_AUTO, NIGHTSHIFT_ALWAYS, round_to = 1)
	if(isnull(nightshift) || nightshift == holder.power_nightshift())
		return refuse(user, null)
	var/datum/power_channels_data/D = cap_data(holder, src)
	if(!COOLDOWN_FINISHED(D, nightshift_cooldown))
		return refuse(user, "[holder]'s night lighting circuit breaker is still cycling!")
	COOLDOWN_START(D, nightshift_cooldown, 1 SECOND)
	holder.set_power_nightshift(nightshift)
	return TRUE

// ---- the holder interface (defaults: no channels) ----
/atom/proc/power_channel_mode(channel)
	return POWERCHAN_OFF
/atom/proc/set_power_channel_mode(channel, mode)
	return FALSE
/atom/proc/power_channel_load(channel)
	return 0
/atom/proc/power_breaker()
	return FALSE
/atom/proc/set_power_breaker(on)
	return FALSE
/atom/proc/power_nightshift()
	return NIGHTSHIFT_AUTO
/atom/proc/set_power_nightshift(mode)
	return FALSE
/atom/proc/power_nightshift_lit()
	return FALSE
/atom/proc/power_channels_lit()
	return FALSE
