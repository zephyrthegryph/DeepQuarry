/datum/modifier/eletricalsurge //grub
	name = "Eletrical Surge"
	desc = "You are filled with an overwhelming energy."

	on_created_text = span_critical("You feel an overwhelimg energy surge through your body!")
	on_expired_text = span_notice("The surge subsides.")
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(BF_EVASION = 20, BF_ATTACK_SPEED = 0.75, BF_SIEMENS = 3)

/datum/modifier/healingtide //carp
	name = "Healing Tide"
	desc = "Your body is more receptive to chemicals."

	on_created_text = span_critical("Your body is more receptive to chemicals!")
	on_expired_text = span_notice("The healing subsides.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_METABOLISM = 0.5, BF_HEALING_RECEIVED = 1.25)

/datum/modifier/radiationhide //deathclaw
	name = "Radiation Hide"
	desc = "Your body is adorn with scales."

	on_created_text = span_critical("Your body strangly mutates!")
	on_expired_text = span_notice("Your body returns to normal.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_INCOMING_ALL = 0.9, BF_INCOMING_GENETIC = 0, BF_HEALING_RECEIVED = 0.5, BF_ENDURANCE_MULT = 1.5, BF_ICON_SCALE_X = 1.2, BF_ICON_SCALE_Y = 1.2)

/datum/modifier/nervoushigh //meteroid
	name = "Nervous High"
	desc = "Your senses feel everything."

	client_color = "#808080" //Za worldo

	on_created_text = span_critical("The world arounds you slows down!")
	on_expired_text = span_notice("The world returns to normal.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_METABOLISM = 3.0, BF_BLEEDING = 3.0, BF_SLOWDOWN = -3, BF_ATTACK_SPEED = 0.25, BF_DISABLE_DURATION = 0.1, BF_ENDURANCE_MULT = 0.25)

/datum/modifier/protectivenumbing //spider
	name = "Protective Numbing"
	desc = "Your senses dull."

	on_created_text = span_critical("Your body becomes numb!")
	on_expired_text = span_notice("Sensation returns to your body.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_ATTACK_SPEED = 1.25, BF_HEAT_EXPOSURE = 0, BF_COLD_EXPOSURE = 0)

/datum/modifier/juggernog
	name = "Juggernog"
	desc = "Your body is prepared for conflict."

	on_created_text = span_critical("Your body becomes tougher!")
	on_expired_text = span_notice("Your body returns to normal.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_DISABLE_DURATION = 0.2, BF_ENDURANCE_MULT = 1.3)

/datum/modifier/life_cloak
	name = "Life Cloak"
	desc = "Your body is protected from death."

	on_created_text = span_critical("You feel protected!")
	on_expired_text = span_notice("Your body returns to normal.")
	stacks = MODIFIER_STACK_EXTEND

/datum/modifier/life_cloak/can_apply(mob/living/L, suppress_failure = FALSE)
	if(L.has_modifier_of_type(/datum/modifier/life_cloak_exhaustion))
		return FALSE
	return ..()

/datum/modifier/life_cloak/tick()
	if(holder.stat != DEAD)
		holder.add_modifier(/datum/modifier/life_cloak_exhaustion, 360 SECONDS)
		// A revival burst from a power, not a reagent: mend by mechanism,
		// organic and synthetic alike.
		holder.mend(TREAT_TISSUE_REPAIR, 150)
		holder.mend(TREAT_PLATING_REPAIR, 150)
		holder.mend(TREAT_BURN_CARE, 150)
		holder.mend(TREAT_WIRING_REPAIR, 150)
		holder.mend(TREAT_OXYGENATION, 200)
		GLOB.dead_mob_list.Remove(holder)
		if((holder in GLOB.living_mob_list) || (holder in GLOB.dead_mob_list))
			WARNING("Mob [holder] was defibbed but already in the living or dead list still!")
		GLOB.living_mob_list += holder
		holder.timeofdeath = 0
		holder.set_stat(CONSCIOUS)
		holder.failed_last_breath = 0
		holder.reload_fullscreen()
		expire()

/datum/modifier/life_cloak_exhaustion
	name = "Life Cloak Recovery"
	desc = "Your body is recovering."

	on_created_text = span_critical("Something feels wrong!")
	on_expired_text = span_notice("Your body returns to normal.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_INCOMING_ALL = 1.5, BF_DISABLE_DURATION = 2)
