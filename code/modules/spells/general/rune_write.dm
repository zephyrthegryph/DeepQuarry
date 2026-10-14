/datum/spell/rune_write
	name = "Scribe a Rune"
	desc = "Let's you instantly manifest a working rune."

	school = "evocation"
	charge_max = 100
	charge_type = Sp_RECHARGE
	invocation_type = SpI_NONE

	spell_flags = CONSTRUCT_CHECK

	hud_state = "const_rune"

	smoke_amt = 1

/// The rune (and last word) are asked here, before the cast charges.
/datum/spell/rune_write
	/// What choose_targets() asked for, read by cast().
	var/picked_rune
	var/picked_beacon

/datum/spell/rune_write/choose_targets(mob/user)
	var/static/list/runes = list("Teleport", "Teleport Other", "Spawn a Tome", "Change Construct Type", "Convert", "EMP", "Drain Blood", "See Invisible", "Resurrect", "Hide Runes", "Reveal Runes", "Astral Journey", "Manifest a Ghost", "Imbue Talisman", "Sacrifice", "Wall", "Free Cultist", "Summon Cultist", "Deafen", "Blind", "BloodBoil", "Communicate", "Stun")
	if(!GLOB.cultwords["travel"])
		runerandom()
	var/r = cast_ask(user, "rune", /datum/prompt/choice, question = "Choose a rune to scribe", title = "Rune Scribing", choices = runes, timeout = 30 SECONDS)
	if(!r)
		return list()
	var/beacon
	if(r == "Teleport" || r == "Teleport Other")
		beacon = cast_ask(user, "beacon", /datum/prompt/choice, question = "Select the last rune", title = "Rune Scribing", choices = GLOB.rnwords, timeout = 30 SECONDS)
		if(!beacon)
			return list()
	picked_rune = r
	picked_beacon = beacon
	return list(user)

/datum/spell/rune_write/cast(null, mob/user)
	if(!GLOB.cultwords["travel"])
		runerandom()
	var/r = picked_rune
	var/obj/effect/rune/R = new /obj/effect/rune(user.loc)
	if(istype(user.loc,/turf))
		var/area/A = get_area(user)
		log_and_message_admins("created \an [r] rune at \the [A.name] - [user.loc.x]-[user.loc.y]-[user.loc.z].", user)
		switch(r)
			if("Teleport")
				if(cast_check(1, user))
					var/beacon = picked_beacon
					R.word1=GLOB.cultwords["travel"]
					R.word2=GLOB.cultwords["self"]
					R.word3=beacon
					R.check_icon()
			if("Teleport Other")
				if(cast_check(1, user))
					var/beacon = picked_beacon
					R.word1=GLOB.cultwords["travel"]
					R.word2=GLOB.cultwords["other"]
					R.word3=beacon
					R.check_icon()
			if("Spawn a Tome")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["see"]
					R.word2=GLOB.cultwords["blood"]
					R.word3=GLOB.cultwords["hell"]
					R.check_icon()
			if("Change Construct Type")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["hell"]
					R.word2=GLOB.cultwords["destroy"]
					R.word3=GLOB.cultwords["other"]
					R.check_icon()
			if("Convert")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["join"]
					R.word2=GLOB.cultwords["blood"]
					R.word3=GLOB.cultwords["self"]
					R.check_icon()
			if("EMP")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["destroy"]
					R.word2=GLOB.cultwords["see"]
					R.word3=GLOB.cultwords["technology"]
					R.check_icon()
			if("Drain Blood")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["travel"]
					R.word2=GLOB.cultwords["blood"]
					R.word3=GLOB.cultwords["self"]
					R.check_icon()
			if("See Invisible")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["see"]
					R.word2=GLOB.cultwords["hell"]
					R.word3=GLOB.cultwords["join"]
					R.check_icon()
			if("Resurrect")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["blood"]
					R.word2=GLOB.cultwords["join"]
					R.word3=GLOB.cultwords["hell"]
					R.check_icon()
			if("Hide Runes")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["hide"]
					R.word2=GLOB.cultwords["see"]
					R.word3=GLOB.cultwords["blood"]
					R.check_icon()
			if("Astral Journey")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["hell"]
					R.word2=GLOB.cultwords["travel"]
					R.word3=GLOB.cultwords["self"]
					R.check_icon()
			if("Manifest a Ghost")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["blood"]
					R.word2=GLOB.cultwords["see"]
					R.word3=GLOB.cultwords["travel"]
					R.check_icon()
			if("Imbue Talisman")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["hell"]
					R.word2=GLOB.cultwords["technology"]
					R.word3=GLOB.cultwords["join"]
					R.check_icon()
			if("Sacrifice")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["hell"]
					R.word2=GLOB.cultwords["blood"]
					R.word3=GLOB.cultwords["join"]
					R.check_icon()
			if("Reveal Runes")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["blood"]
					R.word2=GLOB.cultwords["see"]
					R.word3=GLOB.cultwords["hide"]
					R.check_icon()
			if("Wall")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["destroy"]
					R.word2=GLOB.cultwords["travel"]
					R.word3=GLOB.cultwords["self"]
					R.check_icon()
			if("Freedom")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["travel"]
					R.word2=GLOB.cultwords["technology"]
					R.word3=GLOB.cultwords["other"]
					R.check_icon()
			if("Cultsummon")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["join"]
					R.word2=GLOB.cultwords["other"]
					R.word3=GLOB.cultwords["self"]
					R.check_icon()
			if("Deafen")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["hide"]
					R.word2=GLOB.cultwords["other"]
					R.word3=GLOB.cultwords["see"]
					R.check_icon()
			if("Blind")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["destroy"]
					R.word2=GLOB.cultwords["see"]
					R.word3=GLOB.cultwords["other"]
					R.check_icon()
			if("BloodBoil")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["destroy"]
					R.word2=GLOB.cultwords["see"]
					R.word3=GLOB.cultwords["blood"]
					R.check_icon()
			if("Communicate")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["self"]
					R.word2=GLOB.cultwords["other"]
					R.word3=GLOB.cultwords["technology"]
					R.check_icon()
			if("Stun")
				if(cast_check(1, user))
					R.word1=GLOB.cultwords["join"]
					R.word2=GLOB.cultwords["hide"]
					R.word3=GLOB.cultwords["technology"]
					R.check_icon()
	else
		to_chat(user, span_warning("You do not have enough space to write a proper rune."))
	return
