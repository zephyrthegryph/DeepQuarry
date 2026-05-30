// Wizard spellbook — structured TGUI panel that replaces the legacy attack_self HTML.

/obj/item/spellbook/proc/dq_open_spellbook(mob/user)
	user.set_machine(src)
	tgui_interact(user)

/obj/item/spellbook/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/item/spellbook/tgui_interact(mob/user, datum/tgui/ui)
	if(special_handling)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Spellbook", "The Book of Spells")
		ui.open()

/obj/item/spellbook/proc/get_spellbook_catalog()
	var/static/list/catalog
	if(catalog)
		return catalog
	catalog = list(
		"spells" = list(
			list("id" = "magicmissile", "name" = "Magic Missile", "cooldown" = 10, "desc" = "Fires several slow magic projectiles at nearby targets. Hits paralyze the target and deal minor damage."),
			list("id" = "fireball", "name" = "Fireball", "cooldown" = 10, "desc" = "Fires a fireball in the direction you're facing; does not require wizard garb. Beware close-range casting."),
			list("id" = "disabletech", "name" = "Disable Technology", "cooldown" = 60, "desc" = "Disables all weapons, cameras and most other technology in range."),
			list("id" = "smoke", "name" = "Smoke", "cooldown" = 10, "desc" = "Spawns a cloud of choking smoke at your location; does not require wizard garb."),
			list("id" = "blind", "name" = "Blind", "cooldown" = 30, "desc" = "Temporarily blinds a single person; does not require wizard garb."),
			list("id" = "subjugation", "name" = "Subjugation", "cooldown" = 30, "desc" = "Temporarily subjugates a target's mind; does not require wizard garb."),
			list("id" = "forcewall", "name" = "Forcewall", "cooldown" = 10, "desc" = "Creates an unbreakable wall that lasts 30 seconds; does not require wizard garb."),
			list("id" = "blink", "name" = "Blink", "cooldown" = 2, "desc" = "Randomly teleports you a short distance. Useful for evasion or sneaking with patience."),
			list("id" = "teleport", "name" = "Teleport", "cooldown" = 60, "desc" = "Teleports you to an area of your selection. Useful when in danger, but unpredictable."),
			list("id" = "mutate", "name" = "Mutate", "cooldown" = 60, "desc" = "Briefly transforms you into a hulk and grants telekinesis."),
			list("id" = "etherealjaunt", "name" = "Ethereal Jaunt", "cooldown" = 60, "desc" = "Creates your ethereal form, temporarily making you invisible and able to pass through walls."),
			list("id" = "knock", "name" = "Knock", "cooldown" = 10, "desc" = "Opens nearby doors; does not require wizard garb."),
		),
		"artefacts" = list(
			list("id" = "mentalfocus", "name" = "Mental Focus", "desc" = "An artefact that channels the user's will into destructive bolts of force."),
			list("id" = "soulstone", "name" = "Six Soul Stone Shards and the spell Artificer", "desc" = "Soul Stone Shards capture the spirits of the dead and dying. Artificer lets the captured souls pilot arcane machines."),
			list("id" = "armor", "name" = "Mastercrafted Armor Set", "desc" = "Armor that allows you to cast spells while granting more protection against attacks and the void of space."),
			list("id" = "staffanimation", "name" = "Staff of Animation", "desc" = "An arcane staff that fires bolts of eldritch energy which animate inanimate objects. Doesn't affect machines."),
			list("id" = "scrying", "name" = "Scrying Orb", "desc" = "Lets you ghost while alive to spy upon the station. Also permanently grants x-ray vision."),
		),
		"noclothes" = list(
			"id" = "noclothes",
			"name" = "Remove Clothes Requirement",
			"desc" = "Lets you cast your spells without wizard garb. Costs two spell choices.",
		),
	)
	return catalog

/obj/item/spellbook/tgui_data(mob/user)
	var/list/catalog = get_spellbook_catalog()
	var/list/data = list()
	data["temp"] = temp || ""
	data["uses"] = uses
	data["max_uses"] = max_uses
	data["can_rememorize"] = !!op
	data["spells"] = catalog["spells"]
	data["artefacts"] = catalog["artefacts"]
	data["noclothes"] = catalog["noclothes"]
	return data

/obj/item/spellbook/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("clear_temp")
			temp = null
			SStgui.update_uis(src)
			return TRUE
		if("choose")
			var/spell_id = params["id"]
			if(!spell_id)
				return TRUE
			Topic("spell_choice=[spell_id]", list("spell_choice" = "[spell_id]"))
			SStgui.update_uis(src)
			return TRUE

// DQEdit Start — spellbook now opens via TGUI panel rather than admin_log_show.
/obj/item/spellbook/attack_self(mob/user = usr)
	. = ..(user)
	if(.)
		return TRUE
	if(special_handling)
		return FALSE
	if(!user)
		return
	if((user.mind && !GLOB.wizards.is_antagonist(user.mind)))
		to_chat(user, span_warning("You stare at the book but cannot make sense of the markings!"))
		return
	dq_open_spellbook(user)
// DQEdit End
