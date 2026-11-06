/*
 * Plushies
 */

/*
 * Carp plushie
 */

/obj/item/toy/plushie/carp
	name = "space carp plushie"
	desc = "An adorable stuffed toy that resembles a space carp."
	icon = 'icons/obj/toy.dmi'
	icon_state = "basecarp"
	squeeze_sound = SFX_WEAPONS_BITE
	cooldown_length = 1 SECOND

CAPABILITIES(/obj/item/toy/plushie/carp)
	configure(item_combat(attack_verbs = list("bitten", "eaten", "fin slapped")))

// Attack mob
/obj/item/toy/plushie/carp/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	playsound(src, squeeze_sound, 20, 1)	// Play bite sound in local area
	return ..()

/obj/item/toy/plushie/carp/ice
	name = "ice carp plushie"
	icon_state = "icecarp"

/obj/item/toy/plushie/carp/silent
	name = "monochrome carp plushie"
	icon_state = "silentcarp"

/obj/item/toy/plushie/carp/electric
	name = "electric carp plushie"
	icon_state = "electriccarp"

/obj/item/toy/plushie/carp/gold
	name = "golden carp plushie"
	icon_state = "goldcarp"

/obj/item/toy/plushie/carp/toxin
	name = "toxic carp plushie"
	icon_state = "toxincarp"

/obj/item/toy/plushie/carp/dragon
	name = "dragon carp plushie"
	icon_state = "dragoncarp"

/obj/item/toy/plushie/carp/pink
	name = "pink carp plushie"
	icon_state = "pinkcarp"

/obj/item/toy/plushie/carp/candy
	name = "candy carp plushie"
	icon_state = "candycarp"

/obj/item/toy/plushie/carp/nebula
	name = "nebula carp plushie"
	icon_state = "nebulacarp"

/obj/item/toy/plushie/carp/void
	name = "void carp plushie"
	icon_state = "voidcarp"

//Small plushies.
/obj/item/toy/plushie
	name = "generic small plush"
	desc = "A small toy plushie. It's very cute."
	icon = 'icons/obj/toy.dmi'
	icon_state = "nymphplushie"
	w_class = ITEMSIZE_TINY
	var/last_message = 0
	var/pokephrase = "Uww!"
	var/opened = FALSE	// has this been slit open? this will allow you to store an object in a plushie.
	// owned: the item hidden inside the plushie, kept in its contents
	var/obj/item/stored_item	// Note: Stored items can't be bigger than the plushie itself.
	var/adjusted_name // Our modified name. Used so people don't do funny business with us!

	//This makes it so it reverts back to its initial name when it speaks if TRUE.
	//This should be used if a plushie can be made to say custom messages. Not currently required at the moment, but here just in case it'd added in the future.
	var/prevent_impersonation = FALSE

	var/special_handling = FALSE

	///The sound we make when squeezed
	var/squeeze_sound = SFX_ITEMS_DROP_PLUSHIE

	///Timer to track how long until we can play a sound again
	var/cooldown_timer
	///How long our cooldown timer is. Default 15 seconds
	var/cooldown_length = 15 SECONDS

/obj/item/toy/plushie/examine(mob/user)
	. = ..()
	if(opened)
		. += span_italics("You notice an incision has been made on [src].")
		if(in_range(user, src) && stored_item)
			. += span_italics("You can see something in there...")

/obj/item/toy/plushie/proc/interaction_hug(datum/act/op/A)
	return squeezed(A.actor, I_HELP)

/obj/item/toy/plushie/proc/interaction_poke(datum/act/op/A)
	return squeezed(A.actor, I_DISARM)

/obj/item/toy/plushie/proc/interaction_strangle(datum/act/op/A)
	return squeezed(A.actor, I_GRAB)

/obj/item/toy/plushie/proc/interaction_punch(datum/act/op/A)
	return squeezed(A.actor, I_HURT)

/// Old attack_self: hug, punch or poke it, and fish out anything stitched inside.
/obj/item/toy/plushie/proc/squeezed(mob/user, stance)
	if(special_handling)
		return OP_OK
	if(stored_item && opened && !op_claimed(src))
		perform_op(user, src, "find_inside", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)

	if(ELAPSED(src, last_message, CLOCK_WORLD) <= 1 SECOND)
		return OP_OK
	if(stance == I_HELP)
		act_message(user, src, MSG_SELF(span_notice("You hug %T%!")), MSG_OTHERS(span_notice(span_bold("%U%") + " hugs %T%!")))
	else if (stance == I_HURT)
		act_message(user, src, MSG_SELF(span_warning("You punch %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " punches %T%!")))
	else if (stance == I_GRAB)
		act_message(user, src, MSG_SELF(span_warning("You attempt to strangle %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " attempts to strangle %T%!")))
	else
		act_message(user, src, MSG_SELF(span_notice("You poke %T%.")), MSG_OTHERS(span_notice(span_bold("%U%") + " pokes %T%.")))
		if(COOLDOWN_FINISHED(src, cooldown_timer))
			playsound(src, squeeze_sound, 25, 0)
			COOLDOWN_START(src, cooldown_timer, cooldown_length)
	if(pokephrase) //There was no indiciation you had to use disarm intent to make it speak...So now it speaks if you touch it at all!
		say_phrase()
	STAMP(src, last_message, CLOCK_WORLD)
	return OP_OK

/obj/item/toy/plushie/proc/found_inside(datum/act/op/A)
	var/mob/user = A.actor
	if(!stored_item)
		return OP_FAILED
	to_chat(user, "You find [icon2html(stored_item, user.client)] [stored_item] in [src]!")
	stored_item.forceMove(get_turf(src))
	rel_take(src, nameof(stored_item))
	return OP_OK

/obj/item/toy/plushie/proc/say_phrase()
	//If we don't prevent impersonation, we just speak like normal!
	//The PI var is used in case a plushie can be made to speak a custom message.
	if(!prevent_impersonation)
		atom_say("[pokephrase]")
		return

	//If we do prevent impersonation, change the name to original, speak, then bring it back.
	var/shown_name = name
	name = initial(name) //No namestealing.
	atom_say("[pokephrase]")
	name = adjusted_name || shown_name // adjusted_name is set once it is renamed

/// The old Name Plushie verb: the plushie takes the name given (and so do the voices in it).
/obj/item/toy/plushie/proc/plushie_named(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R)
		return OP_OK
	var/mob/M = A.actor
	var/input = R.value
	if(input)
		name = input
		// Rename possessed voices too
		for(var/mob/living/voice/V in possessed_voice)
			V.name = input
		adjusted_name = input
		to_chat(M, "You name the plushie [input], giving it a hug for good luck.")
	return OP_OK

CAPABILITIES(/obj/item/toy/plushie)
	configure(item_sounds(drop = SFX_ITEMS_DROP_PLUSHIE))
	owns_one(nameof(stored_item), /obj/item)
	op("hug", in_hand(), stance(I_HELP), label("Hug"), then(PROC_REF(interaction_hug)))
	op("poke", in_hand(), stance(I_DISARM), label("Poke"), then(PROC_REF(interaction_poke)))
	op("strangle", in_hand(), stance(I_GRAB), label("Strangle"), then(PROC_REF(interaction_strangle)))
	op("punch", in_hand(), stance(I_HURT), label("Punch"), then(PROC_REF(interaction_punch)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	// A squeeze of an opened plushie takes a second to find what is stitched inside; the plushie is claimed meanwhile.
	op("find_inside", ai(), claims(CLAIM_TARGET), wait(1 SECOND), then(PROC_REF(found_inside)))
	// the old Name Plushie verb, carried, by someone with a mind (a unique plushie refuses)
	op("rename", menu(), label("Name Plushie"), needs(carried(), req(PROC_REF(can_rename))),
		asks(/datum/prompt/text, fields = list("question" = "What do you want to name the plushie?", "default" = "", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0)),
		then(PROC_REF(plushie_named)))

/// Old attackby: kiss it with another plushie, sew it, cut it open, or hide a small thing inside.
/obj/item/toy/plushie/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/toy/plushie) || istype(I, /obj/item/organ/external/head))
		act_message(user, src, MSG_SELF(span_notice("You make \the [I] kiss %T%!.")), \
			MSG_OTHERS(span_notice("%U% makes \the [I] kiss %T%!.")))
		return OP_PASS

	if(istype(I, /obj/item/threadneedle) && opened)
		to_chat(user, "You sew the hole underneath [src].")
		opened = FALSE
		return OP_PASS

	if(is_sharp(I) && !opened)
		to_chat(user, "You open a small incision in [src]. You can place tiny items inside.")
		opened = TRUE
		return OP_PASS

	if( (!(I.w_class > w_class)) && opened)
		if(stored_item)
			to_chat(user, "There is already something in here.")
			return OP_PASS

		to_chat(user, "You place [I] inside [src].")
		if(!move_into(src, nameof(src.stored_item), I, user))
			return OP_PASS
		to_chat(user, "You placed [I] into [src].")
		return OP_PASS

	return OP_DECLINE

/obj/item/toy/plushie/nymph
	name = "diona nymph plush"
	desc = "A plushie of an adorable diona nymph! While its level of self-awareness is still being debated, its level of cuteness is not."
	icon_state = "nymphplushie"
	pokephrase = "Chirp!"

CAPABILITIES(/obj/item/toy/plushie/nymph)
	configure(atom_rules(bubble_icon = "plant"))

/obj/item/toy/plushie/teshari
	name = "teshari plush"
	desc = "This is a plush teshari. Very soft, with a pompom on the tail. The toy is made well, as if alive. Looks like she is sleeping. Shhh!"
	icon_state = "teshariplushie"
	pokephrase = "Rya!"

CAPABILITIES(/obj/item/toy/plushie/teshari)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/mouse
	name = "mouse plush"
	desc = "A plushie of a delightful mouse! What was once considered a vile rodent is now your very best friend."
	icon_state = "mouseplushie"
	pokephrase = "Squeak!"

CAPABILITIES(/obj/item/toy/plushie/mouse)
	configure(atom_rules(bubble_icon = "maus"))

/obj/item/toy/plushie/kitten
	name = "kitten plush"
	desc = "A plushie of a cute kitten! Watch as it purrs its way right into your heart."
	icon_state = "kittenplushie"
	pokephrase = "Mrow!"

CAPABILITIES(/obj/item/toy/plushie/kitten)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/lizard
	name = "lizard plush"
	desc = "A plushie of a scaly lizard! Very controversial, after being accused as \"racist\" by some Unathi."
	icon_state = "lizardplushie"
	pokephrase = "Hiss!"

CAPABILITIES(/obj/item/toy/plushie/lizard)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/spider
	name = "spider plush"
	desc = "A plushie of a fuzzy spider! It has eight legs - all the better to hug you with."
	icon_state = "spiderplushie"
	pokephrase = "Sksksk!"

CAPABILITIES(/obj/item/toy/plushie/spider)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/farwa
	name = "farwa plush"
	desc = "A farwa plush doll. It's soft and comforting!"
	icon_state = "farwaplushie"
	pokephrase = "Squaw!"

CAPABILITIES(/obj/item/toy/plushie/farwa)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/corgi
	name = "corgi plushie"
	icon_state = "corgi"
	pokephrase = "Woof!"

CAPABILITIES(/obj/item/toy/plushie/corgi)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/girly_corgi
	name = "corgi plushie"
	icon_state = "girlycorgi"
	pokephrase = "Arf!"

CAPABILITIES(/obj/item/toy/plushie/girly_corgi)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/robo_corgi
	name = "borgi plushie"
	icon_state = "robotcorgi"
	pokephrase = "Bark."

CAPABILITIES(/obj/item/toy/plushie/robo_corgi)
	configure(atom_rules(bubble_icon = "synthetic"))

/obj/item/toy/plushie/octopus
	name = "octopus plushie"
	icon_state = "loveable"
	pokephrase = "Squish!"

CAPABILITIES(/obj/item/toy/plushie/octopus)
	configure(atom_rules(bubble_icon = "tentacles"))

/obj/item/toy/plushie/face_hugger
	name = "facehugger plushie"
	icon_state = "huggable"
	pokephrase = "Hug!"

CAPABILITIES(/obj/item/toy/plushie/face_hugger)
	configure(atom_rules(bubble_icon = "science"))

//foxes are basically the best

/obj/item/toy/plushie/red_fox
	name = "red fox plushie"
	icon_state = "redfox"
	pokephrase = "Gecker!"

CAPABILITIES(/obj/item/toy/plushie/red_fox)
	configure(atom_rules(bubble_icon = "latte_fox"))

/obj/item/toy/plushie/black_fox
	name = "black fox plushie"
	icon_state = "blackfox"
	pokephrase = "Ack!"

CAPABILITIES(/obj/item/toy/plushie/black_fox)
	configure(atom_rules(bubble_icon = "latte_fox"))

/obj/item/toy/plushie/marble_fox
	name = "marble fox plushie"
	icon_state = "marblefox"
	pokephrase = "Awoo!"

CAPABILITIES(/obj/item/toy/plushie/marble_fox)
	configure(atom_rules(bubble_icon = "latte_fox"))

/obj/item/toy/plushie/blue_fox
	name = "blue fox plushie"
	icon_state = "bluefox"
	pokephrase = "Yoww!"

CAPABILITIES(/obj/item/toy/plushie/blue_fox)
	configure(atom_rules(bubble_icon = "latte_fox"))

/obj/item/toy/plushie/orange_fox
	name = "orange fox plushie"
	icon_state = "orangefox"
	pokephrase = "Yagh!"

CAPABILITIES(/obj/item/toy/plushie/orange_fox)
	configure(atom_rules(bubble_icon = "latte_fox"))

/obj/item/toy/plushie/coffee_fox
	name = "coffee fox plushie"
	icon_state = "coffeefox"
	pokephrase = "Gerr!"

CAPABILITIES(/obj/item/toy/plushie/coffee_fox)
	configure(atom_rules(bubble_icon = "latte_fox"))

/obj/item/toy/plushie/pink_fox
	name = "pink fox plushie"
	icon_state = "pinkfox"
	pokephrase = "Yack!"

CAPABILITIES(/obj/item/toy/plushie/pink_fox)
	configure(atom_rules(bubble_icon = "latte_fox"))

/obj/item/toy/plushie/purple_fox
	name = "purple fox plushie"
	icon_state = "purplefox"
	pokephrase = "Whine!"

CAPABILITIES(/obj/item/toy/plushie/purple_fox)
	configure(atom_rules(bubble_icon = "latte_fox"))

/obj/item/toy/plushie/crimson_fox
	name = "crimson fox plushie"
	icon_state = "crimsonfox"
	pokephrase = "Auuu!"

CAPABILITIES(/obj/item/toy/plushie/crimson_fox)
	configure(atom_rules(bubble_icon = "latte_fox"))

/obj/item/toy/plushie/deer
	name = "deer plushie"
	icon_state = "deer"
	pokephrase = "Bleat!"

CAPABILITIES(/obj/item/toy/plushie/deer)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/black_cat
	name = "black cat plushie"
	icon_state = "blackcat"
	pokephrase = "Mlem!"

CAPABILITIES(/obj/item/toy/plushie/black_cat)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/grey_cat
	name = "grey cat plushie"
	icon_state = "greycat"
	pokephrase = "Mraw!"

CAPABILITIES(/obj/item/toy/plushie/grey_cat)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/white_cat
	name = "white cat plushie"
	icon_state = "whitecat"
	pokephrase = "Mew!"

CAPABILITIES(/obj/item/toy/plushie/white_cat)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/orange_cat
	name = "orange cat plushie"
	icon_state = "orangecat"
	pokephrase = "Meow!"

CAPABILITIES(/obj/item/toy/plushie/orange_cat)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/siamese_cat
	name = "siamese cat plushie"
	icon_state = "siamesecat"
	pokephrase = "Mrew?"

CAPABILITIES(/obj/item/toy/plushie/siamese_cat)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/tabby_cat
	name = "tabby cat plushie"
	icon_state = "tabbycat"
	pokephrase = "Purr!"

CAPABILITIES(/obj/item/toy/plushie/tabby_cat)
	configure(atom_rules(bubble_icon = "heart"))

/obj/item/toy/plushie/tuxedo_cat
	name = "tuxedo cat plushie"
	icon_state = "tuxedocat"
	pokephrase = "Mrowww!!"

CAPABILITIES(/obj/item/toy/plushie/tuxedo_cat)
	configure(atom_rules(bubble_icon = "heart"))

// nah, squids are better than foxes :>

/obj/item/toy/plushie/squid
	name = DEVELOPER_WARNING_NAME

CAPABILITIES(/obj/item/toy/plushie/squid)
	configure(atom_rules(bubble_icon = "tentacles"))
	configure(item_worn(slots = SLOT_HEAD))

/obj/item/toy/plushie/squid
	name = "green squid plushie"
	desc = "A small, cute and loveable squid friend. This one is green."
	icon = 'icons/obj/toy.dmi'
	icon_state = "greensquid"
	pokephrase = "Squrr!"

/obj/item/toy/plushie/squid/mint
	name = "mint squid plushie"
	desc = "A small, cute and loveable squid friend. This one is mint coloured."
	icon_state = "mintsquid"
	pokephrase = "Blurble!"

/obj/item/toy/plushie/squid/blue
	name = "blue squid plushie"
	desc = "A small, cute and loveable squid friend. This one is blue."
	icon_state = "bluesquid"
	pokephrase = "Blob!"

/obj/item/toy/plushie/squid/orange
	name = "orange squid plushie"
	desc = "A small, cute and loveable squid friend. This one is orange."
	icon_state = "orangesquid"
	pokephrase = "Squash!"

/obj/item/toy/plushie/squid/yellow
	name = "yellow squid plushie"
	desc = "A small, cute and loveable squid friend. This one is yellow."
	icon_state = "yellowsquid"
	pokephrase = "Glorble!"

/obj/item/toy/plushie/squid/pink
	name = "pink squid plushie"
	desc = "A small, cute and loveable squid friend. This one is pink."
	icon_state = "pinksquid"
	pokephrase = "Wobble!"

/obj/item/toy/plushie/therapy
	name = "red therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is red."
	icon = 'icons/obj/toy.dmi'
	icon_state = "therapyred"
	item_state = "egg4" // It's the red egg in items_left/righthand

CAPABILITIES(/obj/item/toy/plushie/therapy)
	configure(atom_rules(bubble_icon = "medical"))

/obj/item/toy/plushie/therapy/purple
	name = "purple therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is purple."
	icon_state = "therapypurple"
	item_state = "egg1" // It's the magenta egg in items_left/righthand

/obj/item/toy/plushie/therapy/blue
	name = "blue therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is blue."
	icon_state = "therapyblue"
	item_state = "egg2" // It's the blue egg in items_left/righthand

/obj/item/toy/plushie/therapy/yellow
	name = "yellow therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is yellow."
	icon_state = "therapyyellow"
	item_state = "egg5" // It's the yellow egg in items_left/righthand

/obj/item/toy/plushie/therapy/orange
	name = "orange therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is orange."
	icon_state = "therapyorange"
	item_state = "egg4" // It's the red one again, lacking an orange item_state and making a new one is pointless

/obj/item/toy/plushie/therapy/green
	name = "green therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is green."
	icon_state = "therapygreen"
	item_state = "egg3" // It's the green egg in items_left/righthand

/obj/item/toy/plushie/fumo
	name = "Fumo"
	desc = "A plushie of a....?"
	icon_state = "fumoplushie"
	pokephrase = "I just don't think about losing."

// Tiny tin, rip - OP21

/obj/item/toy/plushie/tinytin
	name = "tiny tin plushie"
	desc = "A tiny fluffy nevrean plush with the label 'Tiny-Tin.' Press his belly to hear a sound!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_tin"
	pokephrase = "Peep peep!"
	squeeze_sound = SFX_VOICE_PEEP

/obj/item/toy/plushie/tinytin_sec
	name = "officer tiny tin plushie"
	desc = "Officer Tiny-Tin, now with rooty-tooty-shooty action! Press his belly to hear a sound!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_tinsec"
	pokephrase = "That means you fucked up!"
	squeeze_sound = SFX_VOICE_TINYTIN_FUCKEDUP

CAPABILITIES(/obj/item/toy/plushie/tinytin_sec)
	configure(atom_rules(bubble_icon = "security"))

/obj/item/toy/plushie/green_fox
	name = "green fox plushie"
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "greenfox"
	pokephrase = "Weh!"

/*
 * Plushies
 */
// the loadout entry shouldn't be able to grab those if everything goes right
/*
 * Plushies
 */
/obj/item/toy/plushie/lizardplushie
	name = "lizard plushie"
	desc = "An adorable stuffed toy that resembles a lizardperson."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_lizard"

CAPABILITIES(/obj/item/toy/plushie/lizardplushie)
	configure(item_combat(attack_verbs = list("clawed", "hissed", "tail slapped")))

/obj/item/toy/plushie/lizardplushie/kobold
	name = "kobold plushie"
	desc = "An adorable stuffed toy that resembles a kobold."
	icon = 'icons/obj/toy.dmi'
	icon_state = "kobold"
	pokephrase = "Wehhh!"

CAPABILITIES(/obj/item/toy/plushie/lizardplushie/kobold)
	configure(item_combat(attack_verbs = list("raided", "kobolded", "weh'd")))
	configure(item_sounds(drop = SFX_VOICE_WEH))

/* // Disable, this is an upstream player reference.
/obj/item/toy/plushie/lizardplushie/resh
	name = "security unathi plushie"
	desc = "An adorable stuffed toy that resembles an unathi wearing a head of security uniform. Perfect example of a monitor lizard."
	icon = 'icons/obj/toy.dmi'
	icon_state = "marketable_resh"
	pokephrase = "Halt! Sssecurity!"		//"Butts!" would be too obvious

CAPABILITIES(/obj/item/toy/plushie/lizardplushie/resh)
	configure(item_combat(attack_verbs = list("valided", "justiced", "batoned")))
*/ // end

/obj/item/toy/plushie/slimeplushie
	name = "slime plushie"
	desc = "An adorable stuffed toy that resembles a slime. It is practically just a hacky sack."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_slime"
	gender = FEMALE	//given all the jokes and drawings, I'm not sure the xenobiologists would make a slimeboy

CAPABILITIES(/obj/item/toy/plushie/slimeplushie)
	configure(item_combat(attack_verbs = list("blorbled", "slimed", "absorbed", "glomped")))

/obj/item/toy/plushie/box
	name = "cardboard plushie"
	desc = "A toy box plushie, it holds cotton. Only a baddie would place a bomb through the postal system..."
	icon = 'icons/obj/toy.dmi'
	icon_state = "box"

CAPABILITIES(/obj/item/toy/plushie/box)
	configure(item_combat(attack_verbs = list("open", "closed", "packed", "hidden", "rigged", "bombed", "sent", "gave")))

/obj/item/toy/plushie/borgplushie
	name = "robot plushie"
	desc = "An adorable stuffed toy of a robot."
	icon = 'icons/obj/toy.dmi'
	icon_state = "securityk9"

CAPABILITIES(/obj/item/toy/plushie/borgplushie)
	configure(atom_rules(bubble_icon = "security"))
	configure(item_combat(attack_verbs = list("beeped", "booped", "pinged")))

/obj/item/toy/plushie/borgplushie/medihound
	name = "medihound plushie"
	icon_state = "medihound"

CAPABILITIES(/obj/item/toy/plushie/borgplushie/medihound)
	configure(atom_rules(bubble_icon = "cardiogram"))

/obj/item/toy/plushie/borgplushie/scrubpuppy
	name = "janihound plushie"
	icon_state = "scrubpuppy"

CAPABILITIES(/obj/item/toy/plushie/borgplushie/scrubpuppy)
	configure(atom_rules(bubble_icon = "synthetic"))

/obj/item/toy/plushie/foxbear
	name = "toy fox"
	desc = "Issa fox!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "fox"

/obj/item/toy/plushie/nukeplushie
	name = "operative plushie"
	desc = "A stuffed toy that resembles a syndicate nuclear operative. The tag claims operatives to be purely fictitious."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_nuke"
	pokephrase = "Hey, has anyone seen the nuke disk?"

CAPABILITIES(/obj/item/toy/plushie/nukeplushie)
	configure(atom_rules(bubble_icon = "synthetic_evil"))
	configure(item_combat(attack_verbs = list("shot", "nuked", "detonated")))

/obj/item/toy/plushie/otter
	name = "otter plush"
	desc = "A perfectly sized snuggable river weasel! Keep away from Clams."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_otter"

/obj/item/toy/plushie/vox
	name = "vox plushie"
	desc = "A stitched-together vox, fresh from the skipjack. Press its belly to hear it skree!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_vox"
	pokephrase = "Skreee!"
	squeeze_sound = SFX_VOICE_SHRIEK1

/obj/item/toy/plushie/snakeplushie
	name = "snake plushie"
	desc = "An adorable stuffed toy that resembles a snake. Not to be mistaken for the real thing."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_snake"

CAPABILITIES(/obj/item/toy/plushie/snakeplushie)
	configure(item_combat(attack_verbs = list("hissed", "snek'd", "rattled")))

/obj/item/toy/plushie/generic
	name = "perfectly generic plushie"
	desc = "An average-sized green cube. It isn't notable in any way."
	icon = 'icons/obj/toy.dmi'
	icon_state = "generic"

CAPABILITIES(/obj/item/toy/plushie/generic)
	configure(atom_rules(bubble_icon = "textbox"))
	configure(item_combat(attack_verbs = list("existed near")))

/obj/item/toy/plushie/moth
	name = "moth plushie"
	desc = "A cute plushie of cartoony moth. It's ultra fluffy but leaves dust everywhere."
	icon = 'icons/obj/toy.dmi'
	icon_state = "moth"
	pokephrase = "Aaaaaaa."
	squeeze_sound = SFX_VOICE_MOTH_SCREAM_MOTH

/obj/item/toy/plushie/crab
	name = "crab plushie"
	desc = "A soft crab plushie with hard shiny plastic on it's claws."
	icon = 'icons/obj/toy.dmi'
	icon_state = "crab"

CAPABILITIES(/obj/item/toy/plushie/crab)
	configure(item_combat(attack_verbs = list("snipped", "carcinated")))

/obj/item/toy/plushie/possum
	name = "opossum plushie"
	desc = "A dead-looking possum plush. It's okay, it's only playing dead."
	icon = 'icons/obj/toy.dmi'
	icon_state = "possum"

/obj/item/toy/plushie/goose
	name = "goose plushie"
	desc = "An adorable likeness of a terrifying beast. \
	It's simple existance chills you to the bone and \
	compells you to hide any loose objects it might steal."
	icon = 'icons/obj/toy.dmi'
	icon_state = "goose"

CAPABILITIES(/obj/item/toy/plushie/goose)
	configure(item_combat(attack_verbs = list("honked")))

/obj/item/toy/plushie/mouse/white
	name = "white mouse plush"
	icon_state = "mouse"
	icon = 'icons/obj/toy.dmi'

/obj/item/toy/plushie/sus
	name = "red spaceman plushie"
	desc = "A suspicious looking red spaceman plushie. Why does it smell like the vents?"
	icon = 'icons/obj/toy.dmi'
	icon_state = "sus_red"
	pokephrase = "Stab!"
	squeeze_sound = SFX_WEAPONS_SLICE

CAPABILITIES(/obj/item/toy/plushie/sus)
	configure(atom_rules(bubble_icon = "security"))
	configure(item_combat(attack_verbs = list("stabbed", "slashed")))

/obj/item/toy/plushie/sus/blue
	name = "blue spaceman plushie"
	desc = "A dapper looking blue spaceman plushie. Looks very intuitive."
	icon_state = "sus_blue"

/obj/item/toy/plushie/sus/white
	name = "white spaceman plushie"
	desc = "A whiny looking white spaceman plushie. Looks like it could cry at any moment."
	icon_state = "sus_white"

/obj/item/toy/plushie/bigcat
	name = "big cat plushie"
	desc = "A big, fluffy looking cat that just looks very huggable."
	icon = 'icons/obj/toy.dmi'
	icon_state = "big_cat"

/obj/item/toy/plushie/basset
	name = "basset plushie"
	desc = "A sleepy looking basset hound plushie."
	icon = 'icons/obj/toy.dmi'
	icon_state = "basset"

/obj/item/toy/plushie/shark
	name = "shark plushie"
	desc = "A plushie depicting a somewhat cartoonish shark. The tag calls it a 'hákarl', noting that it was made by an obscure furniture manufacturer in old Scandinavia."
	icon = 'icons/obj/toy.dmi'
	icon_state = "blahaj"
	item_state = "blahaj"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand.dmi',
		)

/obj/item/toy/plushie/teshari/strix
	name = "Strix Hades"
	desc = "This is Strix Hades the plushie Avali. Very soft, with a pompom on the tail. The toy is made well, as if alive. Looks like he is sleeping. Shhh!"
	icon_state = "strixplush"
	item_state = "strixplush"
	pokephrase = "Weh!"
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi')

CAPABILITIES(/obj/item/toy/plushie/teshari/strix)
	configure(item_worn(slots = SLOT_BACK | SLOT_HEAD))

/obj/item/toy/plushie/teshari/strix/can_rename(datum/act/op/A)
	return "You cannot rename Strix Hades, you hug him anyway."

/obj/item/toy/plushie/teshari/eili
	name = "Eili"
	desc = "This is a plushie that resembles an Avali named Eili. The ammount of detail makes it almost look lifelike! Looks like she is sleeping. Shhh!"
	icon_state = "jeans_eiliplush"
	item_state = "jeans_eiliplush"
	pokephrase = "Weh!"
	icon = 'icons/vore/custom_items_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/vore/custom_items_left_hand_yw.dmi',
		slot_r_hand_str = 'icons/vore/custom_items_right_hand_yw.dmi',
		slot_back_str = 'icons/vore/custom_onmob_yw.dmi',
		slot_head_str = 'icons/vore/custom_onmob_yw.dmi')

CAPABILITIES(/obj/item/toy/plushie/teshari/eili)
	configure(item_worn(slots = SLOT_BACK | SLOT_HEAD))

/obj/item/toy/plushie/teshari/eili/can_rename(datum/act/op/A)
	return "You cannot rename Eili, you hug her anyway."

/obj/item/toy/plushie/teshari/_yw
	name = "lifelike teshari plush"
	desc = "This is a plush teshari. Very soft. The ammount of detail makes it almost look lifelike! Looks like it is sleeping. Shhh!"
	icon_state = "teshariplushie_brown"
	item_state = "teshariplushie_brown"
	pokephrase = "Rya!"
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi')

CAPABILITIES(/obj/item/toy/plushie/teshari/_yw)
	configure(item_worn(slots = SLOT_BACK | SLOT_HEAD))

/obj/item/toy/plushie/teshari/w_yw
	name = "lifelike teshari plush"
	desc = "This is a plush teshari. Very soft. The ammount of detail makes it almost look lifelike! Looks like it is sleeping. Shhh!"
	icon_state = "teshariplushie_white"
	item_state = "teshariplushie_white"
	pokephrase = "Rya!"
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi')

CAPABILITIES(/obj/item/toy/plushie/teshari/w_yw)
	configure(item_worn(slots = SLOT_BACK | SLOT_HEAD))

/obj/item/toy/plushie/teshari/b_yw
	name = "lifelike teshari plush"
	desc = "This is a plush teshari. Very soft. The ammount of detail makes it almost look lifelike! Looks like it is sleeping. Shhh!"
	icon_state = "teshariplushie_black"
	item_state = "teshariplushie_black"
	pokephrase = "Rya!"
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi',
		slot_ear_str = 'icons/mob/toy_worn.dmi')

CAPABILITIES(/obj/item/toy/plushie/teshari/b_yw)
	configure(item_worn(slots = SLOT_BACK | SLOT_HEAD))

/obj/item/toy/plushie/teshari/y_yw
	name = "lifelike teshari plush"
	desc = "This is a plush teshari. Very soft. The ammount of detail makes it almost look lifelike! Looks like it is sleeping. Shhh!"
	icon_state = "teshariplushie_yellow"
	item_state = "teshariplushie_yellow"
	pokephrase = "Rya!"
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi')

CAPABILITIES(/obj/item/toy/plushie/teshari/y_yw)
	configure(item_worn(slots = SLOT_BACK | SLOT_HEAD))

/// Requirement for renaming: someone with a mind, and a plushie that takes a name (a unique one says why it doesn't).
/obj/item/toy/plushie/proc/can_rename(datum/act/op/A)
	if(!has_a_mind(A.actor))
		return MSG(plushie/no_mind)
	return null
