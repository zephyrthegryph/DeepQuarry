/datum/component/xenoqueenbuff
	var/mob/living/carbon/human/xeno
	var/aura_active = 0
	var/datum/modifier/aura/applying = /datum/modifier/aura/xenoqueenbuff // In case we want to add more than one buff in the future.

/datum/component/xenoqueenbuff/Initialize()
	if(!ishuman(parent))
		return COMPONENT_INCOMPATIBLE
	xeno = parent //asigning the reference
	add_verb(xeno,/mob/living/carbon/human/proc/queen_aura_toggle) // TGPanel

/datum/component/xenoqueenbuff/process()
	if(QDELETED(xeno))
		REACT_PROCESS_STOP(src)
		aura_active = 0  //Turn off the aura if our host gets deleted
		return
	if(xeno.stat == DEAD)
		REACT_PROCESS_STOP(src)
		aura_active = 0  //Turn off the aura when we die.
		return

	for(var/mob/living/L in range(7, xeno))
		if(L == xeno)
			continue //Don't buff ourselves
		if(xeno.IIsAlly(L))
			L.add_modifier(applying, null, parent)

/datum/modifier/aura/xenoqueenbuff
	name = "Adrenal Surge"
	on_created_text = span_notice("The influence of a nearby Xenomorph Queen strengthens your body... ")
	on_expired_text = span_warning("You feel the influence of the Queen slip away, causing your body to relax.")
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 7 // Viewrange.
	mob_overlay_state = "purple_electricity_constant"

	// Only affects melee weapons, not fists
	// Increases attack speed by 10%
	// Only affects ranged attacks missing
	factors = alist(BF_EVASION = 25, BF_ATTACK_SPEED = 0.9, BF_MELEE_DAMAGE = 1.2)

/datum/modifier/aura/xenoqueenbuff/check_if_valid()
	.=..()
	var/atom/A = origin.resolve()
	if(istype(A))
		var/datum/component/xenoqueenbuff/X = A.GetComponent(/datum/component/xenoqueenbuff)
		if(X)
			if(!X.aura_active)
				expire()

/mob/living/carbon/human/proc/queen_aura_toggle()
	set name = "Commanding Aura"
	set category = "Abilities.Xeno"
	set desc = "Toggles your Xenomorph Queen buff aura."

	if(stat == DEAD) //Disable the verb while we're dead
		return

	var/datum/component/xenoqueenbuff/X = GetComponent(/datum/component/xenoqueenbuff)
	if(X)
		if(X.aura_active)
			REACT_PROCESS_STOP(X)
			X.aura_active = 0
			to_chat (src, span_notice("You cease empowering those around you."))
		else
			REACT_PROCESS(X, 1 SECOND, "buffs nearby allies every tick while the queen aura is active")
			X.aura_active = 1
			to_chat (src, span_notice("You begin empowering those around you."))
