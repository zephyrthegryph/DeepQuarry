// These things get applied to slimes to do things.

/obj/item/slimepotion
	name = "slime agent"
	desc = "A flask containing strange, mysterious substances excreted by a slime."
	icon = 'icons/obj/chemical.dmi'
	w_class = ITEMSIZE_TINY

// This is actually applied to an extract, so no attack() overriding needed.
/obj/item/slimepotion/enhancer
	name = "extract enhancer agent"
	desc = "A potent chemical mix that will give a slime extract an additional two uses."
	icon_state = "potcyan"
	description_info = "This will even work on inert slime extracts, if it wasn't enhanced before.  Extracts enhanced cannot be enhanced again."

// Makes slimes less likely to mutate.
/obj/item/slimepotion/stabilizer
	name = "slime stabilizer agent"
	desc = "A potent chemical mix that will reduce the chance of a slime mutating."
	icon_state = "potcyan"
	description_info = "The slime needs to be alive for this to work.  It will reduce the chances of mutation by 15%."

/obj/item/slimepotion/stabilizer/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.mutation_chance == 0)
		to_chat(user, span_warning("The slime already has no chance of mutating!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the stabilizer. It is now less likely to mutate."))
	xenobio_slime.mutation_chance = between(0, xenobio_slime.mutation_chance - 15, 100)
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS


// The opposite, makes the slime more likely to mutate.
/obj/item/slimepotion/mutator
	name = "slime mutator agent"
	desc = "A potent chemical mix that will increase the chance of a slime mutating."
	description_info = "The slime needs to be alive for this to work.  It will increase the chances of mutation by 12%."
	icon_state = "potred"

/obj/item/slimepotion/mutator/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.mutation_chance == 100)
		to_chat(user, span_warning("The slime is already guaranteed to mutate!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the mutator. It is now more likely to mutate."))
	xenobio_slime.mutation_chance = between(0, xenobio_slime.mutation_chance + 12, 100)
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS


// Makes the slime friendly forever.
/obj/item/slimepotion/docility
	name = "slime docility agent"
	desc = "A potent chemical mix that nullifies a slime's hunger, causing it to become docile and tame.  It might also work on other creatures?"
	icon_state = "potlightpink"
	description_info = "The target needs to be alive, not already passive, and be an animal or slime type entity."
	var/currently_using = FALSE						// To avoid same potion being usable multiple times

/obj/item/slimepotion/docility/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob))
		to_chat(user, span_warning("The agent only works on creatures!"))
		return ..()
	if(M.stat == DEAD)
		to_chat(user, span_warning("\The [M] is dead!"))
		return ..()
	if(!(M.ai_brain != null))
		to_chat(user, span_warning("\The [M] is too strongly willed for this to affect them.")) // Most likely player controlled.
		return
	if(currently_using)
		to_chat(user, span_warning("This agent has already been used!")) // Possibly trying to cheese the dialogue box and use same potion on multiple targets.
		return ITEM_INTERACT_FAILURE

	currently_using = TRUE
	var/datum/ai_brain/AI = M.ai_brain

	// Slimes.
	if(istype(M, /mob/living/simple_mob/slime/xenobio))
		var/mob/living/simple_mob/slime/xenobio/S = M
		if(S.harmless)
			to_chat(user, span_warning("The slime is already docile!"))
			currently_using = FALSE
			return ..()

		S.pacify()
		S.nutrition = 700
		to_chat(M, span_warning("You absorb the agent and feel your intense desire to feed melt away."))
		to_chat(user, span_notice("You feed the slime the agent, removing its hunger and calming it."))

	// Simple Mobs.
	else if(isanimal(M))
		var/mob/living/simple_mob/SM = M
		if(!(SM.mob_class & (MOB_CLASS_SLIME|MOB_CLASS_ANIMAL))) // So you can't use this on Russians/syndies/hivebots/etc.
			to_chat(user, span_warning("\The [src] only works on slimes and animals."))
			currently_using = FALSE
			return ..()
		if(!AI.hostile)
			to_chat(user, span_warning("\The [SM] is already passive!"))
			currently_using = FALSE
			return ..()

		//legacy .hostile reference removed (no equivalent on /datum/ai_brain).
		to_chat(M, span_warning("You consume the agent and feel a serene sense of peace."))
		to_chat(user, span_notice("You feed \the [SM] the agent, calming it."))

	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	AI.remove_target() // So hostile things stop attacking people even if not hostile anymore.
	var/newname = copytext(tgui_input_text(user, "Would you like to give \the [M] a name?", "Name your new pet", M.name, MAX_NAME_LEN),1,MAX_NAME_LEN)

	if(newname && !QDELETED(M))
		M.name = newname
		M.real_name = newname
	qdel(src)
	return ITEM_INTERACT_SUCCESS


// Makes slimes make more extracts.
/obj/item/slimepotion/steroid
	name = "slime steroid agent"
	desc = "A potent chemical mix that will increase the amount of extracts obtained from harvesting a slime."
	description_info = "The slime needs to be alive and not an adult for this to work.  It will increase the amount of extracts gained by one, up to a max of five per slime.  \
	Extra extracts are not passed down to offspring when reproducing."
	icon_state = "potpurple"

/obj/item/slimepotion/steroid/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.is_adult) //Can't steroidify adults
		to_chat(user, span_warning("Only baby slimes can use the steroid!"))
		return ..()
	if(xenobio_slime.cores >= 5)
		to_chat(user, span_warning("The slime already has the maximum amount of extract!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the steroid. It will now produce one more extract."))
	xenobio_slime.cores++
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS


// Makes slimes not try to murder other slime colors.
/obj/item/slimepotion/unity
	name = "slime unity agent"
	desc = "A potent chemical mix that makes the slime feel and be seen as all the colors at once, and as a result not be considered an enemy to any other color."
	description_info = "The slime needs to be alive for this to work.  Slimes unified will not attack or be attacked by other colored slimes, and this will \
	carry over to offspring when reproducing."
	icon_state = "potpink"

/obj/item/slimepotion/unity/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.unity == TRUE)
		to_chat(user, span_warning("The slime is already unified!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the agent. It will now be friendly to all other slimes."))
	to_chat(xenobio_slime, span_notice("\The [user] feeds you \the [src], and you suspect that all the other slimes will be \
	your friends, at least if you don't attack them first."))
	xenobio_slime.unify()
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

// Makes slimes not kill (most) humanoids but still fight spiders/carp/bears/etc.
/obj/item/slimepotion/loyalty
	name = "slime loyalty agent"
	desc = "A potent chemical mix that makes an animal deeply loyal to the species of whoever applies this, and will attack threats to them."
	description_info = "The slime or other animal needs to be alive for this to work.  The slime this is applied to will have their 'faction' change to \
	the user's faction, which means the slime will attack things that are hostile to the user's faction, such as carp, spiders, and other slimes."
	icon_state = "potlightpink"

/obj/item/slimepotion/loyalty/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob))
		to_chat(user, span_warning("The agent only works on creatures!"))
		return ..()

	if(!(M.mob_class & (MOB_CLASS_SLIME|MOB_CLASS_ANIMAL))) // So you can't use this on Russians/syndies/hivebots/etc.
		to_chat(user, span_warning("\The [M] only works on slimes and animals."))
		return ..()
	if(M.stat == DEAD)
		to_chat(user, span_warning("The animal is dead!"))
		return ..()
	if(M.faction == user.faction)
		to_chat(user, span_warning("\The [M] is already loyal to your species!"))
		return ..()
	if(!(M.ai_brain != null))
		to_chat(user, span_warning("\The [M] is too strong-willed for this to affect them."))
		return ..()

	var/datum/ai_brain/AI = M.ai_brain

	to_chat(user, span_notice("You feed \the [M] the agent. It will now try to murder things that want to murder you instead."))
	to_chat(M, span_notice("\The [user] feeds you \the [src], and feel that the others will regard you as an outsider now."))
	M.faction = user.faction
	AI.remove_target() // So hostile things stop attacking people even if not hostile anymore.
	if(istype(M, /mob/living/simple_mob/slime))
		var/mob/living/simple_mob/slime/slime = M
		slime.update_mood() //Makes them drop-nomable.
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS


// User befriends the slime with this.
/obj/item/slimepotion/friendship
	name = "slime friendship agent"
	desc = "A potent chemical mix that makes an animal deeply loyal to the the specific entity which feeds them this agent."
	description_info = "The slime or other animal needs to be alive for this to work.  The slime this is applied to will consider the user \
	their 'friend', and will never attack them.  This might also work on other things besides slimes."
	icon_state = "potlightpink"

/obj/item/slimepotion/friendship/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob))
		to_chat(user, span_warning("The agent only works on creatures!"))
		return ..()
	var/mob/living/simple_mob/SM = M

	if(!(SM.mob_class & (MOB_CLASS_SLIME|MOB_CLASS_ANIMAL))) // So you can't use this on Russians/syndies/hivebots/etc.
		to_chat(user, span_warning("\The [M] only works on slimes and animals."))
		return ..()
	if(SM.stat == DEAD)
		to_chat(user, span_warning("\The [M] is dead!"))
		return ..()
	if(user in SM.friends)
		to_chat(user, span_warning("\The [M] is already loyal to you!"))
		return ..()
	if(!(SM.ai_brain != null))
		to_chat(user, span_warning("\The [M] is too strong-willed for this to affect them."))
		return ..()

	var/datum/ai_brain/AI = SM.ai_brain

	to_chat(user, span_notice("You feed \the [SM] the agent. It will now be your best friend."))
	to_chat(SM, span_notice("\The [user] feeds you \the [src], and feel that \the [user] wants to be best friends with you."))
	SM.friends.Add(user)
	AI.remove_target() // So hostile things stop attacking people even if not hostile anymore.
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS


// Feeds the slime instantly.
/obj/item/slimepotion/feeding
	name = "slime feeding agent"
	desc = "A potent chemical mix that will instantly sediate the slime."
	description_info = "The slime needs to be alive for this to work.  It will instantly grow the slime enough to reproduce."
	icon_state = "potorange"

/obj/item/slimepotion/feeding/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the feeding agent. It will now instantly reproduce."))
	xenobio_slime.amount_grown = 10
	xenobio_slime.make_adult()
	xenobio_slime.amount_grown = 10
	xenobio_slime.reproduce()
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS


// === merged from slimepotions_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/slimepotion/attackby(obj/item/O, mob/user)
	if(istype(O, /obj/item/slimepotion/mimic))
		to_chat(user, span_notice("You apply the mimic to the slime potion as it copies it's effects."))
		playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
		var/newtype = src.type
		new newtype(get_turf(src))
		qdel(O)
	..()


/obj/item/slimepotion/infertility
	name = "slime infertility agent"
	desc = "A potent chemical mix that will reduce the amount of offspring this slime will have."
	icon_state = "potpurple"
	description_info = "The slime needs to be alive for this to work. It will reduce the amount of slime babies by 2 (to minimum of 2)."

/obj/item/slimepotion/infertility/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.split_amount <= 2)
		to_chat(user, span_warning("The slime cannot get any less fertile!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the infertility agent. It will now have less offspring."))
	xenobio_slime.split_amount = between(2, xenobio_slime.split_amount - 2, 6)
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/slimepotion/fertility
	name = "slime fertility agent"
	desc = "A potent chemical mix that will increase the amount of offspring this slime will have."
	icon_state = "potpurple"
	description_info = "The slime needs to be alive for this to work. It will increase the amount of slime babies by 2 (to maximum of 6)."

/obj/item/slimepotion/fertility/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(xenobio_slime.split_amount >= 6)
		to_chat(user, span_warning("The slime cannot get any more fertile!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the fertility agent. It will now have more offspring."))
	xenobio_slime.split_amount = between(2, xenobio_slime.split_amount + 2, 6)
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/slimepotion/shrink
	name = "slime shrinking agent"
	desc = "A potent chemical mix that will turn adult slime into a baby one."
	icon_state = "potpurple"
	description_info = "The slime needs to be alive for this to work."

/obj/item/slimepotion/shrink/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()
	if(!(xenobio_slime.is_adult))
		to_chat(user, span_warning("The slime is already a baby!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the shrinking agent. It is now back to being a baby."))
	xenobio_slime.make_baby()
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/slimepotion/death
	name = "slime death agent"
	desc = "A potent chemical mix that will instantly kill a slime."
	icon_state = "potblue"
	description_info = "The slime needs to be alive for this to work."

/obj/item/slimepotion/death/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is already dead!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the death agent. Its face flashes pain of betrayal before it goes still."))
	xenobio_slime.adjustToxLoss(500)
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/slimepotion/ferality
	name = "slime ferality agent"
	desc = "A potent chemical mix that will make a slime untamable."
	icon_state = "potred"
	description_info = "The slime needs to be alive for this to work."

/obj/item/slimepotion/ferality/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is already dead!"))
		return ..()
	if(xenobio_slime.untamable && xenobio_slime.untamable_inheirit)
		to_chat(user, span_warning("The slime is already untamable!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the death agent. It will now only get angrier at taming attempts."))
	xenobio_slime.untamable = TRUE
	xenobio_slime.untamable_inheirit = TRUE
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/slimepotion/reinvigoration
	name = "extract reinvigoration agent"
	desc = "A potent chemical mix that will create a slime of appropriate type out of an extract."
	icon_state = "potcyan"
	description_info = "This will even work on inert extracts. Extract is destroyed in process."

/obj/item/slimepotion/mimic
	name = "mimic agent"
	desc = "A potent chemical mix that will mimic effects of other slime-produced agents."
	icon_state = "potsilver"
	description_info = "Warning: avoid combining multiple doses of mimic agent."

/obj/item/slimepotion/mimic/attackby(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(istype(M, /obj/item/slimepotion/mimic))
		to_chat(user, span_warning("You apply the mimic to the mimic, resulting a mimic that copies a mimic that copies a mimic that copies a mimic that-"))
		var/location = get_turf(src)
		playsound(location, 'sound/weapons/gauss_shoot.ogg', 50, 1)
		var/datum/effect/effect/system/grav_pull/s = new /datum/effect/effect/system/grav_pull
		s.set_up(3, 3, location)
		s.start()
		qdel(M)
		qdel(src)
		return ITEM_INTERACT_SUCCESS
	..()

/obj/item/slimepotion/sapience
	name = "slime sapience agent"
	desc = "A potent chemical mix that makes an animal capable of developing more advanced, sapient thought."
	description_info = "The slime or other animal needs to be alive for this to work. The development is not always immedeate and may take indeterminate time before effects show."
	icon_state = "potblue"

/obj/item/slimepotion/sapience/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The creature is dead!"))
		return ..()
	if(xenobio_slime.ghostjoin)
		to_chat(user, span_warning("The creature is already developing sapience."))
		return ..()
	if(xenobio_slime.ckey)
		to_chat(user, span_warning("The creature is already sapient!"))
		return ..()

	to_chat(user, span_notice("You feed \the [xenobio_slime] the agent. It may now eventually develop proper sapience."))
	xenobio_slime.ghostjoin = 1
	GLOB.active_ghost_pods |= xenobio_slime
	if(!xenobio_slime.vore_active)
		add_verb(xenobio_slime, /mob/living/simple_mob/proc/animal_nom)
	xenobio_slime.ghostjoin_icon()
	log_and_message_admins("used a sapience potion on a simple mob: [xenobio_slime]. [ADMIN_FLW(src)]", user)
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/slimepotion/obedience
	name = "slime obedience agent"
	desc = "A potent chemical mix that makes slime extremely obedient."
	icon_state = "potlightpink"
	description_info = "The target needs to be alive and currently misbehaving. Effect is equivalent to very strong discipline."

/obj/item/slimepotion/obedience/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob/slime/xenobio))
		to_chat(user, span_warning("The stabilizer only works on slimes!"))
		return ..()
	var/mob/living/simple_mob/slime/xenobio/xenobio_slime = M

	if(xenobio_slime.stat == DEAD)
		to_chat(user, span_warning("The slime is dead!"))
		return ..()

	to_chat(user, span_notice("You feed the slime the agent. It has been disciplined, for better or worse..."))
	var/justified = xenobio_slime.is_justified_to_discipline()
	xenobio_slime.adjust_discipline(10)
	if(xenobio_slime.slime_state && justified)
		xenobio_slime.slime_state.obedience = 10
	playsound(src, 'sound/effects/bubbles.ogg', 50, 1)
	qdel(src)
	return ITEM_INTERACT_SUCCESS
