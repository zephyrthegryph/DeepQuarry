// cooldowns: lazy state of /atom (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// Each field is an END time (a cooldown: world.time + duration) or a START point on a clock (a stamp), 0 while never set. Read with STATE_PEEK(A, cooldowns, field),
// write with STATE_SET(A, cooldowns, field, value); a cooldown is ready while the field is below world.time, a stamp's age is TIME_NOW(clock, A) - field.

/datum/cooldowns_state
	parent_type = /datum/lazy_state
	var/breath_sound_cooldown = 0
	var/chew_cooldown = 0
	/// when the climb op in flight began
	var/climb_started = 0
	var/cpr_time = 0
	var/disarm_cooldown = 0
	var/fear_sound_cooldown = 0
	var/hud_full_refresh_at = 0
	/// the last scheduled breath on the mob's own (bio) clock, so a breathing step woken from sleep breathes when one is due
	var/last_breath_at = 0
	/// when a mover last bumped this one (doors rate-limit their bump-open by it)
	var/last_bumped = 0
	/// when the client last moved this mob, for movement smoothing
	var/last_move_time = 0
	var/last_special = 0
	var/next_click = 0
	var/next_emote = 0
	var/next_emote_refresh = 0
	var/next_move = 0
	var/next_play_vent = 0
	var/next_preyloop = 0
	var/next_sonar_ping = 0
	var/push_lying_cooldown = 0
	var/resist_cooldown = 0
	var/slip_protect = 0
	var/spit_cooldown = 0
	var/taste_cooldown = 0
	var/taste_repeat_cooldown = 0
	var/venom_milking_cd = 0
	var/xylophone = 0
