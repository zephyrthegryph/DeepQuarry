/mob/living/proc/convert_to_rev(mob/M as mob in oview(src))
	set name = "Convert Bourgeoise"
	set category = "Abilities.Antag"
	if(!M.mind)
		return
	convert_to_faction(M.mind, GLOB.revs)

/mob/living/proc/convert_to_faction(datum/mind/player, datum/antagonist/faction)

	if(!player || !faction || !player.current)
		return

	if(!faction.faction_verb || !faction.faction_descriptor || !faction.faction_verb)
		return

	if(faction.is_antagonist(player))
		to_chat(src, span_warning("\The [player.current] already serves the [faction.faction_descriptor]."))
		return

	if(SSantag_job.player_is_antag(player))
		to_chat(src, span_warning("\The [player.current]'s loyalties seem to be elsewhere..."))
		return

	if(!faction.can_become_antag(player))
		to_chat(src, span_warning("\The [player.current] cannot be \a [faction.faction_role_text]!"))
		return

	if(!COOLDOWN_FINISHED(player, rev_cooldown))
		to_chat(src, span_danger("You must wait five seconds between attempts."))
		return

	to_chat(src, span_danger("You are attempting to convert \the [player.current]..."))
	log_admin("[src]([src.ckey]) attempted to convert [player.current].")
	message_admins(span_danger("[src]([src.ckey]) attempted to convert [player.current]."))

	COOLDOWN_START(player, rev_cooldown, 100)
	om_ask(player.current, /datum/om/prompt/confirm/faction_join, PROC_REF(faction_join_answered), asker = src, player = player, faction = faction)

/// Asked to join a faction; a cancel is a refusal.
/datum/om/prompt/confirm/faction_join
	yes_text = "Yes!"
	no_text = "No!"
	no_first = TRUE
	answer_on_no = TRUE
	cancel_answer = "No!"
	var/datum/mind/player
	var/datum/antagonist/faction

/datum/om/prompt/confirm/faction_join/prepare()
	title = "Join the [faction.faction_descriptor]?"
	message = "Asked by [asker]: Do you want to join the [faction.faction_descriptor]?"
	return TRUE

/mob/living/proc/faction_join_answered(datum/om/prompt/confirm/faction_join/ask)
	var/datum/mind/player = ask.player
	var/datum/antagonist/faction = ask.faction
	if(ask.yes && faction.add_antagonist_mind(player, 0, faction.faction_role_text, faction.faction_welcome))
		to_chat(src, span_notice("\The [player.current] joins the [faction.faction_descriptor]!"))
		return
	if(!ask.yes)
		to_chat(player, span_danger("You reject this traitorous cause!"))
	to_chat(src, span_danger("\The [player.current] does not support the [faction.faction_descriptor]!"))

/mob/living/proc/convert_to_loyalist(mob/M as mob in oview(src))
	set name = "Convert Recidivist"
	set category = "Abilities.Antag"
	if(!M.mind)
		return
	convert_to_faction(M.mind, GLOB.loyalists)
