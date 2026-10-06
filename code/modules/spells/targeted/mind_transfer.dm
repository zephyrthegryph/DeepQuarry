/datum/spell/targeted/mind_transfer
	name = "Mind Transfer"
	desc = "This spell allows the user to switch bodies with a target."

	school = "transmutation"
	charge_max = 600
	spell_flags = 0
	invocation = "GIN'YU CAPAN"
	invocation_type = SpI_WHISPER
	max_targets = 1
	range = 1
	cooldown_min = 200 //100 deciseconds reduction per rank
	compatible_mobs = list(/mob/living/carbon/human) //which types of mobs are affected by the spell. NOTE: change at your own risk

	// TODO: Update to new antagonist system.
	var/static/list/protected_roles = list(JOB_WIZARD,JOB_CHANGELING,JOB_CULTIST) //which roles are immune to the spell
	var/msg_wait = 500 //how long in deciseconds it waits before telling that body doesn't feel right or mind swap robbed of a spell
	amt_paralysis = 20 //how much the victim is paralysed for after the spell

	hud_state = "wiz_mindswap"

/datum/spell/targeted/mind_transfer/cast(list/targets, mob/user)
	..()

	for(var/mob/living/target in targets)
		if(target.stat == DEAD)
			to_chat(user, "You didn't study necromancy back at the Space Wizard Federation academy.")
			continue

		if(!target.key || !target.mind)
			to_chat(user, "They appear to be catatonic. Not even magic can affect their vacant mind.")
			continue

		if(target.mind.special_role in protected_roles)
			to_chat(user, "Their mind is resisting your spell.")
			continue

		var/mob/living/victim = target//The target of the spell whos body will be transferred to.
		var/mob/caster = user//The wizard/whomever doing the body transferring.

		//MIND TRANSFER BEGIN
		if(length(caster.mind.special_verbs)) //If the caster had any special verbs, remove them from the mob verb list.
			for(var/granted_path in caster.mind.special_verbs)
				revoke(caster, granted_verb(granted_path), caster.mind)//Mostly moot with the object spell system, but a safety nontheless.

		if(length(victim.mind.special_verbs)) //Now remove all of the victim's verbs.
			for(var/granted_path in victim.mind.special_verbs)
				revoke(victim, granted_verb(granted_path), victim.mind)

		var/mob/observer/dead/ghost = victim.ghostize(0)
		rel_add(ghost, nameof(ghost.spell_list), victim.spell_list) //If they have spells, transfer them. Now we basically have a backup mob.

		move_player(caster, victim, "mind transfer spell")
		for(var/datum/spell/S in victim.spell_list) //get rid of spells the new way
			victim.remove_spell(S) //This will make it so that players will not get the HUD and all that spell bugginess that caused copies of spells and stuff of that nature.

		for(var/datum/spell/S in caster.spell_list)
			victim.add_spell(S) //Now they are inside the victim's body - this also generates the HUD
			caster.remove_spell(S) //remove the spells from the caster

		if(length(victim.mind.special_verbs)) //To add all the special verbs for the original caster.
			for(var/granted_path in caster.mind.special_verbs)
				grant(caster, granted_verb(granted_path), caster.mind)//Not too important but could come into play.

		transfer_mind(ghost.mind, caster, "mind transfer spell", force = TRUE) // the ghost holds the key: force it along
		for(var/datum/spell/S in ghost.spell_list)
			caster.add_spell(S)
		rel_set(ghost, nameof(ghost.spell_list), list())

		if(length(caster.mind.special_verbs)) //If they had any special verbs, we add them here.
			for(var/granted_path in caster.mind.special_verbs)
				grant(caster, granted_verb(granted_path), caster.mind)
		//MIND TRANSFER END

		//Target is handled in ..(), so we handle the caster here
		caster.status_at_least(STAT_PARALYZED, amt_paralysis)
		caster.status_at_least(STAT_SLEEPING, amt_paralysis)

		//After a certain amount of time the victim gets a message about being in a different body.
		after(caster, msg_wait, TYPE_PROC_REF(/datum, om_chat), with = list(span_danger("You feel woozy and lightheaded. Your body doesn't seem like your own.")))
