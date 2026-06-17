// Combat-AI player-facing tracing.
//
// When a player is fighting (or being hunted by) the modern AI, this writes a
// readable, chronological trace of what the AI is doing to data/logs/<run>/debug.log
// under the `debug-dqai` category — perception (who got noticed and how), behavior
// selection (which behavior won and its score), stance shifts, every vore/grapple
// step, stagger, and pack-lord orders. The point is that a live bug report ("I got
// instantly vored", "they swarmed me from across the map") can be diagnosed from the
// log instead of inferred from the code.
//
// Cost control: every call is gated on GLOB.dqai_player_debug (a runtime toggle, on
// by default) AND on a PLAYER actually being involved in the event — the trace only
// fires for AI that is targeting, fighting, eating, or being hit by a client mob, so
// idle fauna on a packed layer cost nothing. Flip it live with the Toggle DQAI Debug
// admin verb, or set GLOB.dqai_player_debug = FALSE.

/// Master runtime switch for the AI player trace. ON by default so issues are visible.
GLOBAL_VAR_INIT(dqai_player_debug, TRUE)

/// A compact, readable identity for a mob in the trace: "name(type)@(x,y,z)".
/proc/dqai_dbg_who(atom/A)
	if(!A)
		return "null"
	var/turf/T = get_turf(A)
	var/loc_str = T ? "([T.x],[T.y],[T.z])" : "(?)"
	var/tail = ""
	if(ismob(A))
		var/mob/M = A
		if(M.client)
			tail = "<PLAYER:[M.ckey]>"
	return "[A.name][tail]@[loc_str]"

/// TRUE if a player (client mob) is part of this event — either actor or subject, or
/// the actor's brain is currently locked onto a player. Keeps the trace player-relevant
/// and cheap.
/proc/dqai_dbg_player_involved(atom/actor, atom/subject)
	if(ismob(actor))
		var/mob/M = actor
		if(M.client)
			return TRUE
	if(ismob(subject))
		var/mob/M = subject
		if(M.client)
			return TRUE
	if(isliving(actor))
		var/mob/living/L = actor
		if(L.ai_brain && ismob(L.ai_brain.primary_threat))
			var/mob/threat = L.ai_brain.primary_threat
			if(threat.client)
				return TRUE
	return FALSE

/// Write one trace line. `category` is a short tag (PERCEIVE / SELECT / VORE / STAGGER /
/// LORD / MOVE / …); `actor` is the AI mob; `subject` is the other party (prey/target),
/// optional. No-op unless the master switch is on and a player is involved.
/proc/dqai_pdbg(atom/actor, category, msg, atom/subject)
	if(!GLOB.dqai_player_debug)
		return
	if(!dqai_dbg_player_involved(actor, subject))
		return
	var/line = "[category] | [dqai_dbg_who(actor)] | [msg]"
	if(subject)
		line += " | subj=[dqai_dbg_who(subject)]"
	logger.Log(LOG_CATEGORY_DEBUG_DQAI, line)

// --- Admin toggle -----------------------------------------------------------

/client/proc/toggle_dqai_debug()
	set name = "Toggle DQAI Debug"
	set category = "Debug"
	set desc = "Toggle the combat-AI player trace (debug-dqai in debug.log)."
	if(!check_rights(R_DEBUG))
		return
	GLOB.dqai_player_debug = !GLOB.dqai_player_debug
	to_chat(usr, span_notice("Combat-AI player trace is now [GLOB.dqai_player_debug ? "ON" : "OFF"]."))
	log_and_message_admins("toggled the combat-AI player trace [GLOB.dqai_player_debug ? "ON" : "OFF"].")
