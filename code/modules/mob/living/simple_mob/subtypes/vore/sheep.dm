/mob/living/simple_mob/vore/sheep
	drag_buckle = FALSE
	name = "sheep"
	desc = "looks warm and wooly!."
	tt_desc = "Ovis aries"

	icon_state = "sheep"
	icon_living = "sheep"
	icon_dead = "sheep-dead"
	icon = 'icons/mob/vore.dmi'

	faction = FACTION_SHEEP
	endurance = 40

	see_in_dark = 2

	meat_amount = 5
	meat_type = /obj/item/reagent_containers/food/snacks/meat

	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "kicks"

	melee_damage_lower = 1
	melee_damage_upper = 5
	attacktext = list("kicked")
	attack_sound = SFX_VOICE_BAA

	max_buckled_mobs = 1 //Yeehaw
	can_buckle = TRUE
	buckle_movable = TRUE
	buckle_lying = FALSE
	mount_offset_x = 0

	say_list_type = /datum/say_list/sheep



// Activate Noms!
/mob/living/simple_mob/vore/sheep
	vore_active = 1
	vore_icons = SA_ICON_LIVING

CAPABILITIES(/mob/living/simple_mob/vore/sheep)
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE)
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE)

/mob/living/simple_mob/vore/sheep/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = -1

/mob/living/simple_mob/vore/sheep/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "With a final few gulps, the sheep finishes swallowing you down into its hot, dark guts… The wool on the outside is doing you no favors with its insulation. The toasty organic flesh kneads and grinds around you with the stank of wet grass. The sheep seems to have already forgotten about you as it lets out a soft BAAH like belch and carries on doing nothing. "
	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
	"The sheep's idle trotting helps its stomach gently churn around you, slimily squelching against your figure.",
	"The equine predator lazily pauses for a moment and flops down encapsulating you in a strange fleshy hug; Before quickly jumping back up in confusion before trotting off.",
	"Some hot, viscous slime oozes down over your form, helping slicken you up during your stay.",
	"During a moment of relative silence, you can hear the beast's soft, relaxed breathing as it casually goes about its day.",
	"The thick, toasty atmosphere within the sheep's compact belly works in tandem with its steady, metronome-like heartbeat to soothe you.",
	"Your surroundings sway from side to side as the sheep trots about.")
	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
	"The sheep brays in annoyance clenching those compressed walls even tighter against your form!",
	"As the beast trots about, you're forced to slip and slide around amidst a pool of thick digestive goop!",
	"You’re overcome by the smell of wet grass as hot slime oozes over your head!",
	"As the thinning air begins to make you feel dizzy, menacing bworps and grumbles fill that dark, constantly shifting organ!",
	"The constant, rhythmic kneading and massaging starts to take its toll along with the muggy heat, making you feel weaker and weaker!",
	"The sheep trots around while digesting its meal, almost as if its forgotten it even had one.")

/datum/say_list/sheep
	speak = list("EHEHEHEHEH","eh?","BAAAAAAAHHHH")
	emote_hear = list("brays","smacks its lips loudly.")
	emote_see = list("shakes its head", "stamps a foot", "looks around vacantly.")

/*
/////For when/if someone makes a sprite for the sheep that doesn't have wool/////
//This will probably mostly work but you will need to make sure that it actually updates the way it's supposed to and plug in what you call the iconstates.
//If you just update icon_living it should still work with vore states and dying, you'll just need to make and label the sprites appropriately.
//Make sure you un-comment the variables above too.

//Add INTERACT_ITEM_PEACEFUL("Shear", PROC_REF(sheep_interaction_shear)) to the sheep's EXTEND_INTERACTIONS above when re-enabling.
/mob/living/simple_mob/vore/sheep/proc/sheep_interaction_shear(mob/user, obj/item/O, datum/interaction/interaction)
	if(!istype(O, /obj/item/material/knife) && !O.has_tool_quality(TOOL_WIRECUTTER))
		return FALSE
	if(!harvestable_wool)
		return FALSE
	task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(shear_done), done_args = list(user, O), interaction_key = "shearing")
	return TRUE

/mob/living/simple_mob/vore/sheep/proc/shear_done(mob/user, obj/item/O)
	if(!harvestable_wool)
		return
	act_message(user, src, MSG_SELF(span_notice("You shear %T% with %I%.")), MSG_OTHERS(span_notice("%U% shears %T% with %I%.")), item = O)
	new /obj/item/stack/material/fur/wool(get_turf(user))
	harvestable_wool = FALSE


/mob/living/simple_mob/vore/sheep/life_type_post_due()
	return TRUE

/mob/living/simple_mob/vore/sheep/life_type_post(datum/seq_frame/life/F)
	..()
	if(!harvestable_wool)
		wool_growth ++
		return
	if(wool_growth >= 200)
		harvestable_wool = TRUE
*/
