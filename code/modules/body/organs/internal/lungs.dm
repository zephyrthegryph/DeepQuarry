/obj/item/organ/internal/lungs
	name = "lungs"
	icon_state = "lungs"
	gender = PLURAL
	organ_tag = O_LUNGS
	parent_organ = BP_TORSO

/obj/item/organ/internal/lungs/organ_tick(cycles)
	..()

	if(!owner)
		return

	if(is_broken())
		if(prob(4))
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "coughs up a large amount of blood!", check_stat = TRUE)
			var/bleeding_rng = rand(3,5)
			owner.drip(bleeding_rng)
		if(prob(8)) //This is a medical emergency. Will kill within minutes unless exceedingly lucky.
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "gasps for air!", check_stat = TRUE)
			owner.AdjustLosebreath(15)

	else if(is_bruised()) //Only bruised? That's an annoyance and can cause some more damage (via brain damage from hypoxia)
		if(prob(2)) //But let's not kill people too quickly.
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "coughs up a small amount of blood!", check_stat = TRUE)
			var/bleeding_rng = rand(1,2)
			owner.drip(bleeding_rng)
		if(prob(4)) //Get to medical quickly. but shouldn't kill without exceedingly bad RNG.
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "gasps for air!", check_stat = TRUE)
			owner.AdjustLosebreath(10) //Losebreath is a DoT that does 1:1 damage and prevents hypoxia recovery via breathing.

	if(owner.organ_in(O_BRAIN)) // As the brain starts having Trouble, the lungs start malfunctioning.
		var/obj/item/organ/internal/Brain = owner.organ_in(O_BRAIN) // any brain-slot occupant
		if(Brain.get_control_efficiency() <= 0.8)
			if(prob(4 / max(0.1,Brain.get_control_efficiency())))
				owner.automatic_custom_emote(VISIBLE_MESSAGE, "gasps for air!", check_stat = TRUE)
				owner.AdjustLosebreath(round(3 / max(0.1,Brain.get_control_efficiency())))

/obj/item/organ/internal/lungs/proc/rupture()
	if(owner && damage < min_bruised_damage) //Anti spam prevention.
		var/obj/item/organ/external/parent = owner.get_organ(parent_organ)
		if(istype(parent))
			owner.custom_pain("You feel a stabbing pain in your [parent.name]!", 50)
	damage_to_at_least(min_bruised_damage, /datum/affliction/lesion/perforation) // a ruptured lung is a perforated one

/obj/item/organ/internal/lungs/handle_germ_effects(cycles)
	. = ..() //Up should return an infection level as an integer
	if(!. || !owner) return

	//Bacterial pneumonia
	if (. >= 1)
		if(prob(5))
			owner.emote("cough")
	if (. >= 2)
		if(prob(1))
			owner.custom_pain("You suddenly feel short of breath and take a sharp, painful breath!",1)
			// Pus-filled alveoli: gas exchange fails for a while.
			owner.body?.add_restriction(src, BF_GAS_EXCHANGE, 0.3, 30 SECONDS)

/obj/item/organ/internal/lungs/grey
	icon_state = "lungs_grey"


CAPABILITIES(/obj/item/organ/internal/lungs/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/lungs/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color


// === merged from lungs_ch.dm during hard-fork de-suffix (verified no override-order change) ===
//TFF backport 31/12/19 - Erik's Lungs return to haunt us all!
/obj/item/organ/internal/lungs/erikLungs
	name = "Erik's lungs"
	desc = "These lungs supposedly belonged to someone named 'Erik', he loses them so often they've been displayed here for whenever they might be needed."

// When this organ's organ_tick() has nothing to do: the organ clock may park (/obj/item/organ/proc/life_step_idle()).
/obj/item/organ/internal/lungs/life_step_idle()
	if(!..())
		return FALSE
	if(!owner)
		return TRUE
	if(is_bruised())
		return FALSE
	var/obj/item/organ/internal/B = owner.organ_in(O_BRAIN)
	return !B || B.get_control_efficiency() > 0.8
