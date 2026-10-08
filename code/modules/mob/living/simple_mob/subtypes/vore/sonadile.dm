/mob/living/simple_mob/vore/sonadile
	name = "sonadile"
	desc = "A tall, oddly proportioned bipedal reptile. Whilst its body is fairly large on its own, the incredibly long neck brings its height up to near 14 feet tall. Covered in green scales with a yellow underbelly, with a long thin tail, short legs and stubby arms. It has orange frills down its spine and the eyes are an odd grey colour, it doesn't appear to be able to see very well."
	catalogue_data = list(/datum/category_item/catalogue/fauna/sonadile)
	/// Ten seconds after the last meal: the full sprite shows its settled second stage.
	var/settled = FALSE
	tt_desc = "Crocodylidae"
	icon = 'icons/mob/vore64x64.dmi'
	icon_dead = "sonadile-dead"
	icon_living = "sonadile"
	icon_state = "sonadile"
	icon_rest = "sonadile"
	faction = FACTION_SONADILE
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
	endurance = 100
	attacktext = list("bites")
	see_in_dark = 8
	minbodytemp = 0
	say_list_type = /datum/say_list/sonadile

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

/mob/living/simple_mob/vore/sonadile/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The creature's huge maw drops down over your body, the long neck preventing it from barely having to shift its torso at all. The jaws quickly travel down you, slathering you in a drool as you're quickly stuffed through the flexible muscle of the throat. In a matter of seconds you are effortlessly lifted from the ground, your entire figure now reduced to a bulge within the neck of the beast, your feet soon vanishing into its mouth with a visceral gulp. The journey down is a long and slow one, the gullet squeezing you steadily along with heavy rippling contractions, the sonadile is quite content that you're heading in the right direction. With every inch, the world around you grows louder with the sound of a heartbeat and the gutteral grumbles of your upcoming destination. Before long you are squeezed down through a tight fleshy valve and deposited in the stomach of the reptile, walls immediately bearing down on you from every direction to ensure that you're tightly confined with little room to move. Hot, humid and slick with all manner of thick and thin liquids, this place isn't treating you any different from whatever else this animal likes to eat."
	B.mode_flags = DM_FLAG_THICKBELLY
	B.belly_fullscreen = "VBO_fleshs"
	B.digest_brute = 2
	B.digest_burn = 2
	B.digest_oxy = 1
	B.digestchance = 100
	B.absorbchance = 0
	B.escapechance = 5
	B.selective_preference = DM_DIGEST
	B.escape_stun = 5

/datum/say_list/sonadile
	emote_hear = list("warbles","roars","yawns")
	emote_see = list("stumbles about clumsily","slowly pans its head around","extends and shakes its frills","lashes its tail against the ground")

/datum/category_item/catalogue/fauna/sonadile
	name = "Extra-Realspace Fauna - Sonadile"
	desc = "Classification: Crocodylidae\
	<br><br>\
	The Sonadile is named as such due to it's vague resemblence to crocodilian animals and its enhanced ability to hunt purely through sound. \
	Frequently found in dark and damp spaces, the sonadile seems to have little problem moving about despite its unusual size and shape, and generally is seen walking on two legs. Relatively docile when left in the quiet, researchers should be warned that it is quick to attack those who speak out loud. \
	Whilst not entirely blind, it appears to have difficulty discerning differences between shapes and movement, but once it hears something that it interprets as prey, it attempts to swallow the creature whole and alive, lashing its head forward on the massively long neck."
	value = CATALOGUER_REWARD_HARD

/// Ten seconds after a meal, a full sonadile's sprite settles to its second stage (see settle_full_icon()).
/mob/living/simple_mob/vore/sonadile/draw(datum/look/look)
	..()
	if(vore_active && settled && vore_fullness && (look.state_so_far(src) == "[icon_living]-[vore_fullness]"))
		look.state("[icon_living]-2")

CAPABILITIES(/mob/living/simple_mob/vore/sonadile)
	on_change(nameof(vore_fullness), ANY, then(PROC_REF(fullness_changed)))

/// A new meal unsettles the sprite and starts the ten second wait for it to settle again.
/mob/living/simple_mob/vore/sonadile/proc/fullness_changed(datum/act/A)
	set_settled(FALSE)
	if(vore_fullness)
		after(src, 10 SECONDS, PROC_REF(settle_full_icon), key = "settle_full_icon")

TRACKED(/mob/living/simple_mob/vore/sonadile, settled)

/mob/living/simple_mob/vore/sonadile/proc/settle_full_icon()
	if(vore_fullness)
		set_settled(TRUE)
