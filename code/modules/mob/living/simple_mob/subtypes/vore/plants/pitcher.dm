#define NUTRITION_FRUIT 250 //The amount of nutrition needed to produce a fruit
#define NUTRITION_PITCHER 3 * NUTRITION_FRUIT //The amount of nutrition needed to produce a new pitcher
#define NUTRITION_MEAT 50 //The amount of nutrition provided by slabs of meat
#define PITCHER_SATED 250 //The amount of nutrition needed before the pitcher will attempt to grow fruit.
#define PITCHER_HUNGRY 150 //The nutrition cap under which the pitcher actively attempts to lure prey.

GLOBAL_LIST_INIT(pitcher_plant_lure_messages, list(
	"The pitcher plant smells lovely, beckoning you closer.",
	"The sweet scent wafting from the pitcher plant  makes your mouth water.",
	"You feel an urge to investigate the pitcher plant closely.",
	"You find yourself staring at the pitcher plant without really thinking about it.",
	"Doesn't the pitcher plant smell amazing?")) //Messages sent to nearby players if the pitcher is trying to lure prey. This is global to prevent a new list every time a new pitcher plant spawns.

//Pitcher plants, a passive carnivorous plant mob for xenobio and space vine spawning.
//Consider making immune to space vine entangling.
/mob/living/simple_mob/vore/pitcher_plant
	name = "pitcher plant"
	desc = "A carnivorous pitcher plant, bigger than a man."
	tt_desc = "Sarraceniaceae gigantus"

	icon_state = "pitcher_plant"
	icon_living = "pitcher_plant"
	icon_dead = "pitcher_plant_dead"
	icon = 'icons/mob/vore.dmi'

	anchored = 1 // Rooted plant. Only killing it will let you move it.
	endurance = 200
	// Combat mode stays off: a pitcher in combat mode would stop players swapping places with it, but interfere with vore bump.
	faction = FACTION_PLANTS // Makes plant-b-gone deadly.

	min_oxy = 0 //Immune to atmos because so are space vines. This is arbitrary and can be tweaked if desired.
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	minbodytemp = 0
	meat_type = /obj/item/reagent_containers/food/snacks/pitcher_fruit // Allows pitcher plants to be chopped up and replanted. Probably.
	meat_amount = 1 // And allows you to replant them should you so please.

	melee_damage_upper = 0 //This shouldn't attack people but if it does (admemes) no damage can be dealt.
	melee_damage_lower = 0

	armor_spec = "laser=-50;bio=-100;rad=100" // Okay fine fire type beats plant type // Poison kills the plant good.

	var/fruit = FALSE //Has the pitcher produced a fruit?
	var/meat = 0 //How many units of meat is the plant digesting? Separate from actual vore mechanics.
	var/meatspeed = 5 //How many units of meat is converted to nutrition each tick?
	var/pitcher_metabolism = 0.1 //How much nutriment does the pitcher lose every 2 seconds? 0.1 should be around 30 every 10 minutes.
	var/scent_strength = 5 //How much can a hungry pitcher confuse nearby people?
	COOLDOWN_DECLARE(lifechecks_cooldown) //Throttle to limit vore/hungry proc calls
	var/list/pitcher_plant_lure_messages = null
	can_be_drop_prey = FALSE

/mob/living/simple_mob/vore/pitcher_plant //Putting vore variables separately because apparently that's tradition.
	vore_bump_chance = 100
	vore_bump_emote = "slurps up" //Not really a good way to make the grammar work with a passive vore plant.
	vore_active = 1
	vore_icons = 1
	vore_capacity = 1
	vore_pounce_chance = 5 // Either this makes mobs sometimes get eaten for attacking it or nothing happens and I don't know which it is.
	swallowTime = 3 //3 deciseconds. This is intended to be nearly instant, e.g. victim trips and falls in.
	vore_ignores_undigestable = 0
	vore_default_mode = DM_DIGEST

/mob/living/simple_mob/vore/pitcher_plant/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.desc	= "You leaned a little too close to the pitcher plant, stumbling over the lip and splashing into a puddle of liquid filling the bottom of the cramped pitcher. You squirm madly, righting yourself and scrabbling at the walls in vain as the slick surface offers no purchase. The dim light grows dark as the pitcher's cap lowers, silently sealing the exit. With a sinking feeling, you realize you won't be able to push the exit open even if you could somehow climb that high, leaving you helplessly trapped in the slick, tingling fluid. The ONLY POSSIBLE WAY OUT is if someone either kills this thing or lowers a lifeline down to help. Maybe some string, a wire, or a good rope would do the trick..."
	B.digest_burn = 0.1 // Sloowwwwww churns
	B.digest_brute = 0.1 // Okay so I know there's no physical churning because it's a plant just trust me on this you want both of these
	B.vore_verb = "trip"
	B.name = "pitcher"
	B.mode_flags = DM_FLAG_THICKBELLY
	B.wet_loop = 0 // As nice as the fancy internal sounds are, this is a plant.
	B.digestchance = 0
	B.escapechance = 0
	B.fancy_vore = 1
	B.vore_sound = "Squish2"
	B.release_sound = "Pred Escape"
	B.contamination_color = "purple"
	B.contamination_flavor = "Wet"

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Slick fluid trickles over you, carrying threads of sweetness.",
		"Everything is still, dark, and quiet. Your breaths echo quietly.",
		"The surrounding air feels thick and humid.")
	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"The slimy puddle stings faintly. It seems the plant has no need to quickly break down victims.",
		"The humid air settles in your lungs, keeping each breath more labored than the last.",
		"Fluid drips onto you, burning faintly as your body heat warms it.",
		"Digestive enzymes itch at your flesh as you are slowly dissolved into soupy nutrients."
		)
	B.own_emote_lists()
	B.emote_lists[DM_DRAIN] = list(
		"Each bead of slick fluid running down your body leaves you feeling weaker.",
		"It's cramped and dark, the air thick and heavy. Your limbs feel like lead.",
		"Strength drains from your frame. The cramped chamber feels easier to settle into with each passing moment.")
	B.struggle_messages_inside = list(
		"The narrow shape of the pitcher plant's stomach make it impossible to get any leverage. You can't escape.",
		"You struggle and push against the slick and slimy plant flesh surrounding you, but it's no use. There's no way out by yourself.",
		"Other predators would probably be getting queasy by now with all that fussing. Unfortunately, this thing just doesn't care. You're plant food.",
		"Squirm and struggle all you want, you're no closer to freedom. Nothing you're doing is working.",
		"You're just exhausting yourself with all this resistance, and the fumes of the plant's stomach are making you lightheaded.",
		"All that exertion is just making you exhausted. For something with no muscles, it seems perfectly built for keeping you in its gut.",
		"You literally can't escape by yourself. All you can do is wait for rescue and hope this dreadfully slow digestion doesn't snuff you out first.",
		"You can't reach the lid of the pitcher plant to pry yourself out. Even if you could, the walls are too slippery. If only someone could lower a string or a wire or a rope for you to grab on!",
		"The waxy walls are far too slippery for you to climb your way out, and trying to do so only drenches you in even more stinging slime.",
		"Although you try your best to claw your way to freedom, the pitcher's gut is too smooth and too tough for you to get any progress."
	)
	B.struggle_messages_outside = list(
		"Struggles from inside %pred cause its bulbous form to slosh from side-to-side. They might need some help to escape.",
		"You notice someone moving inside that pitcher plant! However, they clearly can't get out on their own.",
		"%pred's stomach shifts and slushes as someone inside of it tries in vain to escape. It doesn't look like they can, though.",
		"%pred seems unpertubed by the stubborn movement of its prey. They clearly aren't getting out on their own.")

/mob/living/simple_mob/vore/pitcher_plant/life_type_post_due()
	return TRUE

/mob/living/simple_mob/vore/pitcher_plant/life_type_post(datum/seq_frame/life/F)
	..()
	if(!F.alive())
		return

	var/lastmeat = src.meat //If Life procs every 2 seconds that means it takes 20 seconds to digest a steak
	src.meat = max(0,src.meat - src.meatspeed) //Clamp it to zero
	src.adjust_nutrition(lastmeat - src.meat) //If there's no meat, this will just be zero.
	if(src.nutrition >= PITCHER_SATED + NUTRITION_FRUIT)
		if(prob(10)) //Should be about once every 20 seconds.
			src.grow_fruit()
	var/lastnutrition = src.nutrition
	src.adjust_nutrition(-src.pitcher_metabolism)
	var/digested = lastnutrition - src.nutrition // Metabolising nutrients heals the pitcher.
	if(digested > 0)
		src.mend(TREAT_TISSUE_REPAIR, digested)
		src.mend(TREAT_ANTITOXIN, digested * 3)
	if(src.nutrition < src.pitcher_metabolism) // Starving.
		src.injure(INJURY_TOXIN, src.pitcher_metabolism, flags = INJURE_SILENT)
	if(COOLDOWN_FINISHED(src, lifechecks_cooldown))
		COOLDOWN_START(src, lifechecks_cooldown, 30 SECONDS)
		src.vore_checks()
		src.handle_hungry()
	if (!src.anchored)
		src.set_anchored(1) // If it's alive, it should root itself back down and once again be impossible to move.

/mob/living/simple_mob/vore/pitcher_plant/Initialize(mapload)
	. = ..()
	pitcher_plant_lure_messages = GLOB.pitcher_plant_lure_messages


/mob/living/simple_mob/vore/pitcher_plant/on_death(gibbed)
	..()
	set_anchored(0)
	if(fruit)
		new /obj/item/reagent_containers/food/snacks/pitcher_fruit(get_turf(src))
		fruit = FALSE

/mob/living/simple_mob/vore/pitcher_plant/proc/grow_fruit() //This proc handles the pitcher turning nutrition into fruit (and new pitchers).
	if(!fruit)
		if(nutrition >= PITCHER_SATED + NUTRITION_FRUIT)
			fruit = TRUE
			adjust_nutrition(-NUTRITION_FRUIT)
			return
		else
			return
	if(fruit)
		if(nutrition >= PITCHER_SATED + NUTRITION_PITCHER)
			var/turf/T = safepick(circleviewturfs(src, 2))
			if(T.density) //No spawning in walls
				return
			else if(src.loc ==T)
				return
			else
				new /mob/living/simple_mob/vore/pitcher_plant(get_turf(T))
				fruit = FALSE //No admeming this to spawn endless pitchers.
				adjust_nutrition(-NUTRITION_PITCHER)

CAPABILITIES(/mob/living/simple_mob/vore/pitcher_plant)
	op("pitcher_interaction_hand", hand(), ungated(), stance(I_HELP), label("Pick fruit"), then(PROC_REF(pitcher_interaction_hand)))
	op("pitcher_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(pitcher_interaction_item)))
	op("pitcher_fish_out", item(/obj/item/stack/cable_coil), claims(), starts(PROC_REF(fish_out_started)), wait(PROC_REF(fish_out_time)), then(PROC_REF(fish_out_done)))

MSG_DEF_SELF(pitcher/empty, "The pitcher is empty.")

/// Old attack_hand: a help-touch picks the fruit; anything else is the normal touch.
/mob/living/simple_mob/vore/pitcher_plant/proc/pitcher_interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(fruit)
		to_chat(user, span_infoplain("You pick a fruit from \the [src]."))
		var/obj/F = new /obj/item/reagent_containers/food/snacks/pitcher_fruit(get_turf(user)) //Drops at the user's feet if put_in_hands fails
		fruit = FALSE
		user.put_in_hands(F)
	else
		to_chat(user, span_infoplain("The [src] hasn't grown any fruit yet!"))
	return TRUE

/mob/living/simple_mob/vore/pitcher_plant/examine(mob/user)
	. = ..()
	if(fruit)
		. += "A plump fruit glistens beneath \the [src]'s cap."

/// The victim a wire loop can snag: the first human in the belly (only carbons, RIP mice).
/mob/living/simple_mob/vore/pitcher_plant/proc/fish_out_victim()
	return locate_within(vore_selected, /mob/living/carbon/human)

/// You can just spam click to stack attempts if you feel like abusing it.
/mob/living/simple_mob/vore/pitcher_plant/proc/fish_out_started(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!fish_out_victim())
		return MSG(pitcher/empty)
	act_message(user, src, MSG_SELF(span_infoplain("You use a loop of wire to try snagging someone trapped in %T%...")), MSG_OTHERS(span_infoplain("%U% uses a loop of wire to try fishing someone out of %T%.")))

/mob/living/simple_mob/vore/pitcher_plant/proc/fish_out_time(datum/act/op/A)
	return rand(3 SECONDS, 7 SECONDS)

/mob/living/simple_mob/vore/pitcher_plant/proc/fish_out_done(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/H = fish_out_victim()
	if(!H)
		return
	if(prob(15))
		act_message(user, H, MSG_SELF(span_infoplain("You heft %T% free from \the [src].")), MSG_OTHERS(span_notice("%U% pulls a sticky %T% free from \the [src].")))
		rel_add(src, nameof(prey_excludes), H)
		vore_selected.release_specific_contents(H)
		after(src, 1 MINUTES, PROC_REF(removeMobFromPreyExcludes), with = list(H))
	else
		to_chat(user, span_notice("The victim slips from your grasp!"))

/// Old attackby: feed meat, fish victims out with cable (the hit still lands, as before), newspaper does nothing.
/mob/living/simple_mob/vore/pitcher_plant/proc/pitcher_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O, /obj/item/reagent_containers/food/snacks/meat))
		if(meat > NUTRITION_FRUIT - NUTRITION_MEAT) //Can't exceed 250
			to_chat(user, span_infoplain("The [src] is full!"))
			return TRUE
		meat += NUTRITION_MEAT
		consume(O, user)
		return TRUE
	if(istype(O, /obj/item/newspaper))
		act_message(user, src, MSG_SELF(span_notice("You whap %T% with a rolled up newspaper.")), MSG_OTHERS(span_notice("%U% baps %T%, but it doesn't seem to do anything.")))
		to_chat(user, span_notice("Weird. That usually works. Maybe you can fish out its victim with some string or wire or something? Or maybe kill the thing with some plant-b-gone. Both would probably be safer than hacking it up with a person still inside."))
		return TRUE // You can't newspaper people to freedom like you do with other mobs, but since that doesn't work, fucking tell people.
	return OP_DECLINE

/mob/living/simple_mob/vore/pitcher_plant/proc/vore_checks()
	if(ckey) //This isn't intended to be a playable mob but skip all of this if it's player-controlled.
		return
	if(vore_selected && contents_count(vore_selected)) //Looping through all (potential) vore bellies would be more thorough but probably not worth the processing power if this check happens every 30 seconds.
		var/mob/living/L
		var/N = 0
		var/hasdigestable = 0
		var/hasindigestable = 0
		FOR_CONTENTS(L, vore_selected)
			if(istype(L, /mob/living/carbon/human/monkey))
				L.set_nutrition(0) //No stuffing monkeys with protein shakes for massive nutrition.
			if(!L.digestable)
				vore_selected.digest_mode = DM_DRAIN
				N = 1
				hasindigestable = 1
				continue
			else
				vore_selected.digest_mode = DM_DIGEST
				N = 1
				hasdigestable = 1
				continue
		if(hasdigestable && hasindigestable)
			vore_selected.digest_mode = DM_DIGEST //Let's digest until we digest all the digestable prey, then move onto draining indigestable prey.
		if(!N)
			vore_selected.release_all_contents() //If there's no prey, spit out everything.

/mob/living/simple_mob/vore/pitcher_plant/proc/handle_hungry() //Let's run this check every 30 seconds. This is how a hungry pitcher tries to lure prey.
	if(nutrition <= PITCHER_HUNGRY) //Is sanity check another way to say redundancy?
		var/turf/T = get_turf(src)
		var/cardinal_turfs = T.CardinalTurfs()

		for(var/mob/living/carbon/human/H in oview(2, src))
			if(!istype(H) || !isliving(H) || H.stat == DEAD) //Living mobs only
				continue
			if(HAS_SYNTHETIC_BIOLOGY(H) || !H.species.breath_type || H.internal) //Exclude species which don't breathe or have internals.
				continue
			if(src.Adjacent(H)) //If they can breathe and are next to the pitcher, confuse them.
				to_chat(H,span_red("The sweet, overwhelming scent from \the [src] makes your senses reel!"))
				H.status_at_least(STAT_CONFUSED, scent_strength)
				continue
			else
				to_chat(H, span_red("[pick(pitcher_plant_lure_messages)]"))

		for(var/turf/simulated/TR in cardinal_turfs)
			TR.wet_floor(1) //Same effect as water. Slip into plant, get ate.
	else
		return
/mob/living/simple_mob/vore/pitcher_plant/Crossed(atom/movable/AM as mob|obj) //Yay slipnoms
	if(AM.is_incorporeal())
		return
	if(istype(AM, /mob/living) && will_eat(AM) && !istype(AM, type) && prob(vore_bump_chance) && !ckey)
		animal_nom(AM)
	..()

/obj/item/reagent_containers/food/snacks/pitcher_fruit //As much as I want to tie hydroponics harvest code to the mob, this is simpler (albeit kinda hacky).
	name = "squishy fruit"
	desc = "A tender, fleshy fruit with a thin skin. Said to have an intensely sweet flavor, and also a narcotic paralyzing effect."
	icon = 'icons/obj/hydroponics_products.dmi'
	icon_state = "treefruit-product"
	color = "#a839a2"
	trash = /obj/item/seeds/pitcherseed
	nutriment_amt = 1
	nutriment_desc = list("pineapple" = 1)
	w_class = ITEMSIZE_SMALL
	var/datum/seed/seed = null
	var/obj/item/seeds/pit = null
	special_handling = TRUE


/obj/item/reagent_containers/food/snacks/pitcher_fruit/Initialize(mapload)
	. = ..()
	bitesize = 1
	seed = pit.seed()

/obj/item/reagent_containers/food/snacks/pitcher_fruit/afterattack(obj/O as obj, mob/user as mob, proximity)
	if(istype(O,/obj/machinery/microwave))
		return ..()
	if(istype (O, /obj/machinery/seed_extractor))
		var/obj/item/seeds/extracted = rel_take(src, nameof(pit))
		extracted?.forceMove(O.loc) //1 seed, perhaps balanced because you can get the reagents and the seed. Can be increased if desirable.
		consume(src, user)
		return
	if(!(proximity && O.is_open_container()))
		return
	to_chat(user, span_notice("You squeeze \the [src], juicing it into \the [O]."))
	reagents.trans_to(O, reagents.total_volume)
	user.drop_from_inventory(src)
	var/obj/item/seeds/dropped_pit = rel_take(src, nameof(pit))
	dropped_pit?.forceMove(user.loc)
	consume(src, user)

CAPABILITIES(/obj/item/reagent_containers/food/snacks/pitcher_fruit)
	configure(reagents(add = list(REAGENT_ID_PITCHERNECTAR = 5, REAGENT_ID_PARALYZE_FLUID = 5)))
	op("pitcher_fruit_self", in_hand(), label("Plant"), then(PROC_REF(pitcher_fruit_self)))

/// Old attack_self: plant the fruit.
/obj/item/reagent_containers/food/snacks/pitcher_fruit/proc/pitcher_fruit_self(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You plant the fruit."))
	new /obj/machinery/portable_atmospherics/hydroponics/soil/invisible(get_turf(user),src.seed)
	GLOB.seed_planted_shift_roundstat++
	consume(src, user)
	return

#undef NUTRITION_FRUIT
#undef NUTRITION_PITCHER
#undef NUTRITION_MEAT
#undef PITCHER_SATED
#undef PITCHER_HUNGRY

/obj/item/reagent_containers/food/snacks/pitcher_fruit/ownership()
	. = ..()
	. += owns(nameof(pit), policy = OWN_CONTAINED, starts = /obj/item/seeds/pitcherseed)
