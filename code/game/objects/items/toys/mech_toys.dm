/*
 * Mech toys (previously labeled prizes, but that's unintuitive)
 * Mech toy combat
 */

// Mech battle special attack types.
#define SPECIAL_ATTACK_HEAL 1
#define SPECIAL_ATTACK_DAMAGE 2
#define SPECIAL_ATTACK_UTILITY 3
#define SPECIAL_ATTACK_OTHER 4

// Max length of a mech battle
#define MAX_BATTLE_LENGTH 50

/obj/item/toy/mecha
	icon = 'icons/obj/toy.dmi'
	icon_state = "ripleytoy"
	drop_sound = SFX_MECHA_MECHSTEP
	reach = 2 // So you can battle across the table!

	// Mech Battle Vars
	var/timer = 0 // Timer when it'll be off cooldown
	var/cooldown = 1.5 SECONDS // Cooldown between play sessions (and interactions)
	var/cooldown_multiplier = 20 // Cooldown multiplier after a battle (by default: battle cooldowns are 30 seconds)
	var/quiet = FALSE // If it makes noise when played with
	var/wants_to_battle = FALSE // TRUE = Offering battle to someone || FALSE = Not offering battle
	var/in_combat = FALSE // TRUE = in combat currently || FALSE = Not in combat
	var/combat_health = 0 // The mech's health in battle
	var/max_combat_health = 0 // The mech's max combat health
	var/special_attack_charged = FALSE // TRUE = the special attack is charged || FALSE = not charged
	var/special_attack_type = 0 // What type of special attack they use - SPECIAL_ATTACK_DAMAGE, SPECIAL_ATTACK_HEAL, SPECIAL_ATTACK_UTILITY, SPECIAL_ATTACK_OTHER
	var/special_attack_type_message = "" // What message their special move gets on examining
	var/special_attack_cry = "*flip" // The battlecry when using the special attack
	var/special_attack_cooldown = 0 // Current cooldown of their special attack
	var/wins = 0 // This mech's win count in combat
	var/losses = 0 // ...And their loss count in combat

/obj/item/toy/mecha/Initialize(mapload)
	. = ..()
	desc = "Mini-Mecha action figure! Collect them all! Attack your friends or another mech with one to initiate epic mech combat! [desc]."
	combat_health = max_combat_health
	switch(special_attack_type)
		if(SPECIAL_ATTACK_DAMAGE)
			special_attack_type_message = "an aggressive move, which deals bonus damage."
		if(SPECIAL_ATTACK_HEAL)
			special_attack_type_message = "a defensive move, which grants bonus healing."
		if(SPECIAL_ATTACK_UTILITY)
			special_attack_type_message = "a utility move, which heals the user and damages the opponent."
		if(SPECIAL_ATTACK_OTHER)
			special_attack_type_message = "a special move, which [special_attack_type_message]"
		else
			special_attack_type_message = "a mystery move, even I don't know."

/obj/item/toy/mecha/proc/in_range(source, user) // Modify our in_range proc specifically for mech battles!
	if(get_dist(source, user) <= 2)
		return 1

	return 0 //not in range and not telekinetic

/**
 * this proc combines "sleep" while also checking for if the battle should continue
 *
 * this goes through some of the checks - the toys need to be next to each other to fight!
 * if it's player vs themself: They need to be able to "control" both mechs (either must be adjacent or using TK).
 * if it's player vs player: Both players need to be able to "control" their mechs (either must be adjacent or using TK).
 * if all the checks are TRUE, it does the sleeps, and returns TRUE. Otherwise, it returns FALSE.
 * Arguments:
 * * delay - the amount of time the sleep at the end of the check will sleep for
 * * attacker - the attacking toy in the battle.
 * * attacker_controller - the controller of the attacking toy. there should ALWAYS be an attacker_controller
 * * opponent - (optional) the defender controller in the battle, for PvP
 */

/obj/item/toy/mecha/proc/combat_can_continue(obj/item/toy/mecha/attacker, mob/living/carbon/attacker_controller, mob/living/carbon/opponent)
	if(!attacker_controller) // If the attacker for whatever reason is null, don't continue.
		return FALSE

	if(!attacker) // If there's no attacker, then attacker_controller IS the attacker.
		if(!in_range(src, attacker_controller))
			act_message(attacker_controller, src, others = span_suicide("%U% is running from %T%! The coward!"))
			return FALSE
	else // If there's an attacker, we can procede as normal.
		if(!in_range(src, attacker)) // The two toys aren't next to each other, the battle ends.
			act_message(attacker_controller, src, MSG_SELF(span_notice(" [attacker] and %T% separate, ending the battle. ")), \
				MSG_OTHERS(span_notice(" [attacker] and %T% separate, ending the battle. ")))
			return FALSE

		// Dead men tell no tales, incapacitated men fight no fights.
		if(attacker_controller.incapacitated())
			return FALSE
		// If the attacker_controller isn't next to the attacking toy (and doesn't have telekinesis), the battle ends.
		if(!in_range(attacker, attacker_controller))
			act_message(attacker_controller, attacker, MSG_SELF(span_notice("You separate from %T%, ending the battle. ")), \
				MSG_OTHERS(span_notice("%U% separates from %T%, ending the battle.")))
			return FALSE

		// If it's PVP and the opponent is not next to the defending(src) toy (and doesn't have telekinesis), the battle ends.
		if(opponent)
			if(opponent.incapacitated())
				return FALSE
			if(!in_range(src, opponent))
				act_message(opponent, src, MSG_SELF(span_notice(" You separate from %T%, ending the battle. ")), \
					MSG_OTHERS(span_notice(" %U% separates from %T%, ending the battle.")))
				return FALSE
		// If it's not PVP and the attacker_controller isn't next to the defending toy (and doesn't have telekinesis), the battle ends.
		else
			if (!in_range(src, attacker_controller))
				act_message(attacker_controller, src, MSG_SELF(span_notice(" You separate [attacker] and %T%, ending the battle. ")), \
					MSG_OTHERS(span_notice(" %U% separates from %T% and [attacker], ending the battle.")))
				return FALSE

	// If all that is good, the battle goes on.
	return TRUE

//all credit to skasi for toy mech fun ideas
CAPABILITIES(/obj/item/toy/mecha)
	// the old attack_self (and attack_tk): play with it
	op("play", in_hand(), label("Play"), then(PROC_REF(interaction_self)))
	op("play_tk", tk(), label("Play"), then(PROC_REF(interaction_tk)))
	// a toy mech on a toy mech starts a battle (the hit goes on after)
	op("battle", item(/obj/item/toy/mecha), label("Battle"), then(PROC_REF(interaction_item)))
	// picking it up plays with it once it's in hand
	op("pick_up", hand(), label("Pick up"), then(PROC_REF(mecha_toy_pick_up)))

/// Old attack_self.
/obj/item/toy/mecha/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, timer))
		to_chat(user, span_notice("You play with [src]."))
		COOLDOWN_START(src, timer, cooldown)
		play_sfx(user, SFX_MECHA_MECHSTEP)
	return OP_OK

/// Picking up a toy mech plays with it once it's in hand.
/obj/item/toy/mecha/proc/mecha_toy_pick_up(datum/act/op/A)
	var/mob/user = A.actor
	pick_up_by_hand(user)
	if(loc == user)
		attack_self(user)
	return OP_OK

/**
 * If you attack a mech with a mech, initiate combat between them
 */
/// Old attackby.
/obj/item/toy/mecha/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/toy/mecha/M = A.held
	if(check_battle_start(user, M))
		mecha_brawl(M, user)
	return OP_DECLINE

/**
 * Attack is called from the user's toy, aimed at target(another human), checking for target's toy.
 */
/obj/item/toy/mecha/attack(mob/living/target, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(target == user)
		to_chat(user, span_notice("Target another toy mech if you want to start a battle with yourself."))
		return ITEM_INTERACT_FAILURE
	else if(stance != I_HURT)
		if(wants_to_battle) //prevent spamming someone with offers
			to_chat(user, span_notice("You already are offering battle to someone!"))
			return ITEM_INTERACT_FAILURE
		if(!check_battle_start(user)) //if the user's mech isn't ready, don't bother checking
			return ITEM_INTERACT_FAILURE

		for(var/obj/item/I in target.get_all_held_items())
			if(istype(I, /obj/item/toy/mecha)) //if you attack someone with a mech who's also holding a mech, offer to battle them
				var/obj/item/toy/mecha/M = I
				if(!M.check_battle_start(target, null, user)) //check if the attacker mech is ready
					break

				//slap them with the metaphorical white glove
				if(M.wants_to_battle) //if the target mech wants to battle, initiate the battle from their POV
					mecha_brawl(M, target, user) //P = defender's mech / SRC = attacker's mech / target = defender / user = attacker
					M.wants_to_battle = FALSE
					return ITEM_INTERACT_SUCCESS

		//extend the offer of battle to the other mech
		to_chat(user, span_notice("You offer battle to [target.name]!"))
		to_chat(target, span_notice(span_bold("[user.name] wants to battle with [user.p_their()] [name]!") + " " + span_italics("Attack them with a toy mech to initiate combat.")))
		wants_to_battle = TRUE
		after(src, 6 SECONDS, PROC_REF(withdraw_offer), with = list(user))
		return ITEM_INTERACT_SUCCESS

	..()

/**
 * Old attack_tk - Sorry, you have to be face to face to initiate a battle, it's good sportsmanship
 */
/obj/item/toy/mecha/proc/interaction_tk(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, timer))
		to_chat(user, span_notice("You telekinetically play with [src]."))
		COOLDOWN_START(src, timer, cooldown)
		play_sfx(user, SFX_MECHA_MECHSTEP)
	return OP_OK

/**
 * Resets the request for battle.
 *
 * For use in a timer, this proc resets the wants_to_battle variable after a short period.
 * Arguments:
 * * user - the user wanting to do battle
 */
/obj/item/toy/mecha/proc/withdraw_offer(mob/living/carbon/user)
	if(wants_to_battle)
		wants_to_battle = FALSE
		to_chat(user, span_notice("You get the feeling they don't want to battle."))

/obj/item/toy/mecha/examine()
	. = ..()
	. += span_notice("This toy's special attack is [special_attack_cry], [special_attack_type_message] ")
	if(in_combat)
		. += span_notice("This toy has a maximum health of [max_combat_health]. Currently, it's [combat_health].")
		. += span_notice("Its special move light is [special_attack_cooldown? "flashing red." : "green and is ready!"]")
	else
		. += span_notice("This toy has a maximum health of [max_combat_health].")

	if(wins || losses)
		. += span_notice("This toy has [wins] wins, and [losses] losses.")

/**
 * The 'master' proc of the mech battle. Processes the entire battle's events and makes sure it start and finishes correctly.
 *
 * src is the defending toy, and the battle proc is called on it to begin the battle.
 * After going through a few checks at the beginning to ensure the battle can start properly, the battle begins a loop that lasts
 * until either toy has no more health. During this loop, it also ensures the mechs stay in combat range of each other.
 * It will then randomly decide attacks for each toy, occasionally making one or the other use their special attack.
 * When either mech has no more health, the loop ends, and it displays the victor and the loser while updating their stats and resetting them.
 * Arguments:
 * * attacker - the attacking toy, the toy in the attacker_controller's hands
 * * attacker_controller - the user, the one who is holding the toys / controlling the fight
 * * opponent - optional arg used in Mech PvP battles: the other person who is taking part in the fight (controls src)
 */
/obj/item/toy/mecha/proc/mecha_brawl(obj/item/toy/mecha/attacker, mob/living/carbon/attacker_controller, mob/living/carbon/opponent)
	//A GOOD DAY FOR A SWELL BATTLE!
	act_message(attacker_controller, src, MSG_SELF(span_danger(" You collide [attacker] into %T%, sparking a fierce battle! ")), \
		MSG_OTHERS(span_danger(" %U% collides [attacker] with %T%! Looks like they're preparing for a brawl! ")), \
		MSG_BLIND(span_hear(" You hear hard plastic smacking into hard plastic.")))

	in_combat = TRUE
	attacker.in_combat = TRUE

	//1.5 second cooldown * 20 = 30 second cooldown after a fight
	COOLDOWN_START(src, timer, cooldown*cooldown_multiplier)
	COOLDOWN_START(attacker, timer, attacker.cooldown*attacker.cooldown_multiplier)

	after(src, 1 SECOND, PROC_REF(brawl_round), with = list(attacker, attacker_controller, opponent, 0))

/// Checks the fighters, then half a second later the next exchange lands.
/obj/item/toy/mecha/proc/brawl_round(obj/item/toy/mecha/attacker, mob/living/carbon/attacker_controller, mob/living/carbon/opponent, battle_length)
	//--THE BATTLE BEGINS--
	if(!QDELETED(attacker) && combat_health > 0 && attacker.combat_health > 0 && battle_length < MAX_BATTLE_LENGTH && combat_can_continue(attacker, attacker_controller, opponent))
		after(src, 0.5 SECONDS, PROC_REF(brawl_exchange), with = list(attacker, attacker_controller, opponent, battle_length))
		return
	brawl_end(attacker, attacker_controller, opponent)

/obj/item/toy/mecha/proc/brawl_exchange(obj/item/toy/mecha/attacker, mob/living/carbon/attacker_controller, mob/living/carbon/opponent, battle_length)
	if(QDELETED(attacker))
		brawl_end(attacker, attacker_controller, opponent)
		return
	var/mob/living/carbon/src_controller = (opponent)? opponent : attacker_controller

	//before we do anything - deal with charged attacks
	if(special_attack_charged)
		act_message(src_controller, src, MSG_SELF(span_danger(" You unleash %T%'s special attack! ")), \
			MSG_OTHERS(span_danger(" %T% unleashes its special attack!! ")))
		special_attack_move(attacker)
	else if(attacker.special_attack_charged)

		act_message(attacker_controller, attacker, MSG_SELF(span_danger(" You unleash %T%'s special attack! ")), \
			MSG_OTHERS(span_danger(" %T% unleashes its special attack!! ")))
		attacker.special_attack_move(src)
	else
		//process the cooldowns
		if(special_attack_cooldown > 0)
			special_attack_cooldown--
		if(attacker.special_attack_cooldown > 0)
			attacker.special_attack_cooldown--

		//combat commences
		switch(rand(1,8))
			if(1 to 3) //attacker wins
				if(attacker.special_attack_cooldown == 0 && attacker.combat_health <= round(attacker.max_combat_health/3)) //if health is less than 1/3 and special off CD, use it
					attacker.special_attack_charged = TRUE
					act_message(attacker_controller, attacker, MSG_SELF(span_danger(" You begin charging %T%'s special attack! ")), \
						MSG_OTHERS(span_danger(" %T% begins charging its special attack!! ")))
				else //just attack
					attacker.SpinAnimation(5, 0)
					play_sfx(attacker, SFX_MECHA_MECHSTEP, 1.5)
					combat_health--
					act_message(attacker_controller, src, MSG_SELF(span_danger(" You ram [attacker] into %T%! ")), \
						MSG_OTHERS(span_danger(" [attacker] devastates %T%! ")), \
						MSG_BLIND(span_hear(" You hear hard plastic smacking hard plastic.")))
					if(prob(5))
						combat_health--
						play_sfx(src, SFX_EFFECTS_METEORIMPACT, 0.5)
						act_message(attacker_controller, src, MSG_SELF(span_boldwarning(" ...and you land a CRIPPLING blow on %T%! ")), \
							MSG_OTHERS(span_boldwarning(" ...and lands a CRIPPLING BLOW! ")))

			if(4) //both lose
				attacker.SpinAnimation(5, 0)
				SpinAnimation(5, 0)
				combat_health--
				attacker.combat_health--
				// This is sloppy but we don't have do_sparks.
				play_sfx(src, SFX_SPARKS)
				fx_sparks(src, 2, FALSE)
				play_sfx(attacker, SFX_SPARKS)
				fx_sparks(attacker, 2, FALSE)
				if(prob(50))
					act_message(attacker_controller, src, MSG_SELF(span_danger(" [attacker] and %T% clash dramatically, causing sparks to fly! ")), \
						MSG_OTHERS(span_danger(" [attacker] and %T% clash dramatically, causing sparks to fly! ")), \
						MSG_BLIND(span_hear(" You hear hard plastic rubbing against hard plastic.")))
				else
					act_message(src_controller, src, MSG_SELF(span_danger(" %T% and [attacker] clash dramatically, causing sparks to fly! ")), \
						MSG_OTHERS(span_danger(" %T% and [attacker] clash dramatically, causing sparks to fly! ")), \
						MSG_BLIND(span_hear(" You hear hard plastic rubbing against hard plastic.")))
			if(5) //both win
				play_sfx(attacker, SFX_WEAPONS_PARRY)
				if(prob(50))
					act_message(attacker_controller, src, MSG_SELF(span_danger(" %T%'s attack deflects off of [attacker]. ")), \
						MSG_OTHERS(span_danger(" %T%'s attack deflects off of [attacker]. ")), \
						MSG_BLIND(span_hear(" You hear hard plastic bouncing off hard plastic.")))
				else
					act_message(src_controller, src, MSG_SELF(span_danger(" [attacker]'s attack deflects off of %T%. ")), \
						MSG_OTHERS(span_danger(" [attacker]'s attack deflects off of %T%. ")), \
						MSG_BLIND(span_hear(" You hear hard plastic bouncing off hard plastic.")))

			if(6 to 8) //defender wins
				if(special_attack_cooldown == 0 && combat_health <= round(max_combat_health/3)) //if health is less than 1/3 and special off CD, use it
					special_attack_charged = TRUE
					act_message(src_controller, src, MSG_SELF(span_danger(" You begin charging %T%'s special attack! ")), \
						MSG_OTHERS(span_danger(" %T% begins charging its special attack!! ")))
				else //just attack
					SpinAnimation(5, 0)
					play_sfx(src, SFX_MECHA_MECHSTEP, 1.5)
					attacker.combat_health--
					act_message(src_controller, src, MSG_SELF(span_danger(" You smash %T% into [attacker]! ")), \
						MSG_OTHERS(span_danger(" %T% smashes [attacker]! ")), \
						MSG_BLIND(span_hear(" You hear hard plastic smashing hard plastic.")))
					if(prob(5))
						attacker.combat_health--
						play_sfx(attacker, SFX_EFFECTS_METEORIMPACT, 0.5)
						act_message(src_controller, attacker, MSG_SELF(span_boldwarning(" ...and you land a CRIPPLING blow on %T%! ")), \
							MSG_OTHERS(span_boldwarning(" ...and lands a CRIPPLING BLOW! ")))
			else
				act_message(attacker_controller, src, MSG_SELF(span_notice(" You don't know what to do next.")), \
					MSG_OTHERS(span_notice(" %T% and [attacker] stand around awkwardly.")))

	after(src, 0.5 SECONDS, PROC_REF(brawl_round), with = list(attacker, attacker_controller, opponent, battle_length + 1))

/obj/item/toy/mecha/proc/brawl_end(obj/item/toy/mecha/attacker, mob/living/carbon/attacker_controller, mob/living/carbon/opponent)
	if(QDELETED(attacker))
		in_combat = FALSE
		combat_health = max_combat_health
		return
	var/mob/living/carbon/src_controller = (opponent)? opponent : attacker_controller

	/// Lines chosen for the winning mech
	var/list/winlines = list("YOU'RE NOTHING BUT SCRAP!", "I'LL YIELD TO NONE!", "GLORY IS MINE!", "AN EASY FIGHT.", "YOU SHOULD HAVE NEVER FACED ME.", "ROCKED AND SOCKED.")

	if(attacker.combat_health <= 0 && combat_health <= 0) //both lose
		play_sfx(src, SFX_MACHINES_WARNING_BUZZER, 0.4, vary = TRUE)
		act_message(attacker_controller, src, MSG_SELF(span_boldnotice(" Both %T% and [attacker] are destroyed!")), \
			MSG_OTHERS(span_boldnotice(" MUTUALLY ASSURED DESTRUCTION!! %T% and [attacker] both end up destroyed!")))
	else if(attacker.combat_health <= 0) //src wins
		wins++
		attacker.losses++
		play_sfx(attacker, SFX_EFFECTS_LIGHT_FLICKER, 0.4)
		act_message(attacker_controller, attacker, MSG_SELF(span_notice(" %T% falls apart!")), \
			MSG_OTHERS(span_notice(" %T% falls apart!")))
		visible_message("[pick(winlines)]")
		act_message(src_controller, src, MSG_SELF(span_notice(" You raise up %T% victoriously over [attacker]!")), \
			MSG_OTHERS(span_notice(" %T% destroys [attacker] and walks away victorious!")))
	else if (combat_health <= 0) //attacker wins
		attacker.wins++
		losses++
		play_sfx(src, SFX_EFFECTS_LIGHT_FLICKER, 0.4)
		act_message(src_controller, src, MSG_SELF(span_notice(" %T% collapses!")), \
			MSG_OTHERS(span_notice(" %T% collapses!")))
		attacker.visible_message("[pick(winlines)]")
		act_message(attacker_controller, src, MSG_SELF(span_notice("You raise up [attacker] proudly over %T%") + "!"), \
			MSG_OTHERS(span_notice(" [attacker] demolishes %T% and walks away victorious!")))
	else //both win?
		visible_message("NEXT TIME.")
		//don't want to make this a one sided conversation
		quiet? attacker.visible_message("I WENT EASY ON YOU.") : attacker.visible_message("OF COURSE.")

	in_combat = FALSE
	attacker.in_combat = FALSE

	combat_health = max_combat_health
	attacker.combat_health = attacker.max_combat_health

	return

/**
 * This proc checks if a battle can be initiated between src and attacker.
 *
 * Both SRC and attacker (if attacker is included) timers are checked if they're on cooldown, and
 * both SRC and attacker (if attacker is included) are checked if they are in combat already.
 * If any of the above are true, the proc returns FALSE and sends a message to user (and target, if included) otherwise, it returns TRUE
 * Arguments:
 * * user: the user who is initiating the battle
 * * attacker: optional arg for checking two mechs at once
 * * target: optional arg used in Mech PvP battles (if used, attacker is target's toy)
 */
/obj/item/toy/mecha/proc/check_battle_start(mob/living/carbon/user, obj/item/toy/mecha/attacker, mob/living/carbon/target)
	if(attacker && attacker.in_combat)
		to_chat(user, span_notice("[target ? target.p_their() : "Your" ] [attacker.name] is in combat."))
		if(target)
			to_chat(target, span_notice("Your [attacker.name] is in combat."))
		return FALSE
	if(in_combat)
		to_chat(user, span_notice("Your [name] is in combat."))
		if(target)
			to_chat(target, span_notice("[target.p_Their()] [name] is in combat."))
		return FALSE
	if(attacker && !COOLDOWN_FINISHED(attacker, timer))
		to_chat(user, span_notice("[target ? target.p_their() : "Your" ] [attacker.name] isn't ready for battle."))
		if(target)
			to_chat(target, span_notice("Your [attacker.name] isn't ready for battle."))
		return FALSE
	if(!COOLDOWN_FINISHED(src, timer))
		to_chat(user, span_notice("Your [name] isn't ready for battle."))
		if(target)
			to_chat(target, span_notice("[target.p_Their()] [name] isn't ready for battle."))
		return FALSE

	return TRUE

/**
 * Processes any special attack moves that happen in the battle (called in the mechaBattle proc).
 *
 * Makes the toy shout their special attack cry and updates its cooldown. Then, does the special attack.
 * Arguments:
 * * victim - the toy being hit by the special move
 */
/obj/item/toy/mecha/proc/special_attack_move(obj/item/toy/mecha/victim)
	visible_message(special_attack_cry + "!!")

	special_attack_charged = FALSE
	special_attack_cooldown = 3

	switch(special_attack_type)
		if(SPECIAL_ATTACK_DAMAGE) //+2 damage
			victim.combat_health-=2
			play_sfx(src, SFX_WEAPONS_MARAUDER)
		if(SPECIAL_ATTACK_HEAL) //+2 healing
			combat_health+=2
			play_sfx(src, SFX_MECHA_MECH_SHIELD_RAISE)
		if(SPECIAL_ATTACK_UTILITY) //+1 heal, +1 damage
			victim.combat_health--
			combat_health++
			play_sfx(src, SFX_MECHA_MECHMOVE01, 0.6)
		if(SPECIAL_ATTACK_OTHER) //other
			super_special_attack(victim)
		else
			visible_message("I FORGOT MY SPECIAL ATTACK...")

/**
 * Base proc for 'other' special attack moves.
 *
 * This one is only for inheritance, each mech with an 'other' type move has their procs below.
 * Arguments:
 * * victim - the toy being hit by the super special move (doesn't necessarily need to be used)
 */
/obj/item/toy/mecha/proc/super_special_attack(obj/item/toy/mecha/victim)
	visible_message(span_notice(" [src] does a cool flip."))

/obj/random/mech_toy
	name = "Random Mech Toy"
	desc = "This is a random mech toy."
	icon = 'icons/obj/toy.dmi'
	icon_state = "ripleytoy"

DECLARE_LOOT(/obj/random/mech_toy, LOOT_TABLE(LOOT_TYPES(1, typesof(/obj/item/toy/mecha))))

/obj/item/toy/mecha/ripley
	name = "toy ripley"
	desc = "Mini-Mecha action figure! Collect them all! 1/13."
	max_combat_health = 4 // 200 integrity
	special_attack_type = SPECIAL_ATTACK_DAMAGE
	special_attack_cry = "GIGA DRILL BREAK"

/obj/item/toy/mecha/fireripley
	name = "toy firefighting ripley"
	desc = "Mini-Mecha action figure! Collect them all! 2/13."
	icon_state = "fireripleytoy"
	max_combat_health = 5 // 250 integrity?
	special_attack_type = SPECIAL_ATTACK_UTILITY
	special_attack_cry = "FIRE SHIELD"

/obj/item/toy/mecha/deathripley
	name = "toy deathsquad ripley"
	desc = "Mini-Mecha action figure! Collect them all! 3/13."
	icon_state = "deathripleytoy"
	max_combat_health = 5 // 250 integrity
	special_attack_type = SPECIAL_ATTACK_OTHER
	special_attack_type_message = "instantly destroys the opposing mech if its health is less than this mech's health."
	special_attack_cry = "KILLER CLAMP"

/obj/item/toy/mecha/deathripley/super_special_attack(obj/item/toy/mecha/victim)
	play_sfx(src, SFX_WEAPONS_SONIC_JACKHAMMER)
	if(victim.combat_health < combat_health) // Instantly kills the other mech if it's health is below our's.
		visible_message("EXECUTE!!")
		victim.combat_health = 0
	else // Otherwise, just deal one damage.
		victim.combat_health--

/obj/item/toy/mecha/gygax
	name = "toy gygax"
	desc = "Mini-Mecha action figure! Collect them all! 4/13."
	icon_state = "gygaxtoy"
	max_combat_health = 5 // 250 integrity
	special_attack_type = SPECIAL_ATTACK_UTILITY
	special_attack_cry = "SUPER SERVOS"

/obj/item/toy/mecha/durand
	name = "toy durand"
	desc = "Mini-Mecha action figure! Collect them all! 5/13."
	icon_state = "durandtoy"
	max_combat_health = 6 // 400 integrity
	special_attack_type = SPECIAL_ATTACK_HEAL
	special_attack_cry = "SHIELD OF PROTECTION"

/obj/item/toy/mecha/honk
	name = "toy H.O.N.K."
	desc = "Mini-Mecha action figure! Collect them all! 6/13."
	icon_state = "honktoy"
	max_combat_health = 4 // 140 integrity
	special_attack_type = SPECIAL_ATTACK_OTHER
	special_attack_type_message = "puts the opposing mech's special move on cooldown and heals this mech."
	special_attack_cry = "MEGA HORN"

/obj/item/toy/mecha/honk/super_special_attack(obj/item/toy/mecha/victim)
	play_sfx(src, SFX_MACHINES_HONKBOT_EVIL_LAUGH)
	victim.special_attack_cooldown += 3 // Adds cooldown to the other mech and gives a minor self heal
	combat_health++

/obj/item/toy/mecha/marauder
	name = "toy marauder"
	desc = "Mini-Mecha action figure! Collect them all! 7/13."
	icon_state = "maraudertoy"
	max_combat_health = 7 // 500 integrity
	special_attack_type = SPECIAL_ATTACK_DAMAGE
	special_attack_cry = "BEAM BLAST"

/obj/item/toy/mecha/seraph
	name = "toy seraph"
	desc = "Mini-Mecha action figure! Collect them all! 8/13."
	icon_state = "seraphtoy"
	max_combat_health = 8 // 550 integrity
	special_attack_type = SPECIAL_ATTACK_DAMAGE
	special_attack_cry = "ROCKET BARRAGE"

/obj/item/toy/mecha/mauler
	name = "toy mauler"
	desc = "Mini-Mecha action figure! Collect them all! 9/13."
	icon_state = "maulertoy"
	max_combat_health = 7 // 500 integrity
	special_attack_type = SPECIAL_ATTACK_DAMAGE
	special_attack_cry = "BULLET STORM"

/obj/item/toy/mecha/odysseus
	name = "toy odysseus"
	desc = "Mini-Mecha action figure! Collect them all! 10/13."
	icon_state = "odysseustoy"
	max_combat_health = 4 // 120 integrity
	special_attack_type = SPECIAL_ATTACK_HEAL
	special_attack_cry = "MECHA BEAM"

/obj/item/toy/mecha/phazon
	name = "toy phazon"
	desc = "Mini-Mecha action figure! Collect them all! 11/13."
	icon_state = "phazontoy"
	max_combat_health = 6 // 200 integrity
	special_attack_type = SPECIAL_ATTACK_UTILITY
	special_attack_cry = "NO-CLIP"

/obj/item/toy/mecha/reticence
	name = "toy Reticence"
	desc = "12/13"
	icon_state = "reticencetoy"
	quiet = TRUE
	max_combat_health = 4 //100 integrity
	special_attack_type = SPECIAL_ATTACK_OTHER
	special_attack_type_message = "has a lower cooldown than normal special moves, increases the opponent's cooldown, and deals damage."
	special_attack_cry = "*wave"

/obj/item/toy/mecha/reticence/super_special_attack(obj/item/toy/mecha/victim)
	special_attack_cooldown-- //Has a lower cooldown...
	victim.special_attack_cooldown++ //and increases the opponent's cooldown by 1...
	victim.combat_health-- //and some free damage.

/obj/item/toy/mecha/clarke
	name = "toy Clarke"
	desc = "13/13"
	icon_state = "clarketoy"
	max_combat_health = 4 //200 integrity
	special_attack_type = SPECIAL_ATTACK_UTILITY
	special_attack_cry = "ROLL OUT"

/obj/item/toy/mecha/fivestars
	name = "toy fivestars"
	desc = "Five stars!"
	icon_state = "fivestarstoy"
	max_combat_health = 4 //200 integrity
	special_attack_type = SPECIAL_ATTACK_UTILITY
	special_attack_cry = "ROLL OUT"

#undef SPECIAL_ATTACK_HEAL
#undef SPECIAL_ATTACK_DAMAGE
#undef SPECIAL_ATTACK_UTILITY
#undef SPECIAL_ATTACK_OTHER
#undef MAX_BATTLE_LENGTH
