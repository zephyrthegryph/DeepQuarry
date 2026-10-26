/proc/GameOver()
	if(!GLOB.hadevent)
		GLOB.hadevent = 1
		message_admins("The apocalypse has begun! (this holiday event can be disabled by toggling events off within 60 seconds)")
		after(null, 1 MINUTE, GLOBAL_PROC_REF(game_over_begins)) // the global owner: a round event

/proc/game_over_begins()
	if(!CONFIG_GET(flag/allow_random_events))	return
	Show2Group4Delay(ScreenText(null,"<center>" + span_red(span_extramassive("GAME OVER")) + "</center>"),null,150)
	for(var/i = 0 to 3)
		after(null, i * 5 SECONDS, GLOBAL_PROC_REF(spawn_dynamic_event))
