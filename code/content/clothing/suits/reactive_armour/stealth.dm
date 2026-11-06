/obj/item/clothing/suit/armor/reactive/stealth
	name = "reactive stealth armor"
	desc = "An experimental suit of armor that renders the wearer invisible on detection of imminent harm, and creates a decoy that runs away from the owner. You can't fight what you can't see."
	cooldown_message = span_danger("The reactive stealth system activates, but is not charged enough to fully cloak!")
	emp_message = span_warning("The reactive stealth armor's threat assessment system crashes...")
	///when triggering while on cooldown will only flicker the alpha slightly. this is how much it removes.
	var/cooldown_alpha_removal = 50
	///cooldown alpha flicker- how long it takes to return to the original alpha
	var/cooldown_animation_time = 3 SECONDS
	///how long they will be fully stealthed
	var/stealth_time = 4 SECONDS
	///how long it will animate back the alpha to the original
	var/animation_time = 2 SECONDS
	var/in_stealth = FALSE

/obj/item/clothing/suit/armor/reactive/stealth/cooldown_activation(mob/living/carbon/human/owner)
	if(in_stealth)
		return
	owner.set_alpha(max(0, owner.alpha - cooldown_alpha_removal))
	animate(owner, alpha = initial(owner.alpha), time = cooldown_animation_time)
	..()

/obj/item/clothing/suit/armor/reactive/stealth/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text, final_block_chance, damage)
	var/mob/living/simple_mob/illusion/decoy = new(owner.loc)
	decoy.copy_appearance(owner)
	decoy.copy_overlays(owner, TRUE)
	var/turf/rand_turf = pick(get_turf(orange(5, 10)))
	decoy.ai_brain?.give_destination(rand_turf)
	owner.set_alpha(0)
	in_stealth = TRUE
	act_message(owner, null, others = span_danger("%U% is hit by [attack_text] in the chest!"))
	after(src, stealth_time, PROC_REF(end_stealth), with = list(owner), keeps_dead = TRUE)
	decoy.say("*sidestep")
	after(src, stealth_time, PROC_REF(destroy_illusion), with = list(decoy))
	decoy.expire(stealth_time)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/stealth/proc/end_stealth(mob/living/carbon/human/owner)
	in_stealth = FALSE
	if(owner)
		animate(owner, alpha = initial(owner.alpha), time = animation_time)

/obj/item/clothing/suit/armor/reactive/stealth/proc/destroy_illusion(mob/illusion)
	if(QDELETED(illusion))
		return
	fx_sparks(illusion, 3, 3)
	illusion.expire(animation_time)

/obj/item/clothing/suit/armor/reactive/stealth/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	if(!isliving(hitby))
		return FALSE
	var/mob/living/attacker = hitby
	owner.visible_message(span_danger("[src] activates, cloaking the wrong person!"))
	attacker.set_alpha(0)
	after(attacker, 4 SECONDS, GLOBAL_PROC_REF(reactive_cloak_wear_off), with = list(attacker, initial(attacker.alpha)))
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE
