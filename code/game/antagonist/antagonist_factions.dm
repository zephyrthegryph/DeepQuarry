/mob/living/proc/convert_to_rev(mob/M as mob in oview(src))
	set name = "Convert Bourgeoise"
	set category = VERB_CAT_ABILITIES_ANTAG
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

	if(SSantag.player_is_antag(player))
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
	open_request(src, /datum/prompt/choice/faction_join, PROC_REF(faction_join_answered), answerer = player.current, asker = src, player = player, faction = faction)

/// Asked to join a faction; a cancel is a refusal.
/datum/prompt/choice/faction_join
	buttons = TRUE
	timeout = 0
	var/datum/mind/player
	var/datum/antagonist/faction

CAPABILITIES(/datum/prompt/choice/faction_join)
	ref_one(nameof(player), /datum/mind)
	ref_one(nameof(faction), /datum/antagonist)

/datum/prompt/choice/faction_join/prepare(datum/act/A)
	..()
	// Named request fields are written before prepare; register their actual reference views.
	var/datum/mind/captured_player = player
	var/datum/antagonist/captured_faction = faction
	rel_clear(src, nameof(player))
	rel_clear(src, nameof(faction))
	rel_set(src, nameof(player), captured_player)
	rel_set(src, nameof(faction), captured_faction)
	var/static/list/join_buttons = list("No!", "Yes!")
	choices = join_buttons
	title = "Join the [faction.faction_descriptor]?"
	question = "Asked by [asker]: Do you want to join the [faction.faction_descriptor]?"

/mob/living/proc/faction_join_answered(datum/act/request/A)
	var/datum/prompt/choice/faction_join/ask = A.request
	if(!A.answer && ask.outcome != REQ_CANCELLED)
		return
	var/datum/mind/player = ask.player
	var/datum/antagonist/faction = ask.faction
	if(QDELETED(ask.answerer) || QDELETED(player) || QDELETED(faction))
		return
	var/accepted = A.answer && ask.value == "Yes!"
	if(accepted && faction.add_antagonist_mind(player, 0, faction.faction_role_text, faction.faction_welcome))
		to_chat(src, span_notice("\The [player.current] joins the [faction.faction_descriptor]!"))
		return
	if(!accepted)
		to_chat(player, span_danger("You reject this traitorous cause!"))
	to_chat(src, span_danger("\The [player.current] does not support the [faction.faction_descriptor]!"))

/mob/living/proc/convert_to_loyalist(mob/M as mob in oview(src))
	set name = "Convert Recidivist"
	set category = VERB_CAT_ABILITIES_ANTAG
	if(!M.mind)
		return
	convert_to_faction(M.mind, GLOB.loyalists)
