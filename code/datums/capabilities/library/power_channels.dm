// power_channels(): an area power controller's channels (equipment, lighting, environment), its main
// breaker and night-shift lighting (doc/rewrite/dx_conventions.md §2). It owns their UI data
// (data["caps"]["power"]), the channel indicator glows (the part "channel-<channel>-<mode>", emissive, while the holder
// says power_channels_lit()) and the UI actions act_channel / act_breaker / act_nightshift, so the holder
// writes none of them. State stays on the holder, behind the capability's holder interface: procs of the capability
// that take the holder (no proc is added to /atom; a holder with channels declares a capability subtype overriding them):
//	channel_mode(holder, channel) / set_channel_mode(holder, channel, mode)   POWER_CHANNEL_* / POWERCHAN_*
//	channel_load(holder, channel)                                             watts
//	breaker(holder) / set_breaker(holder, on)
//	nightshift(holder) / set_nightshift(holder, mode)                         NIGHTSHIFT_*
//	nightshift_lit(holder)
//	channels_lit(holder)                                                      draw the glows now
//
//	. += power_channels(/datum/capability/power_channels/apc)

/datum/capability/power_channels
	layer_name = "power"
	data_type = /datum/power_channels_data

/datum/power_channels_data
	/// The night lighting breaker cycles for a second after each switch.
	COOLDOWN_DECLARE(nightshift_cooldown)

/// The channels; `type`: the holder's subtype implementing the holder interface.
/proc/power_channels(type = /datum/capability/power_channels)
	return list(new type)

/// Channel titles, by POWER_CHANNEL_* + 1.
GLOBAL_LIST_INIT(power_channel_titles, list("Equipment", "Lighting", "Environment"))

/datum/capability/power_channels/draw(atom/holder, datum/look/look)
	if(!channels_lit(holder))
		return
	for(var/channel in POWER_CHANNEL_EQUIPMENT to POWER_CHANNEL_ENVIRON)
		look.part("channel-[channel]", "[channel_mode(holder, channel)]") // a text value: mode 0 is a state too
		look.glow("channel-[channel]", "[channel_mode(holder, channel)]")

/datum/capability/power_channels/ui_data(atom/holder, mob/user, list/data)
	var/list/channels = list()
	for(var/channel in POWER_CHANNEL_EQUIPMENT to POWER_CHANNEL_ENVIRON)
		channels += list(list(
			"title" = GLOB.power_channel_titles[channel + 1],
			"powerLoad" = round(channel_load(holder, channel)),
			"status" = channel_mode(holder, channel),
			"topicParams" = list(
				"auto" = list("channel" = channel, "mode" = POWERCHAN_ON_AUTO),
				"on" = list("channel" = channel, "mode" = POWERCHAN_ON),
				"off" = list("channel" = channel, "mode" = POWERCHAN_OFF_AUTO),
			),
		))
	data["powerChannels"] = channels
	data["isOperating"] = breaker(holder)
	data["nightshiftLights"] = nightshift_lit(holder)
	data["nightshiftSetting"] = nightshift(holder)

TYPE_TABLE(/datum/capability/power_channels, ui_logged_actions, list("channel" = LOG_GAME, "breaker" = LOG_GAME, "nightshift" = LOG_GAME))

/// Sets one channel: channel POWER_CHANNEL_*, mode POWERCHAN_OFF_AUTO (off), POWERCHAN_ON or POWERCHAN_ON_AUTO.
/datum/capability/power_channels/proc/act_channel(mob/user, atom/holder, channel, mode)
	channel = ui_number(channel, POWER_CHANNEL_EQUIPMENT, POWER_CHANNEL_ENVIRON, round_to = 1)
	mode = ui_number(mode, POWERCHAN_OFF_AUTO, POWERCHAN_ON_AUTO, round_to = 1)
	if(isnull(channel) || isnull(mode))
		return refuse(user, null)
	set_channel_mode(holder, channel, mode)
	return TRUE

/datum/capability/power_channels/proc/act_breaker(mob/user, atom/holder)
	set_breaker(holder, !breaker(holder))
	return TRUE

/datum/capability/power_channels/proc/act_nightshift(mob/user, atom/holder, nightshift)
	nightshift = ui_number(nightshift, NIGHTSHIFT_AUTO, NIGHTSHIFT_ALWAYS, round_to = 1)
	if(isnull(nightshift) || nightshift == nightshift(holder))
		return refuse(user, null)
	var/datum/power_channels_data/D = cap_data(holder, src)
	if(!COOLDOWN_FINISHED(D, nightshift_cooldown))
		return refuse(user, "[holder]'s night lighting circuit breaker is still cycling!")
	COOLDOWN_START(D, nightshift_cooldown, 1 SECOND)
	set_nightshift(holder, nightshift)
	return TRUE

// ---- the holder interface (defaults: no channels; a holder's subtype overrides them) ----
/datum/capability/power_channels/proc/channel_mode(atom/holder, channel)
	return POWERCHAN_OFF
/datum/capability/power_channels/proc/set_channel_mode(atom/holder, channel, mode)
	return FALSE
/datum/capability/power_channels/proc/channel_load(atom/holder, channel)
	return 0
/datum/capability/power_channels/proc/breaker(atom/holder)
	return FALSE
/datum/capability/power_channels/proc/set_breaker(atom/holder, on)
	return FALSE
/datum/capability/power_channels/proc/nightshift(atom/holder)
	return NIGHTSHIFT_AUTO
/datum/capability/power_channels/proc/set_nightshift(atom/holder, mode)
	return FALSE
/datum/capability/power_channels/proc/nightshift_lit(atom/holder)
	return FALSE
/datum/capability/power_channels/proc/channels_lit(atom/holder)
	return FALSE
