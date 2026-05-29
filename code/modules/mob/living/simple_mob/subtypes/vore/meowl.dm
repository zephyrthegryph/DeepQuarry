/mob/living/simple_mob/vore/meowl
	name = "Meowl"
	desc = "A rather cute looking creature that seems to have the features of both a cat and an owl."
	catalogue_data = list(/datum/category_item/catalogue/fauna/meowl)
	tt_desc = "Strigiline"
	icon = 'icons/mob/vore.dmi'
	icon_dead = "meowl-dead"
	icon_living = "meowl"
	icon_state = "meowl"
	icon_rest = "meowl_rest"
	faction = FACTION_MEOWL
	friendly = list("nudges", "sniffs on", "rumbles softly at", "nuzzles")
	response_help = "pets"
	response_disarm = "shoves"
	response_harm = "attacks"
	movement_cooldown = 2
	harm_intent_damage = 1
	melee_damage_lower = 1
	melee_damage_upper = 2
	maxHealth = 100
	attacktext = list("scratches")
	see_in_dark = 8
	minbodytemp = 0
	var/well_fed = 0

	vore_bump_chance = 0
	vore_digest_chance = 50
	vore_escape_chance = 5
	vore_pounce_chance = 1000
	vore_active = 1
	vore_icons = 1
	vore_icons = SA_ICON_LIVING | SA_ICON_REST
	vore_capacity = 1
	swallowTime = 50
	vore_ignores_undigestable = FALSE
	vore_default_mode = DM_HOLD
	vore_pounce_maxhealth = 1000
	vore_bump_emote = "pounces on"

/mob/living/simple_mob/vore/meowl/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The strange critter suddenly takes advantage of you being alone to pounce atop you and quickly engulf your head within its maw! Before you even have a chance to react, the world goes dark with the inside of the meowls mouth covering your face, a rough tounge lapping smearing wet hot slobber over you. The rest of the process is pretty quick as the cat-owl begins to gulp your head down through a surprisingly stretchy throat and along the tight, flexing tunnel of its gullet. Before long you are pushing face first into the creature's stomach, the wrinkled walls quickly beginning grind slick flesh across it like any other piece of food. The rest of your body soon follows into the increasingly tight space, forced to curl up over yourself as the stomach lining bears down on you from every angle. At first, the stomach itself seems rather inactive, happily just squeezing and massaging you as the meowl settles down to slowly enjoy their snack. Though, struggling might risk setting off the gut one way or another..."
	B.mode_flags = DM_FLAG_THICKBELLY
	B.belly_fullscreen = "VBO_fleshs"
	B.digest_brute = 1
	B.digest_burn = 1
	B.digest_oxy = 1
	B.selectchance = 25
	B.digestchance = 0
	B.absorbchance = 0
	B.escapechance = 10
	B.selective_preference = DM_DIGEST
	B.escape_stun = 5
	B.transferlocation_absorb = "chub"

	var/obj/belly/chub = new /obj/belly(src)
	chub.immutable = TRUE
	chub.name = "chub"
	chub.desc = "Your body quickly begins to feel very... different? In fact, you can't really feel your body much at all any more, but you certainly still feel something. The pressure of the gut that was practically crushing you before is relieved, but somehow still present as though you were now on the other side of the interaction. Your being feels much more spread out and practically intertwined with the world around, that world being the meowl itself. The strange cat-owl's purring feels like it's reverberating throughout your entire form, whatever that might be. Every time the critter shakes to ruffle its feathers, you feel yourself shake with it. Even the creatures emotions feel tangible to you, as though you share themselves, and mostly they are ones of fullness and content."
	chub.digest_mode = DM_HOLD // like, its got you already, doesn't need to get you more
	chub.mode_flags = DM_FLAG_FORCEPSAY
	chub.escapable = B_ESCAPABLE_DEFAULT // good luck
	chub.escapechance = 40 // high chance of STARTING a successful escape attempt
	chub.escapechance_absorbed = 5 // m i n e
	chub.vore_verb = "soak"
	chub.count_absorbed_prey_for_sprite = FALSE
	chub.absorbed_struggle_messages_inside = list(
		"You try and push free from %pred's %belly, but can't seem to will yourself to move.",
		"Your fruitless mental struggles only cause %pred to purr happily.",
		"You can't make any progress freeing yourself from %pred's %belly.")
	chub.escape_attempt_absorbed_messages_owner = list(
		"%prey is attempting to free themselves from your %belly!")

	chub.escape_attempt_absorbed_messages_prey = list(
		"You try to force yourself out of %pred's %belly.",
		"You strain and push, attempting to reach out of %pred's %belly.",
		"You work up the will to try and force yourself free of %pred's clutches.")

	chub.escape_absorbed_messages_owner = list(
		"%prey forces themselves free of your %belly!")

	chub.escape_absorbed_messages_prey = list(
		"You finally manage to wrest yourself free from %pred's %belly, re-asserting your more usual form.",
		"You heave and push, eventually spilling out from %pred's %belly, eliciting a mildly annoyed flurry of wing flapping.")

	chub.escape_absorbed_messages_outside = list(
		"%prey suddenly forces themselves free of %pred's %belly!")

	chub.escape_fail_absorbed_messages_owner = list(
		"%prey's attempt to escape form your %belly has failed!")

	chub.escape_fail_absorbed_messages_prey = list(
		"Before you manage to reach freedom, you feel yourself getting dragged back into %pred's %belly!",
		"%pred cheeps playfully, simply pressing your wrigging form back into their %belly before you get anywhere.",
		"%pred holds a wing down on their %belly, the gentle pressure breaking your concentration and sending you sinking back into its form.",
		"Try as you might, you barely make an impression before %pred simply clenches with the most minimal effort, binding you back into their %belly.",
		"Unfortunately, %pred seems to have absolutely no intention of letting you go, and your futile effort goes nowhere.",
		"Strain as you might, you can't keep up the effort long enough before you sink back into %pred's %belly.")

/mob/living/simple_mob/vore/meowl/attackby(obj/item/O as obj, mob/user as mob)
	if(istype(O, /obj/item/reagent_containers/food))
		if(health <= 0)
			return
		user.visible_message(span_notice("\The [src] happily gulps down \the [O] right out of \the [user]'s hand, it seems pretty content now."),span_notice("\The [src] happily gulps down \the [O] right out of your hand, it seems pretty content now."))
		user.drop_from_inventory(O)
		qdel(O)
		well_fed = world.time
		return
	return ..()

/mob/living/simple_mob/vore/meowl/PounceTarget(mob/living/M, successrate = 100)
	vore_pounce_cooldown = world.time + 1 SECONDS // don't attempt another pounce for a while
	if(prob(max(successrate,33))) // pounce success!
		M.Weaken(5)
		M.visible_message(span_danger("\The [src] pounces on \the [M]!"))
	else // pounce misses!
		M.visible_message(span_danger("\The [src] attempts to pounce \the [M] but misses!"))
		playsound(src, 'sound/weapons/punchmiss.ogg', 25, 1, -1)

	if(will_eat(M) && (!M.canmove || vore_standing_too)) //if they're edible then eat them too
		return EatTarget(M)
	else
		return //just leave them

/datum/category_item/catalogue/fauna/meowl
	name = "Extra-Realspace Fauna - Meowl"
	desc = "Classification: Strigiline\
	<br><br>\
	These unusual creatures are sometimes found within redgate locations and seem to exhibit both the characteristics of a cat and of an owl. \
	Whilst these animals at a glance appear to be rather sweet and friendly, they are actually very competent predators and excellent opportunists. \
	They will very rarely attack their prey when there are other creatures nearby, preferring to wait until their target is alone and unprotected. \
	Despite this, these creatues can be rather docile in the right conditions, and will not attack those who it believes it can get food from reliably."
	value = CATALOGUER_REWARD_HARD

// DQEdit - legacy engage_target override body removed.
