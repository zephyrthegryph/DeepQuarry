/mob/living/simple_mob/vore/devil
	name = "statue of temptation"
	desc = "A tall statue made of red-tinted metal in the shape of some sort of demon or devil."
	catalogue_data = list(/datum/category_item/catalogue/fauna/devil)
	tt_desc = "Metal Statue"
	icon = 'icons/mob/vore64x64.dmi'
	icon_dead = "devil-dead"
	icon_living = "devil"
	icon_state = "devil"
	icon_rest = "devil"
	faction = FACTION_DEVIL
	old_x = -16
	old_y = 0
	default_pixel_x = -16
	pixel_x = -16
	pixel_y = 0
	friendly = list("nudges", "sniffs on", "rumbles softly at", "nuzzles")
	response_help = "bumps"
	response_disarm = "shoves"
	response_harm = "attacks"
	movement_cooldown = 0
	harm_intent_damage = 7
	melee_damage_lower = 3
	melee_damage_upper = 10
	maxHealth = 100
	attacktext = list("bites")
	see_in_dark = 8
	minbodytemp = 0

	vore_bump_chance = 25
	vore_digest_chance = 50
	vore_escape_chance = 5
	vore_pounce_chance = 1000
	vore_active = 1
	vore_icons = 1
	vore_icons = SA_ICON_LIVING | SA_ICON_REST
	vore_capacity = 1
	swallowTime = 50
	vore_ignores_undigestable = TRUE
	vore_default_mode = DM_DIGEST
	vore_pounce_maxhealth = 1000
	vore_bump_emote = "pounces on"

/mob/living/simple_mob/vore/devil/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "It turns out that this was not just any old statue, but some form of android waiting for its chance to ambush you. The moment that it laid its hands on you, your fate was decided. The jaws of the machine parted, if you could call them that, and immediately enveloped your head. The inside was hot and slick, but dry. The textures were startlingly realistic, the base was clearly a tongue, the top palate of the mouth was hard but somewhat pliable. Not that you had time to admire it before the rest of your body was stuffed inside. Through a short passage down through a rubbery tube of a gullet, mechanical contractions squeezing you down from behind, you're quickly deposited in something much resembling a stomach. Amid the sounds of mechanical whirrs, you can heard glorping, gurgling and burbling from unknown sources. The walls wrap firmly around your body, deliberately dramping you up into the smallest space that the machine can crush you into, whilst the synthetic lining around you ripples across your hunched up form. You can even see yourself, the gut itself is backlit by some eerie red glow, just enough to tell exactly what is happening to you. It doesn't help that you can see the drooling fluids glistening in the dim light."
	B.mode_flags = DM_FLAG_THICKBELLY
	B.belly_fullscreen = "synth_flesh_mono_hole"
	B.digest_brute = 2
	B.digest_burn = 2
	B.digest_oxy = 1
	B.digestchance = 100
	B.absorbchance = 0
	B.escapechance = 5
	B.selective_preference = DM_DIGEST
	B.escape_stun = 5

/datum/category_item/catalogue/fauna/devil
	name = "Extra-Realspace Machine - Statue of Temptation"
	desc = "Classification: Synthetic Lifeform\
	<br><br>\
	The origin of this machine is not well understood, neither is its purpose nor whether it is sapient. However, we have been able to study a little about their behaviour. \
	These creatures seem to disquise themselves as statues, making no movement what so ever when being directly observed. There is little to suggest they move at all when there is nobody present either. \
	However, when lifeforms exist nearby, these oddly curvaceous devils spring to life, lighting up and attempting to devour all living things. We assume they reduce their targets to biofuel to sustain themselves, but they have been known to break their disguise when attacked to defend themselves."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/vore/devil/PounceTarget(mob/living/M, successrate = 100)
	vore_pounce_cooldown = world.time + 1 SECONDS // don't attempt another pounce for a while
	if(prob(successrate)) // pounce success!
		M.Weaken(5)
		M.visible_message(span_danger("\The [src] pounces on \the [M]!"))
	else // pounce misses!
		M.visible_message(span_danger("\The [src] attempts to pounce \the [M] but misses!"))
		playsound(src, 'sound/weapons/punchmiss.ogg', 25, 1, -1)

	if(will_eat(M) && (!M.canmove || vore_standing_too)) //if they're edible then eat them too
		return EatTarget(M)
	else
		return //just leave them

//legacy /datum/ai_brain/.../find_target / can_attack / engage_target
// overrides removed in the combat migration. The brain handles targeting.
