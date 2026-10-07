CAPABILITIES(/obj/item/spellbook)
	op("clear_temp", ui_act(), then(PROC_REF(ui_act_clear_temp)))
	interface("Spellbook", title = "The Book of Spells", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	op("choose", ui_act("choose", arg("id", schema_text(4096))), then(PROC_REF(ui_act_choose)))
	op("read_spellbook", in_hand(), label("Read"), needs(req(PROC_REF(can_read_markings_holds), because = PROC_REF(can_read_markings_refusal))), then(PROC_REF(interaction_read_spellbook)))

// Wizard spellbook — structured TGUI panel that replaces the legacy attack_self HTML.

/obj/item/spellbook/proc/dq_open_spellbook(mob/user)
	user.set_machine(src)
	tgui_interact(user)

/obj/item/spellbook/ui_prepare(mob/user, datum/tgui/ui)
	if(special_handling)
		return FALSE
	return TRUE

/proc/build_spellbook_catalog()
	var/list/catalog = list(
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

GLOBAL_TABLE(spellbook_catalog, GLOBAL_PROC_REF(build_spellbook_catalog))

/// /obj/item/spellbook's window data.
/obj/item/spellbook/ui_data(datum/act/eval/A)
	var/list/catalog = GLOBAL_TABLE_GET(spellbook_catalog)
	var/list/data = list()
	data["temp"] = temp || ""
	data["uses"] = uses
	data["max_uses"] = max_uses
	data["can_rememorize"] = !!op
	data["spells"] = catalog["spells"]
	data["artefacts"] = catalog["artefacts"]
	data["noclothes"] = catalog["noclothes"]
	return data

/obj/item/spellbook/proc/ui_act_clear_temp(datum/act/op/A)
	temp = null
	SStgui.update_uis(src)
	return OP_OK

/obj/item/spellbook/proc/ui_act_choose(datum/act/op/A, id)
	if(!id)
		return TRUE
	choose_spell(A.actor, "[id]")
	SStgui.update_uis(src)
	return TRUE

// spellbook now opens via TGUI panel rather than admin_log_show.

/// Requirement: only wizards (or the mindless) make sense of the markings; special books handle this themselves.
/obj/item/spellbook/proc/can_read_markings(mob/user, atom/target, obj/item/held)
	if(special_handling)
		return TRUE
	return dq_actor_is_wizard_or_mindless(user) ? TRUE : "you stare at the book but cannot make sense of the markings"

/// Requirement: the actor is a wizard, or has no mind to judge (the old `user.mind && !is_antagonist` gate).
/proc/dq_actor_is_wizard_or_mindless(mob/actor, atom/target, obj/item/held)
	READS_FROM(actor)
	return !actor?.mind || GLOB.wizards.is_antagonist(actor.mind) ? TRUE : FALSE

/// Old attack_self: the spellbook panel opens via TGUI. Specially handled books leave it to their own self-use.
/// Requirement (was REQ_* can_read_markings): the legacy check answers TRUE to pass.
/obj/item/spellbook/proc/can_read_markings_holds(datum/act/op/A)
	var/answer = can_read_markings(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_read_markings_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/spellbook/proc/can_read_markings_refusal(datum/act/op/A)
	var/answer = can_read_markings(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/item/spellbook/proc/interaction_read_spellbook(datum/act/op/A)
	var/mob/user = A.actor
	if(special_handling)
		return OP_DECLINE
	if(!user)
		return TRUE
	dq_open_spellbook(user)
	return TRUE
