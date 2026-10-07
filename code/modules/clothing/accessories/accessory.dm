/obj/item/clothing/accessory
	name = "tie"
	desc = "A neosilk clip-on tie."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "bluetie"
	item_state_slots = list(slot_r_hand_str = "", slot_l_hand_str = "")
	appearance_flags = RESET_COLOR	// Stops has_suit's color from being multiplied onto the accessory
	slot_flags = SLOT_TIE
	w_class = ITEMSIZE_SMALL
	var/glove_level = 1							// What 'level' the accessory is on if equipped on the gloveslot. Lower = things can be put on top of it.
	var/slot = ACCESSORY_SLOT_DECOR
	var/can_remove = TRUE						// Can it be taken off once attached?
	var/tmp/obj/item/clothing/has_suit	// The suit the tie may be attached to
	var/tmp/image/inv_overlay = null				// Overlay used when attached to clothing.
	var/tmp/image/mob_overlay = null
	var/overlay_state = null
	var/punch_force	= 0							// added melee damage
	var/punch_injury_kind						// what punches inflict (INJURY_*); null = the punch's own kind
	var/concealed_holster = 0
	var/list/on_rolled							// Lazylist. Used when jumpsuit sleeves are rolled ("rolled" entry) or it's rolled down ("down"). Set to "none" to hide in those states.
	sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/accessory/mob_teshari.dmi') //Teshari can into webbing, too!
	drop_sound = SFX_ITEMS_DROP_ACCESSORY
	pickup_sound = SFX_ITEMS_PICKUP_ACCESSORY

// an attached accessory is removed from its clothing.
/obj/item/clothing/accessory/on_destroy(force)
	on_removed()
	..()

// Delegate to the global clothing_appearance_handler singleton.
// The cached inv_overlay / mob_overlay vars remain on the accessory for
// backward compatibility with code that checks them directly.
/obj/item/clothing/accessory/proc/get_inv_overlay()
	if(!inv_overlay)
		inv_overlay = GLOB.clothing_appearance_handler.build_inv_overlay(src)
	return inv_overlay

/obj/item/clothing/accessory/proc/get_mob_overlay()
	if(!istype(loc, /obj/item/clothing))
		return null
	// Update the wearer view before delegating (existing callers expect this side-effect).
	if(ishuman(has_suit()?.loc))
		rel_set(src, nameof(wearer), has_suit().loc)
	else
		rel_clear(src, nameof(wearer))
	var/mob/living/carbon/human/H = wearer
	if(!ishuman(H))
		return null
	mob_overlay = GLOB.clothing_appearance_handler.build_mob_overlay(src)
	return mob_overlay

//when user attached an accessory to S
/obj/item/clothing/accessory/proc/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	rel_set(src, nameof(has_suit), S)
	src.forceMove(S)
	has_suit().add_overlay(get_inv_overlay())

	has_suit().force += force
	if(istype(S,/obj/item/clothing/gloves))
		var/obj/item/clothing/gloves/has_gloves = S
		has_gloves.punch_force = has_gloves.punch_force + punch_force

	if(user)
		to_chat(user, span_notice("You attach \the [src] to \the [has_suit()]."))
		add_fingerprint(user)

/obj/item/clothing/accessory/proc/on_removed(mob/user)
	if(!has_suit())
		return
	var/obj/item/clothing/old_suit = has_suit()
	old_suit.cut_overlay(get_inv_overlay())
	old_suit.force = initial(old_suit.force)
	if(istype(old_suit,/obj/item/clothing/gloves))
		var/obj/item/clothing/gloves/has_gloves = old_suit
		has_gloves.punch_force = initial(has_gloves.punch_force)
	// Clear both sides of the ownership relation. Qdel may delete an accessory
	// directly rather than going through clothing.remove_accessory().
	GLOB.accessory_slot_registry.remove_modifiers(src, old_suit)
	own_take_member(old_suit, nameof(old_suit.accessories), src)
	rel_clear(src, nameof(has_suit))
	if(QDELETED(src))
		return
	if(user && !issilicon(user))
		user.put_in_hands(src)
		add_fingerprint(user)
	else if(get_turf(src))		//We actually exist in space
		forceMove(get_turf(src))

CAPABILITIES(/obj/item/clothing/accessory)
	op("accessory_attached_hand", hand(), then(PROC_REF(accessory_attached_hand)))

/// Old attack_hand: an attached accessory isn't picked up.
/obj/item/clothing/accessory/proc/accessory_attached_hand(datum/act/op/A)
	if(has_suit())
		return TRUE	//we aren't an object on the ground so don't call parent
	return OP_DECLINE

/obj/item/clothing/accessory/tie
	name = "blue tie"
	icon_state = "bluetie"
	slot = ACCESSORY_SLOT_TIE

/obj/item/clothing/accessory/tie/red
	name = "red tie"
	icon_state = "redtie"

/obj/item/clothing/accessory/tie/blue_clip
	name = "blue tie with a clip"
	icon_state = "bluecliptie"

/obj/item/clothing/accessory/tie/blue_long
	name = "blue long tie"
	icon_state = "bluelongtie"

/obj/item/clothing/accessory/tie/red_clip
	name = "red tie with a clip"
	icon_state = "redcliptie"

/obj/item/clothing/accessory/tie/red_long
	name = "red long tie"
	icon_state = "redlongtie"

/obj/item/clothing/accessory/tie/black
	name = "black tie"
	icon_state = "blacktie"

/obj/item/clothing/accessory/tie/darkgreen
	name = "dark green tie"
	icon_state = "dgreentie"

/obj/item/clothing/accessory/tie/yellow
	name = "yellow tie"
	icon_state = "yellowtie"

/obj/item/clothing/accessory/tie/navy
	name = "navy tie"
	icon_state = "navytie"

/obj/item/clothing/accessory/tie/white
	name = "white tie"
	icon_state = "whitetie"

/obj/item/clothing/accessory/tie/horrible
	name = "horrible tie"
	desc = "A neosilk clip-on tie. This one is disgusting."
	icon_state = "horribletie"

/obj/item/clothing/accessory/bowtie
	name = "red bow tie"
	desc = "Snazzy!"
	icon_state = "redbowtie"
	slot = ACCESSORY_SLOT_TIE

/obj/item/clothing/accessory/bowtie/black
	name = "black bow tie"
	icon_state = "blackbowtie"

/obj/item/clothing/accessory/bowtie/white
	name = "white bow tie"
	icon_state = "whitebowtie"

/obj/item/clothing/accessory/maid_neck
	name = "maid neck cover"
	desc = "A neckpiece for a maid costume, it smells faintly of disappointment."
	icon_state = "maid_neck"

/obj/item/clothing/accessory/maidcorset
	name = "maid corset"
	desc = "The final touch that holds it all together."
	icon_state = "maidcorset"

/obj/item/clothing/accessory/maid_arms/get_mechanics_info(list/additional_information)
	return ..(list("Wearable as gloves, or attachable to uniforms. May visually conflict with actual gloves when attached to uniforms.") + additional_information)

/obj/item/clothing/accessory/maid_arms
	name = "maid arm covers"
	desc = "Cylindrical looking tubes that go over your arms, weird."
	slot_flags = SLOT_OCLOTHING | SLOT_GLOVES | SLOT_TIE
	body_parts_covered = ARMS
	heat_protection = ARMS
	cold_protection = ARMS
	icon_state = "maid_arms"

/obj/item/clothing/accessory/stethoscope
	name = "stethoscope"
	desc = "An outdated medical apparatus for listening to the sounds of the human body. It also makes you look like you know what you're doing."
	icon_state = "stethoscope"
	slot = ACCESSORY_SLOT_TIE

/obj/item/clothing/accessory/stethoscope/use_on_patient(mob/living/carbon/human/M, mob/living/user, stance = I_HURT)
	if(stance != I_HELP) //in case it is ever used as a surgery tool
		return ..()
	attack(M, user, user.zone_sel?.selecting || BP_TORSO, 1, stance) //default surgery behaviour is just to scan as usual
	return 1

/obj/item/clothing/accessory/stethoscope/attack(mob/living/carbon/human/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(ishuman(M) && isliving(user))
		if(stance == I_HELP)
			var/body_part = parse_zone(user.zone_sel.selecting)

			var/message_holder	//Holds pervy message
			var/message_holder2	//Hods the nutrition related message.
			var/beat_size = ""	//Small prey = quiet

			if(body_part)
				var/their = "their"
				switch(M.gender)
					if(MALE)	their = "his"
					if(FEMALE)	their = "her"

				var/sound = "heartbeat"
				var/sound_strength = "cannot hear"
				if(M.stat == DEAD || (M.status_flags & FAKEDEATH))
					sound_strength = "cannot hear"
					sound = "anything"
				else
					switch(body_part)
						//TORSO:
						//ORGANS INVENTORY: Heart, Lungs, Spleen, Voicebox,
						if(BP_TORSO)
							for(var/belly in M.vore_organs) // Pervy edit. //
								var/obj/belly/B = belly
								for(var/mob/living/carbon/human/H in B)
									if(H.size_multiplier < 0.5)
										beat_size = pick("quiet ", "hushed " ,"low " ,"hushed ")
									message_holder = pick("You can hear disparate heartbeats as well.", "You can hear a different [beat_size]heartbeat too.", "It sounds like there is more than one heartbeat." ,"You can pick up a [beat_size]heatbeat along with everything else.")
							if(M.nutrition > 900)	//dead
								message_holder2 = pick("Your listening is troubled by the occasional deep groan of their body.", "There is some moderate bubbling in the background.", "They seem to have a healthy metabolism as well.")

							var/obj/item/organ/internal/heart/heart = M.organ_in(O_HEART)
							sound_strength = "hear"
							sound = "no heartbeat"
							if(heart)
								if(heart.is_bruised())
									sound = span_warning("muffled heart sounds, as if fluid is around the heart") //yes this shows over the heart beinng robotic.
								else if(heart.robotic) //They have JUST a heart but no heartbeat
									if(heart.robotic == ORGAN_ASSISTED) //LVAD
										sound = "a loud, continual, electronic hum"
									else if(heart.robotic == ORGAN_ROBOT || heart.robotic == ORGAN_LIFELIKE)
										sound = "a light, rhythmic, mechanical clicking"
									else
										sound = span_warning("no heartbeat")
									if(istype(heart, /obj/item/organ/internal/heart/machine/anomalock))
										var/obj/item/organ/internal/heart/machine/anomalock/zap_heart = heart
										if(zap_heart.core)
											user.electrocute_act(15, src)
											user.emote("scream")
								else
									switch(M.pulse)
										if(PULSE_NONE)
											sound = "no heartbeat"
										if(PULSE_SLOW)
											sound = "a slow heartbeat"
										if(PULSE_NORM)
											sound = "a normal, healthy heartbeat"
										if(PULSE_FAST)
											sound = "a rapid heartbeat"
										if(PULSE_2FAST)
											sound = span_info("a very rapid heartbeat")
										if(PULSE_THREADY)
											sound = span_warning("an extremely rapid, thready, irregular heartbeat")

							var/obj/item/organ/internal/lungs/L = M.organ_in(O_LUNGS)
							if(!L || M.losebreath)
								sound += span_warning(" and no respiration")
							else if(M.is_lung_ruptured() || M.oxygen_debt() > 50)
								sound += span_warning(" and [pick("wheezing","gurgling")] sounds")
							else
								sound += " and healthy respiration"
						//GROIN
						//ORGANS INVENTORY: Appendix, Intestines, Kidneys, Liver, Spleen, Stomach.
						//Of these, the Intestines, Stomach, Liver, and Kidneys make noise.
						if(BP_GROIN)
							var/obj/item/organ/internal/intestine/intestine = M.organ_in(O_INTESTINE)
							var/obj/item/organ/internal/stomach/stomach = M.organ_in(O_STOMACH)
							var/obj/item/organ/internal/kidneys/kidneys = M.organ_in(O_KIDNEYS)
							var/obj/item/organ/internal/liver/liver = M.organ_in(O_LIVER)
							sound_strength = "hear"
							sound = span_warning("no gastric sounds,")
							if(intestine)
								if(intestine.is_bruised())
									sound = span_warning("slowed intestinal sounds")
								else
									sound = "normal intestinal sounds,"

							if(stomach)
								if(stomach.is_bruised())
									sound += span_warning(" slowed digestive sounds,")
								else
									sound += " with normal digestive sounds,"
							else
								sound += span_warning(" no digestive sounds,")

							if(kidneys && kidneys.is_bruised())
								sound += span_warning(" renal bruits,") //I don't really know how to convey this without using medical terminology.
							else
								sound += " no renal sounds,"

							if(liver) //yeah, I didn't know your liver could make sounds either.
								if(liver.is_bruised())
									sound += span_warning(" and abnormal liver sounds.")
								else
									sound += " and normal liver sounds."
						else
							sound_strength = "cannot hear"
							sound = "anything"

				act_message(user, src, MSG_SELF("You place %T% against [their] [body_part]. You [sound_strength] [sound]. [message_holder] [message_holder2]"), \
					MSG_OTHERS("%U% places %T% against [M]'s [body_part] and listens attentively."))
				return ITEM_INTERACT_SUCCESS

	return ..(M,user)

//Medals
/obj/item/clothing/accessory/medal
	name = "bronze medal"
	desc = "A bronze medal."
	icon_state = "bronze"
	slot = ACCESSORY_SLOT_MEDAL
	drop_sound = SFX_ITEMS_DROP_ACCESSORY
	pickup_sound = SFX_ITEMS_PICKUP_ACCESSORY

/obj/item/clothing/accessory/medal/conduct
	name = "distinguished conduct medal"
	desc = "A bronze medal awarded for distinguished conduct. Whilst a great honor, this is most basic award on offer. It is often awarded by a captain to a member of their crew."

/obj/item/clothing/accessory/medal/bronze_heart
	name = "bronze heart medal"
	desc = "A bronze heart-shaped medal awarded for sacrifice. It is often awarded posthumously or for severe injury in the line of duty."
	icon_state = "bronze_heart"

/obj/item/clothing/accessory/medal/nobel_science
	name = "nobel sciences award"
	desc = "A bronze medal which represents significant contributions to the field of science or engineering."

/obj/item/clothing/accessory/medal/silver
	name = "silver medal"
	desc = "A silver medal."
	icon_state = "silver"

/obj/item/clothing/accessory/medal/silver/valor
	name = "medal of valor"
	desc = "A silver medal awarded for acts of exceptional valor."

/obj/item/clothing/accessory/medal/silver/security
	name = "robust security award"
	desc = "An award for distinguished combat and sacrifice in defence of corporate commercial interests. Often awarded to security staff."

/obj/item/clothing/accessory/medal/gold
	name = "gold medal"
	desc = "A prestigious golden medal."
	icon_state = "gold"

/obj/item/clothing/accessory/medal/gold/captain
	name = "medal of captaincy"
	desc = "A golden medal awarded exclusively to those promoted to the rank of captain. It signifies the codified responsibilities of a captain, and their undisputable authority over their crew."

/obj/item/clothing/accessory/medal/gold/heroism
	name = "medal of exceptional heroism"
	desc = "An extremely rare golden medal awarded only by high ranking officials. To receive such a medal is the highest honor and as such, very few exist. This medal is almost never awarded to anybody but distinguished veteran staff."

/obj/item/clothing/accessory/medal/gold/casino
	name = "medal of true lucky winner"
	desc = "A gaudy golden medal with a logo of a casino engraved on top. The only achievement you had to earn this was great luck or great richness, neither of which is an achievement. Still, it instills a feeling of hope and smell of fresh bagels."

// Base type for 'medals' found in a "dungeon" submap, as a sort of trophy to celebrate the player's conquest.
/obj/item/clothing/accessory/medal/dungeon

/obj/item/clothing/accessory/medal/dungeon/alien_ufo
	name = "alien captain's medal"
	desc = "It vaguely like a star. It looks like something an alien captain might've worn. Probably."
	icon_state = "alien_medal"

//Scarves

/obj/item/clothing/accessory/scarf
	name = "green scarf"
	desc = "A stylish scarf. The perfect winter accessory for those with a keen fashion sense, and those who just can't handle a cold breeze on their necks."
	icon_state = "greenscarf"
	slot = ACCESSORY_SLOT_DECOR

/obj/item/clothing/accessory/scarf/red
	name = "red scarf"
	icon_state = "redscarf"

/obj/item/clothing/accessory/scarf/darkblue
	name = "dark blue scarf"
	icon_state = "darkbluescarf"

/obj/item/clothing/accessory/scarf/purple
	name = "purple scarf"
	icon_state = "purplescarf"

/obj/item/clothing/accessory/scarf/yellow
	name = "yellow scarf"
	icon_state = "yellowscarf"

/obj/item/clothing/accessory/scarf/orange
	name = "orange scarf"
	icon_state = "orangescarf"

/obj/item/clothing/accessory/scarf/lightblue
	name = "light blue scarf"
	icon_state = "lightbluescarf"

/obj/item/clothing/accessory/scarf/white
	name = "white scarf"
	icon_state = "whitescarf"

/obj/item/clothing/accessory/scarf/black
	name = "black scarf"
	icon_state = "blackscarf"

/obj/item/clothing/accessory/scarf/zebra
	name = "zebra scarf"
	icon_state = "zebrascarf"

/obj/item/clothing/accessory/scarf/christmas
	name = "christmas scarf"
	icon_state = "christmasscarf"

/obj/item/clothing/accessory/scarf/stripedred
	name = "striped red scarf"
	icon_state = "stripedredscarf"

/obj/item/clothing/accessory/scarf/stripedgreen
	name = "striped green scarf"
	icon_state = "stripedgreenscarf"

/obj/item/clothing/accessory/scarf/stripedblue
	name = "striped blue scarf"
	icon_state = "stripedbluescarf"

/obj/item/clothing/accessory/scarf/teshari/neckscarf
	name = "small neckscarf"
	desc = "a neckscarf that is too small for a human's neck"
	icon_state = "tesh_neckscarf"

TYPE_TABLE(/obj/item/clothing/accessory/scarf/teshari/neckscarf, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_TESHARI))))

/obj/item/clothing/accessory/halfcape
	name = "half cape"
	desc = "A tasteful half-cape, suitible for European nobles and retro anime protagonists."
	icon_state = "halfcape"
	slot = ACCESSORY_SLOT_DECOR

/obj/item/clothing/accessory/fullcape
	name = "full cape"
	desc = "A gaudy full cape. You're thinking about wearing it, aren't you?"
	icon_state = "fullcape"
	slot = ACCESSORY_SLOT_DECOR

/obj/item/clothing/accessory/sash
	name = "sash"
	desc = "A plain, unadorned sash."
	icon_state = "sash"
	slot = ACCESSORY_SLOT_OVER

//Gaiter scarves
/obj/item/clothing/accessory/gaiter
	name = "red neck gaiter"
	desc = "A slightly worn neck gaiter, it's loose enough to be worn comfortably like a scarf. Commonly used by outdoorsmen and mercenaries, both to keep warm and keep debris away from the face."
	icon_state = "gaiter_red"
	slot_flags = SLOT_MASK | SLOT_TIE
	body_parts_covered = FACE
	w_class = ITEMSIZE_SMALL
	slot = ACCESSORY_SLOT_INSIGNIA // snowflakey, i know, shut up
	item_flags = FLEXIBLEMATERIAL
	var/breath_masked = FALSE
	var/obj/item/clothing/mask/breath/breathmask
	actions_types = list(/datum/action/item_action/pull_on_gaiter)
	special_handling = TRUE

/obj/item/clothing/accessory/gaiter/update_clothing_icon()
	. = ..()
	if(ismob(src.loc))
		var/mob/M = src.loc
		M.update_inv_wear_mask()

/// Old attackby: tuck a breath mask behind the gaiter. Always falls through, as the old ..() did.
/obj/item/clothing/accessory/gaiter/proc/gaiter_tuck_mask_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/clothing/mask/breath))
		if(!own_bring_in(src, nameof(breathmask), I, null, user, TRUE, null, FALSE))
			return OP_DECLINE
		if(breathmask())
			gaiter_remove_mask_alt(user, null, null)
		to_chat(user, span_notice("You tuck [I] behind [src]."))
		rel_set(src, nameof(breathmask), I)
		breath_masked = TRUE
		item_flags &= ~FLEXIBLEMATERIAL
	return OP_DECLINE

/// Old click_alt: pull the tucked mask out. Falls through to the clothing alt-click (which ran first before).
/obj/item/clothing/accessory/gaiter/proc/gaiter_remove_mask_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(breath_masked && breathmask())
		to_chat(user, span_notice("You pull [breathmask()] out from behind [src], and it drops to your feet."))
		breathmask().forceMove(drop_location())
		rel_clear(src, nameof(breathmask))
		breath_masked = FALSE
		item_flags &= ~AIRTIGHT
		item_flags |= FLEXIBLEMATERIAL
	return OP_DECLINE

/// Old attack_self: pull the gaiter up or down.
/obj/item/clothing/accessory/gaiter/proc/gaiter_adjust_self(datum/act/op/A)
	var/mob/user = A.actor
	var/gaiterstring = "You pull [src] "
	if(src.icon_state == initial(icon_state))
		src.icon_state = "[icon_state]_up"
		gaiterstring += "up over your nose[breath_masked ? " and secure the mask tucked underneath." : "."]"
		if(breath_masked)
			item_flags |= AIRTIGHT
	else
		src.icon_state = initial(icon_state)
		gaiterstring += "down around your neck[breath_masked ? " and dislodge the mask tucked underneath." : "."]"
		body_parts_covered &= ~FACE
		if(breath_masked)
			item_flags &= ~AIRTIGHT
	to_chat(user, span_notice(gaiterstring))
	spent(mob_overlay, user) // we're gonna need to refresh these
	update_clothing_icon()	//so our mob-overlays update

/obj/item/clothing/accessory/gaiter/half //functions like a gaiter
	name = "black half-mask"
	icon_state = "half_mask"

/*
 * Pride Pins
 */
/obj/item/clothing/accessory/pride
	name = "pride pin"
	desc = "A pin displaying pride in one's identity."
	icon_state = "pride"
	slot = ACCESSORY_SLOT_MEDAL

/obj/item/clothing/accessory/pride/bi
	name = "bisexual pride pin"
	icon_state = "pride_bi"

/obj/item/clothing/accessory/pride/trans
	name = "transgender pride pin"
	icon_state = "pride_trans"

/obj/item/clothing/accessory/pride/ace
	name = "asexual pride pin"
	icon_state = "pride_ace"

/obj/item/clothing/accessory/pride/enby
	name = "nonbinary pride pin"
	icon_state = "pride_enby"

/obj/item/clothing/accessory/pride/pan
	name = "pansexual pride pin"
	icon_state = "pride_pan"

/obj/item/clothing/accessory/pride/lesbian
	name = "lesbian pride pin"
	icon_state = "pride_lesbian"

/obj/item/clothing/accessory/pride/intersex
	name = "intersex pride pin"
	icon_state = "pride_intersex"

/obj/item/clothing/accessory/pride/vore
	name = "vore pride pin"
	icon_state = "pride_vore"

// ranger ponchos

/obj/item/clothing/accessory/poncho/roles/ranger
	name = "red ranger poncho"
	desc = "A rugged all-weather poncho, perfectly coloured to match a popular line of neck gaiters. You could probably use it as a tent in a pinch!"
	icon_state = "rangerponcho_red"
	item_state = "rangerponcho_red"

// leg warmers

/obj/item/clothing/accessory/legwarmers
	name = "thigh-length legwarmers"
	desc = "A comfy pair of legwarmers. These are excessively long."
	icon_state = "legwarmers_thigh"

/obj/item/clothing/accessory/legwarmersmedium
	name = "medium-length legwarmers"
	desc = "A comfy pair of legwarmers. For those unfortunate enough to wear shorts in the cold."
	icon_state = "legwarmers_medium"

/obj/item/clothing/accessory/legwarmersshort
	name = "short legwarmers"
	desc = "A comfy pair of legwarmers. For those better in the cold than others."
	icon_state = "legwarmers_short"

//
// Collars and such like that
//

/obj/item/clothing/accessory/choker //A colorable, tagless choker
	name = "plain choker"
	slot_flags = SLOT_TIE | SLOT_OCLOTHING
	desc = "A simple, plain choker. Or maybe it's a collar?"
	icon_state = "choker_cst"
	item_state = "choker_cst"
	overlay_state = "choker_cst"
	var/customized = 0
	var/icon_previous_override

//Forces different sprite sheet on equip
/obj/item/clothing/accessory/choker/on_materialize()
	icon_previous_override = icon_override
	. = ..()

/obj/item/clothing/accessory/choker/equipped() //Solution for race-specific sprites for an accessory which is also a suit. Suit icons break if you don't use icon override which then also overrides race-specific sprites.
	..()
	setUniqueSpeciesSprite()

/obj/item/clothing/accessory/choker/proc/setUniqueSpeciesSprite()
	var/mob/living/carbon/human/H = loc
	if(!istype(H) && istype(has_suit(), /obj/item/clothing) && ishuman(has_suit().loc))
		H = has_suit().loc
	if(sprite_sheets && istype(H) && H.species.get_bodytype(H) && (H.species.get_bodytype(H) in sprite_sheets))
		icon_override = sprite_sheets[H.species.get_bodytype(H)]
		update_clothing_icon()

/obj/item/clothing/accessory/choker/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	rel_set(src, nameof(has_suit), S)
	setUniqueSpeciesSprite()
	..(S, user)

/obj/item/clothing/accessory/choker/dropped(mob/user, equipping, slot)
	..()
	icon_override = icon_previous_override

/obj/item/clothing/accessory/collar
	slot_flags = SLOT_TIE | SLOT_OCLOTHING
	icon_state = "collar_blk"
	var/writtenon = 0
	var/icon_previous_override
	special_handling = TRUE
	///Var for attack_self chain
	var/special_collar = FALSE
	default_worn_icon = INV_ACCESSORIES_DEF_ICON

//Forces different sprite sheet on equip
/obj/item/clothing/accessory/collar/on_materialize()
	icon_previous_override = icon_override
	. = ..()

/obj/item/clothing/accessory/collar/equipped() //Solution for race-specific sprites for an accessory which is also a suit. Suit icons break if you don't use icon override which then also overrides race-specific sprites.
	..()
	setUniqueSpeciesSprite()

/obj/item/clothing/accessory/collar/proc/setUniqueSpeciesSprite()
	var/mob/living/carbon/human/H = loc
	if(!istype(H) && istype(has_suit(), /obj/item/clothing) && ishuman(has_suit().loc))
		H = has_suit().loc
	if(sprite_sheets && istype(H) && H.species.get_bodytype(H) && (H.species.get_bodytype(H) in sprite_sheets))
		icon_override = sprite_sheets[H.species.get_bodytype(H)]
		update_clothing_icon()

/obj/item/clothing/accessory/collar/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	rel_set(src, nameof(has_suit), S)
	setUniqueSpeciesSprite()
	..(S, user)

/obj/item/clothing/accessory/collar/dropped(mob/user, equipping, slot)
	..()
	icon_override = icon_previous_override

/obj/item/clothing/accessory/collar/silver
	name = "Silver tag collar"
	desc = "A collar for your little pets... or the big ones."
	icon_state = "collar_blk"
	item_state = "collar_blk"
	overlay_state = "collar_blk"

/obj/item/clothing/accessory/collar/gold
	name = "Golden tag collar"
	desc = "A collar for your little pets... or the big ones."
	icon_state = "collar_gld"
	item_state = "collar_gld"
	overlay_state = "collar_gld"

/obj/item/clothing/accessory/collar/bell
	name = "Bell collar"
	desc = "A collar with a tiny bell hanging from it, purrfect furr kitties."
	icon_state = "collar_bell"
	item_state = "collar_bell"
	overlay_state = "collar_bell"
	var/jingled = 0

CAPABILITIES(/obj/item/clothing/accessory/collar/bell)
	op("bell_jinglebell_verb", menu(), label("Jingle Bell"), needs(carried()), then(PROC_REF(bell_jinglebell_verb)))

/// Old verb "Jingle Bell".
/obj/item/clothing/accessory/collar/bell/proc/bell_jinglebell_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(user)) return
	if(user.stat) return

	if(!jingled)
		user.audible_message("[user] jingles the [src]'s bell.", runemessage = "jingle")
		play_sfx(src, SFX_ITEMS_PICKUP_RING)
		jingled = 1
		after(src, 5 SECONDS, PROC_REF(jingledreset))
	return

/obj/item/clothing/accessory/collar/bell/proc/jingledreset()
	jingled = 0

/obj/item/clothing/accessory/collar/shock
	name = "Shock collar"
	desc = "A collar used to ease hungry predators."
	icon_state = "collar_shk0"
	item_state = "collar_shk"
	overlay_state = "collar_shk"
	var/on = FALSE // 0 for off, 1 for on, starts off to encourage people to set non-default frequencies and codes.
	var/frequency = AMAG_ELE_FREQ
	var/code = 2
	var/tmp/datum/radio_frequency/radio_connection
	special_collar = TRUE

/obj/item/clothing/accessory/collar/shock/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_CHAT)) // Makes it so you don't need to change the frequency off of default for it to work.

/obj/item/clothing/accessory/collar/shock/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_CHAT))

CAPABILITIES(/obj/item/clothing/accessory/collar/shock)
	op("controls", in_hand(), label("Open shock collar controls"), then(PROC_REF(shock_collar_controls_opened)))
	interface("ShockCollar")
	without("ui_open")
	op("freq", ui_act("freq", arg("freq", schema_text(4096))), then(PROC_REF(ui_act_freq)))
	op("code", ui_act("code", arg("code", num())), then(PROC_REF(ui_act_code)))
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("tag", ui_act("tag"), asks(/datum/prompt/text/shock_collar_ui_tag, step = "tag"), then(PROC_REF(ui_act_tag)))

/obj/item/clothing/accessory/collar/shock/proc/shock_collar_controls_opened(datum/act/op/A)
	if(!ishuman(A.actor))
		return OP_OK
	tgui_interact(A.actor)
	return OP_OK

/obj/item/clothing/accessory/collar/shock/tgui_static_data(mob/user)
	var/list/data = ..()

	data["freq_min"] = PUBLIC_LOW_FREQ
	data["freq_max"] = PUBLIC_HIGH_FREQ

	data["code_min"] = 0
	data["code_max"] = 100

	return data

/obj/item/clothing/accessory/collar/shock/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["on"] = on
	data["frequency"] = frequency
	data["code"] = code
	return data

/obj/item/clothing/accessory/collar/shock/proc/ui_act_freq(datum/act/op/A, freq)
	var/new_freq = sanitize_frequency(freq)
	set_frequency(new_freq)
	. = TRUE

/obj/item/clothing/accessory/collar/shock/proc/ui_act_code(datum/act/op/A, code_arg)
	code = CLAMP(code_arg, 1, 100)
	. = TRUE

/obj/item/clothing/accessory/collar/shock/proc/ui_act_power(datum/act/op/A)
	on = !on
	if(!istype(src, /obj/item/clothing/accessory/collar/shock/bluespace))
		icon_state = "collar_shk[on]"
	. = TRUE

/obj/item/clothing/accessory/collar/shock/proc/ui_act_tag(datum/act/op/A)
	return apply_ui_tag(A.actor, A.step_value("tag"))

/obj/item/clothing/accessory/collar/shock/proc/apply_ui_tag(mob/user, sanitized)
	if(!length(sanitized))
		to_chat(user, span_notice("[src]'s tag set to blank."))
		name = initial(name)
		desc = initial(desc)
	else
		to_chat(user, span_notice("[src]'s tag set to '[sanitized]'."))
		name = initial(name) + " ([sanitized])"
		desc = initial(desc) + " The tag says \"[sanitized]\"."
	. = TRUE

/datum/prompt/text/shock_collar_ui_tag
	title = "Set Tag"
	question = "Tag text?"
	max_len = MAX_NAME_LEN
	name_text = TRUE
	timeout = 0

/datum/prompt/text/shock_collar_ui_tag/normalize(given)
	return istext(given) ? strip_name_tokens(given) : given

/obj/item/clothing/accessory/collar/shock/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption != code)
		return

	if(on)
		var/mob/M = null
		if(ismob(loc))
			M = loc
		if(ismob(loc.loc))
			M = loc.loc // This is about as terse as I can make my solution to the whole 'collar won't work when attached as accessory' thing.
		if(!M)
			return
		to_chat(M,span_danger("You feel a sharp shock!"))
		fx_sparks(M, 3)
		M.status_at_least(STAT_WEAKENED, 10)

/obj/item/clothing/accessory/collar/spike
	name = "Spiked collar"
	desc = "A collar with spikes that look as sharp as your teeth."
	icon_state = "collar_spik"
	item_state = "collar_spik"
	overlay_state = "collar_spik"

/obj/item/clothing/accessory/collar/pink
	name = "Pink collar"
	desc = "This collar will make your pets look FA-BU-LOUS."
	icon_state = "collar_pnk"
	item_state = "collar_pnk"
	overlay_state = "collar_pnk"

/obj/item/clothing/accessory/collar/cowbell
	name = "cowbell collar"
	desc = "A collar for your little pets... or the big ones."
	icon_state = "collar_cowbell"
	item_state = "collar_cowbell_overlay"
	overlay_state = "collar_cowbell_overlay"

/obj/item/clothing/accessory/collar/collarplanet_earth
	name = "planet collar"
	desc = "A collar featuring a surprisingly detailed replica of a earth-like planet surrounded by a weak battery powered force shield. There is a button to turn it off."
	icon_state = "collarplanet_earth"
	item_state = "collarplanet_earth"
	overlay_state = "collarplanet_earth"

/obj/item/clothing/accessory/collar/holo
	name = "Holo-collar"
	desc = "An expensive holo-collar for the modern day pet."
	icon_state = "collar_holo"
	item_state = "collar_holo"
	overlay_state = "collar_holo"
	MATERIAL_BULK(MAT_STEEL, 50)

/obj/item/clothing/accessory/collar/holo/indigestible
	desc = "A special variety of the holo-collar that seems to be made of a very durable fabric that fits around the neck."
//Make indigestible
/obj/item/clothing/accessory/collar/holo/indigestible/digest_act(atom/movable/item_storage = null)
	return FALSE

EXTEND_INTERACTIONS(/obj/item/clothing/accessory/collar, \
	INTERACT_SELF(null, PROC_REF(collar_tag_self)), \
	INTERACT_ITEM(null, PROC_REF(collar_tag_item)), \
)

/// Old attack_self: set the tag. Returns FALSE where the old body returned nothing, so subtypes'
/// legacy attack_self bodies that ran after ..() still run.
/obj/item/clothing/accessory/collar/proc/collar_tag_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_collar)
		return FALSE
	if(istype(src,/obj/item/clothing/accessory/collar/holo))
		to_chat(user,span_notice("[name]'s interface is projected onto your hand."))
	else
		if(writtenon)
			to_chat(user,span_notice("You need a pen or a screwdriver to edit the tag on this collar."))
			return FALSE
		to_chat(user,span_notice("You adjust the [name]'s tag."))

	open_collar_tag(user, held, interaction)
	return TRUE

/obj/item/clothing/accessory/collar/proc/open_collar_tag(mob/user, obj/item/held, datum/interaction/interaction, tool_edit = FALSE, erasemethod, erasing, writemethod)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/text/collar_tag, PROC_REF(collar_tag_entered), answerer = user, captured_item = held, captured_interaction = interaction, item_expected = !isnull(held), interaction_expected = !isnull(interaction), original_client_ckey = original_client_ckey, tool_edit = tool_edit, erasemethod = erasemethod, erasing = erasing, writemethod = writemethod)

/obj/item/clothing/accessory/collar/proc/collar_tag_entered(datum/act/request/A)
	var/datum/prompt/text/collar_tag/request = A.request
	if(request.captures_gone())
		return
	if(!A.answer)
		if(request.outcome == REQ_CANCELLED && !isnull(request.value))
			if(!request.tool_edit && !special_collar && !istype(src, /obj/item/clothing/accessory/collar/holo) && writtenon)
				to_chat(request.user_value(), span_notice("You need a pen or a screwdriver to edit the tag on this collar."))
			SStgui.update_uis(src)
		return
	var/datum/result/result = safe_call(request.tool_edit ? PROC_REF(apply_tool_tag) : PROC_REF(apply_self_tag), A)
	if(!result.ok)
		stack_trace("Collar tag request: [result.error]")
	SStgui.update_uis(src)

/obj/item/clothing/accessory/collar/proc/apply_self_tag(datum/act/request/A)
	var/datum/prompt/text/collar_tag/request = A.request
	var/mob/user = request.user_value()
	if(special_collar)
		return FALSE
	if(istype(src, /obj/item/clothing/accessory/collar/holo))
		to_chat(user, span_notice("[name]'s interface is projected onto your hand."))
	else
		if(writtenon)
			to_chat(user, span_notice("You need a pen or a screwdriver to edit the tag on this collar."))
			return FALSE
		to_chat(user, span_notice("You adjust the [name]'s tag."))
	var/_answer_a1 = A.answer.value
	var/str = copytext(reject_bad_text(_answer_a1),1,MAX_NAME_LEN)

	if(!str || !length(str))
		to_chat(user,span_notice("[name]'s tag set to be blank."))
		name = initial(name)
		desc = initial(desc)
	else
		to_chat(user,span_notice("You set the [name]'s tag to '[str]'."))
		initialize_tag(str)
	return FALSE

/obj/item/clothing/accessory/collar/proc/initialize_tag(tag)
		name = initial(name) + " ([tag])"
		desc = initial(desc) + " \"[tag]\" has been engraved on the tag."
		writtenon = 1

/obj/item/clothing/accessory/collar/holo/initialize_tag(tag)
		..()
		desc = initial(desc) + " The tag says \"[tag]\"."

/// Old attackby: edit the tag with a pen or screwdriver. Never fell through to the clothing attackby.
/obj/item/clothing/accessory/collar/proc/collar_tag_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(src,/obj/item/clothing/accessory/collar/holo))
		return INTERACTION_HANDLED_PASS

	if(I.has_tool_quality(TOOL_SCREWDRIVER))
		update_collartag(user, I, "scratched out", "scratch out", "engraved")
		return INTERACTION_HANDLED_PASS

	if(istype(I,/obj/item/pen))
		update_collartag(user, I, "crossed out", "cross out", "written")
		return INTERACTION_HANDLED_PASS

	to_chat(user,span_notice("You need a pen or a screwdriver to edit the tag on this collar."))
	return INTERACTION_HANDLED_PASS

/obj/item/clothing/accessory/collar/proc/update_collartag(mob/user, obj/item/I, erasemethod, erasing, writemethod)
	if(!(istype(user.get_active_hand(),I)) || !(istype(user.get_inactive_hand(),src)) || (user.stat))
		return

	open_collar_tag(user, I, null, TRUE, erasemethod, erasing, writemethod)

/obj/item/clothing/accessory/collar/proc/apply_tool_tag(datum/act/request/A)
	var/datum/prompt/text/collar_tag/request = A.request
	var/mob/user = request.user_value()
	var/obj/item/I = request.captured_item
	var/erasemethod = request.erasemethod
	var/erasing = request.erasing
	var/writemethod = request.writemethod
	if(!(istype(user.get_active_hand(),I)) || !(istype(user.get_inactive_hand(),src)) || user.stat)
		return
	var/_answer_a2 = A.answer.value
	var/str = copytext(reject_bad_text(_answer_a2),1,MAX_NAME_LEN)

	if(!str || !length(str))
		if(!writtenon)
			to_chat(user,span_notice("You don't write anything."))
		else
			to_chat(user,span_notice("You [erasing] the words with the [I]."))
			name = initial(name)
			desc = initial(desc) + " The tag has had the words [erasemethod]."
	else
		if(!writtenon)
			to_chat(user,span_notice("You write '[str]' on the tag with the [I]."))
			name = initial(name) + " ([str])"
			desc = initial(desc) + " \"[str]\" has been [writemethod] on the tag."
			writtenon = 1
		else
			to_chat(user,span_notice("You [erasing] the words on the tag with the [I], and write '[str]'."))
			name = initial(name) + " ([str])"
			desc = initial(desc) + " Something has been [erasemethod] on the tag, and it now has \"[str]\" [writemethod] on it."

/datum/prompt/text/collar_tag
	question = "Tag text?"
	title = "Set tag"
	timeout = 0
	max_len = MAX_NAME_LEN
	name_text = TRUE
	encode = TRUE
	multiline = FALSE
	var/obj/item/captured_item
	var/datum/interaction/captured_interaction
	var/item_expected = FALSE
	var/interaction_expected = FALSE
	var/original_client_ckey
	var/tool_edit = FALSE
	var/erasemethod
	var/erasing
	var/writemethod

CAPABILITIES(/datum/prompt/text/collar_tag)
	ref_one(nameof(captured_item), /obj/item)
	ref_one(nameof(captured_interaction), /datum/interaction)

/datum/prompt/text/collar_tag/prepare(datum/act/A)
	. = ..()
	var/obj/item/item = captured_item
	var/datum/interaction/interaction = captured_interaction
	rel_clear(src, nameof(captured_item))
	rel_clear(src, nameof(captured_interaction))
	rel_set(src, nameof(captured_item), item)
	rel_set(src, nameof(captured_interaction), interaction)

/datum/prompt/text/collar_tag/proc/user_value()
	return original_client_ckey ? GLOB.directory[original_client_ckey] : answerer

/datum/prompt/text/collar_tag/proc/captures_gone()
	return QDELETED(answerer) || (original_client_ckey && !GLOB.directory[original_client_ckey]) || (item_expected && QDELETED(captured_item)) || (interaction_expected && QDELETED(captured_interaction))

/datum/prompt/text/collar_tag/recheck_extra()
	. = ..()
	if(.)
		return
	if(captures_gone())
		return "gone"
	var/obj/item/clothing/accessory/collar/collar = owner
	if(tool_edit)
		var/mob/user = user_value()
		if(!(istype(user.get_active_hand(), captured_item)) || !(istype(user.get_inactive_hand(), collar)) || user.stat)
			return "the collar and writing tool must stay in the same hands"
	else if(collar.special_collar || (!istype(collar, /obj/item/clothing/accessory/collar/holo) && collar.writtenon))
		return "the collar tag cannot be edited by hand"
	return null

//Size collar remote

/obj/item/clothing/accessory/collar/shock/bluespace
	name = "Bluespace collar"
	desc = "A collar that can manipulate the size of the wearer, and can be modified when unequiped."
	icon_state = "collar_size"
	item_state = "collar_size"
	overlay_state = "collar_size"
	/// Ratio (target_size / size_multiplier at activation) the collar itself applied.
	/// Stored as a ratio rather than an absolute snapshot so that restoring only
	/// undoes the collar's own contribution instead of clobbering whatever other
	/// size sources (potions, sizeguns, etc.) did to the wearer in the meantime.
	var/applied_ratio
	EXPIRY_DECLARE(last_activated)
	var/target_size = 1
	on = 1

/obj/item/clothing/accessory/collar/shock/bluespace/tgui_static_data(mob/user)
	var/list/data = ..()
	data["target_size_min"] = RESIZE_MINIMUM_DORMS
	data["target_size_max"] = RESIZE_MAXIMUM_DORMS
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["target_size"] = target_size
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/proc/ui_act_size(datum/act/op/A, size)
	var/mob/user = A.actor
	target_size = clamp((size/100), RESIZE_MINIMUM_DORMS, RESIZE_MAXIMUM_DORMS)
	to_chat(user, span_notice("You set the size to [target_size * 100]%"))
	if(target_size < RESIZE_MINIMUM || target_size > RESIZE_MAXIMUM)
		to_chat(user, span_notice("Note: Resizing limited to 25-200% automatically while outside dormatory areas.")) //hint that we clamp it in resize
	. = TRUE

/obj/item/clothing/accessory/collar/shock/bluespace/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption != code)
		return

	if(on)
		var/mob/M = null
		if(ismob(loc))
			M = loc
		if(ismob(loc.loc))
			M = loc.loc // This is about as terse as I can make my solution to the whole 'collar won't work when attached as accessory' thing.
		var/mob/living/carbon/human/H = M
		if(!istype(H))
			return
		if(!H.resizable)
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts but nothing happens to you.")), \
				MSG_OTHERS(span_warning("The space around %U% compresses for a moment but then nothing happens.")))
			return
		if(applied_ratio == null)
			if(!(ELAPSED_SINCE(src, last_activated, CLOCK_WORLD) > 10 SECONDS))
				to_chat(M, span_warning("\The [src] flickers. It seems to be recharging."))
				return
			EXPIRY_STAMP(src, last_activated, CLOCK_WORLD)
			applied_ratio = H.size_multiplier ? (target_size / H.size_multiplier) : 1
			H.resize(target_size, ignore_prefs = FALSE, allow_stripping = TRUE)		//In case someone else tries to put it on you.
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts as you change size!")), \
				MSG_OTHERS(span_warning("The space around %U% distorts as they change size!")))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			fx_sparks(M, 3)
		else
			EXPIRY_STAMP(src, last_activated, CLOCK_WORLD)
			H.resize(applied_ratio ? (H.size_multiplier / applied_ratio) : H.size_multiplier, ignore_prefs = FALSE, allow_stripping = TRUE)
			applied_ratio = null
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts as you return to your original size!")), \
				MSG_OTHERS(span_warning("The space around %U% distorts as they return to their original size!")))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			to_chat(M, span_warning("\The [src] flickers. It is now recharging and will be ready again in ten seconds."))
			fx_sparks(M, 3)
	return

/obj/item/clothing/accessory/collar/shock/bluespace/relaymove(mob/living/user,direction)
	return //For some reason equipping this item was triggering this proc, putting the wearer inside of the collars belly for some reason.

CAPABILITIES(/obj/item/clothing/accessory/collar/shock/bluespace)
	op("bluespace_collar_wire_signaler", item(/obj/item/assembly/signaler), label("Wire signaler"), then(PROC_REF(bluespace_collar_wire_signaler)))
	op("size", ui_act("size", arg("size", num())), then(PROC_REF(ui_act_size)))

/// Old attackby: wire a signaler in, making a modified collar.
/obj/item/clothing/accessory/collar/shock/bluespace/proc/bluespace_collar_wire_signaler(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/component = A.held
	to_chat(user, span_notice("You wire the signaler into the [src]."))
	user.drop_item()
	consume(component, user)
	var/turf/T = get_turf(src)
	new /obj/item/clothing/accessory/collar/shock/bluespace/modified(T)
	consume(src, user)
	return OP_PASS

/obj/item/clothing/accessory/collar/shock/bluespace/wrench_act(mob/user, obj/item/tool)
	to_chat(user, span_notice("You crack the bluespace crystal [src]."))
	new /obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning(get_turf(src))
	consume(src, user)
	return ITEM_INTERACT_SUCCESS

// modified bluespace collar where the size is controlled by the signaller.

/obj/item/clothing/accessory/collar/shock/bluespace/modified
	name = "Bluespace collar"
	desc = "A collar that can manipulate the size of the wearer, and can be modified when unequiped. It has a little reciever attached."
	icon_state = "collar_size_mod"
	item_state = "collar_size"
	overlay_state = "collar_size"
	target_size = 1
	on = 1

CAPABILITIES(/obj/item/clothing/accessory/collar/shock/bluespace/modified)
	op("modified_collar_signaler", item(/obj/item/assembly/signaler), priority(OP_PRIORITY_DEFAULT - 1), label("Wire signaler"), then(PROC_REF(modified_collar_signaler)))

/// Old attackby: already has a signaler.
/obj/item/clothing/accessory/collar/shock/bluespace/modified/proc/modified_collar_signaler(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("There is already a signaler wired to the [src]."))
	return OP_PASS

/obj/item/clothing/accessory/collar/shock/bluespace/modified/wrench_act(mob/user, obj/item/tool)
	var/collar_name = "[src]"
	var/turf/product_turf = get_turf(src)
	if(!consume(src, user))
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You crack the bluespace crystal [collar_name], the attached signaler disconnects."))
	new /obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning(product_turf)
	return ITEM_INTERACT_SUCCESS

/obj/item/clothing/accessory/collar/shock/bluespace/modified/ui_data(datum/act/eval/A)
	var/list/data = ..()
	var/list/merged_1 = ui_data_obj_item_clothing_accessory_collar_shock_bluespace_modified(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/clothing/accessory/collar/shock/bluespace/modified's window data.
/obj/item/clothing/accessory/collar/shock/bluespace/modified/proc/ui_data_obj_item_clothing_accessory_collar_shock_bluespace_modified(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["target_size"] = "code"
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/modified/ui_act_size(datum/act/op/A, size)
	return // no modifying size

/obj/item/clothing/accessory/collar/shock/bluespace/modified/receive_signal(datum/signal/signal)
	if(!signal)
		return
	target_size = (signal.encryption * 2)/100
	if(on)
		var/mob/M = null
		if(ismob(loc))
			M = loc
		if(ismob(loc.loc))
			M = loc.loc // This is about as terse as I can make my solution to the whole 'collar won't work when attached as accessory' thing.
		var/mob/living/carbon/human/H = M
		if(!istype(H))
			return
		if(!H.resizable)
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts but nothing happens to you.")), \
				MSG_OTHERS(span_warning("The space around %U% compresses for a moment but then nothing happens.")))
			return
		if (target_size < 0.26)
			act_message(H, null, MSG_SELF(span_notice("Your collar flickers, but is not powerful enough to shrink you that small.")), \
				MSG_OTHERS(span_warning("The collar on %U% flickers, but fizzles out.")))
			return
		if(applied_ratio == null)
			if(!(ELAPSED_SINCE(src, last_activated, CLOCK_WORLD) > 10 SECONDS))
				to_chat(M, span_warning("\The [src] flickers. It seems to be recharging."))
				return
			EXPIRY_STAMP(src, last_activated, CLOCK_WORLD)
			applied_ratio = H.size_multiplier ? (target_size / H.size_multiplier) : 1
			H.resize(target_size, ignore_prefs = FALSE, allow_stripping = TRUE)		//In case someone else tries to put it on you.
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts as you change size!")), \
				MSG_OTHERS(span_warning("The space around %U% distorts as they change size!")))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			fx_sparks(M, 3)
		else
			EXPIRY_STAMP(src, last_activated, CLOCK_WORLD)
			H.resize(applied_ratio ? (H.size_multiplier / applied_ratio) : H.size_multiplier, ignore_prefs = FALSE, allow_stripping = TRUE)
			applied_ratio = null
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts as you return to your original size!")), \
				MSG_OTHERS(span_warning("The space around %U% distorts as they return to their original size!")))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			to_chat(M, span_warning("\The [src] flickers. It is now recharging and will be ready again in ten seconds."))
			fx_sparks(M, 3)
	return

//bluespace collar malfunctioning (random size)

/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning
	name = "Bluespace collar"
	desc = "A collar that can manipulate the size of the wearer, and can be modified when unequiped. It has a crack on the crystal."
	icon_state = "collar_size_malf"
	item_state = "collar_size"
	overlay_state = "collar_size"
	target_size = 1
	on = 1
	var/currently_shrinking = 0

CAPABILITIES(/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning)
	op("malfunctioning_collar_signaler", item(/obj/item/assembly/signaler), priority(OP_PRIORITY_DEFAULT - 1), label("Wire signaler"), then(PROC_REF(malfunctioning_collar_signaler)))

/// Old attackby: the cracked crystal won't take a signaler.
/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning/proc/malfunctioning_collar_signaler(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("The signaler doesn't respond to the connection attempt [src]."))
	return OP_PASS

/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning/ui_data(datum/act/eval/A)
	var/list/data = ..()
	var/list/merged_1 = ui_data_obj_item_clothing_accessory_collar_shock_bluespace_malfunctioning(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning's window data.
/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning/proc/ui_data_obj_item_clothing_accessory_collar_shock_bluespace_malfunctioning(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["target_size"] = "locked"
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning/ui_act_size(datum/act/op/A, size)
	return // no modifying size

/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning/receive_signal(datum/signal/signal)
	if(!signal)
		return
	target_size =  (rand(25,200)) /100
	if(on)
		var/mob/M = null
		if(ismob(loc))
			M = loc
		if(ismob(loc.loc))
			M = loc.loc // This is about as terse as I can make my solution to the whole 'collar won't work when attached as accessory' thing.
		var/mob/living/carbon/human/H = M
		if(!istype(H))
			return
		if(!H.resizable)
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts but nothing happens to you.")), \
				MSG_OTHERS(span_warning("The space around %U% compresses for a moment but then nothing happens.")))
			return
		if (target_size < 0.25)
			act_message(H, null, MSG_SELF(span_notice("Your collar flickers, but is not powerful enough to shrink you that small.")), \
				MSG_OTHERS(span_warning("The collar on %U% flickers, but fizzles out.")))
			return
		if(currently_shrinking == 0)
			if(!(ELAPSED_SINCE(src, last_activated, CLOCK_WORLD) > 10 SECONDS))
				to_chat(M, span_warning("\The [src] flickers. It seems to be recharging."))
				return
			EXPIRY_STAMP(src, last_activated, CLOCK_WORLD)
			applied_ratio = H.size_multiplier ? (target_size / H.size_multiplier) : 1
			currently_shrinking = 1
			H.resize(target_size, ignore_prefs = FALSE, allow_stripping = TRUE)		//In case someone else tries to put it on you.
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts as you change size!")), \
				MSG_OTHERS(span_warning("The space around %U% distorts as they change size!")))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			fx_sparks(M, 3)
		else if(currently_shrinking == 1)
			if(applied_ratio == null)
				act_message(H, null, MSG_SELF(span_notice("The space around you distorts but stay the same size.")), \
					MSG_OTHERS(span_warning("The space around %U% twists and turns for a moment but then nothing happens.")))
				return
			EXPIRY_STAMP(src, last_activated, CLOCK_WORLD)
			H.resize(applied_ratio ? (H.size_multiplier / applied_ratio) : H.size_multiplier, ignore_prefs = FALSE, allow_stripping = TRUE)
			applied_ratio = null
			currently_shrinking = 0
			act_message(H, null, MSG_SELF(span_notice("The space around you distorts as you return to your original size!")), \
				MSG_OTHERS(span_warning("The space around %U% distorts as they return to their original size!")))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			to_chat(M, span_warning("\The [src] flickers. It is now recharging and will be ready again in ten seconds."))
			fx_sparks(M, 3)
	return

//Machete Holsters
/obj/item/clothing/accessory/holster/machete
	name = "machete sheath"
	desc = "A handsome synthetic leather sheath with matching belt."
	icon_state = "holster_machete"
	slot = ACCESSORY_SLOT_WEAPON
	concealed_holster = 0

//Medals

TYPE_TABLE(/obj/item/clothing/accessory/holster/machete, hold_spec, list(HOLD_ONLY(list(/obj/item/material/knife/machete, /obj/item/kinetic_crusher/machete))))

/obj/item/clothing/accessory/medal/silver/unity
	name = "medal of unity"
	desc = "A silver medal awarded to a group which has demonstrated exceptional teamwork to achieve a notable feat."

/obj/item/clothing/accessory/medal/silver/unity/tabiranth
	icon_state = "silverthree"
	item_state = "silverthree"
	overlay_state = "silverthree"
	desc = "A silver medal awarded to a group which has demonstrated exceptional teamwork to achieve a notable feat. This one has three bronze service stars, denoting that it has been awarded four times."

/obj/item/clothing/accessory/talon
	name = "Talon pin"
	desc = "A collectable enamel pin that resembles ITV Talon's ship logo."
	icon_state = "talon_pin"
	item_state = "talonpin"
	overlay_state = "talonpin"

//Casino Sentient Prize Collar

/obj/item/clothing/accessory/collar/casinosentientprize
	name = "disabled Sentient Prize Collar"
	desc = "A collar worn by sentient prizes registered to a SPASM. Although the red text on it shows its disconnected and nonfunctional."

	icon_state = "casinoslave"
	item_state = "casinoslave"
	overlay_state = "casinoslave"

	var/sentientprizename = null	//Name for system to put on collar description
	var/ownername = null	//Name for system to put on collar description
	var/sentientprizeckey = null	//Ckey for system to check who is the person and ensure no abuse of system or errors
	var/sentientprizeflavor = null	//Description to show on the SPASM
	var/sentientprizeooc = null		//OOC text to show on the SPASM
	var/sentientprizeitemtf = FALSE	//Whether the person opted in to allowing themselves to be item TF'd as a prize
	special_handling = TRUE
	special_collar = TRUE

//keeping self-use blank so people don't tag and reset collar status
CAPABILITIES(/obj/item/clothing/accessory/collar/casinosentientprize)
	op("swallow", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Interaction swallow"), then(TYPE_PROC_REF(/atom, op_swallow)))

/obj/item/clothing/accessory/collar/casinosentientprize_fake
	name = "Sentient Prize Collar"
	desc = "A collar worn by sentient prizes registered to a SPASM. This one has been disconnected from the system and is now an accessory!"

	icon_state = "casinoslave_owned"
	item_state = "casinoslave_owned"
	overlay_state = "casinoslave_owned"

//The gold trim from one of the qipaos, separated to an accessory to preserve the color
/obj/item/clothing/accessory/qipaogold
	name = "gold trim"
	desc = "Gold trim belonging to a qipao. Why would you remove this?"
	icon_state = "qipaogold"
	item_state = "qipaogold"
	overlay_state = "qipaogold"

//Antediluvian accessory set
/obj/item/clothing/accessory/antediluvian
	name = "antediluvian bracers"
	desc = "A pair of metal bracers with gold inlay. They're thin and light."
	icon_state = "antediluvian"
	item_state = "antediluvian"
	overlay_state = "antediluvian"
	body_parts_covered = ARMS

/obj/item/clothing/accessory/antediluvian/loincloth
	name = "antediluvian loincloth"
	desc = "A lengthy loincloth that drapes over the loins, obviously. It's quite long."
	icon_state = "antediluvian_loin"
	item_state = "antediluvian_loin"
	overlay_state = "antediluvian_loin"
	body_parts_covered = LOWER_TORSO

//The cloaks below belong to this _vr file but their sprites are contained in non-_vr icon files due to
//the way the poncho/cloak equipped() proc works. Sorry for the inconvenience
/obj/item/clothing/accessory/poncho/roles/cloak/antediluvian
	name = "antediluvian cloak"
	desc = "A regal looking cloak of white with specks of gold woven into the fabric."
	icon_state = "antediluvian_cloak"
	item_state = "antediluvian_cloak"

//Other clothes that I'm too lazy to port to Polaris
/obj/item/clothing/accessory/poncho/roles/cloak/chapel
	name = "bishop's cloak"
	desc = "An elaborate white and gold cloak."
	icon_state = "bishopcloak"
	item_state = "bishopcloak"

/obj/item/clothing/accessory/poncho/roles/cloak/chapel/alt
	name = "antibishop's cloak"
	desc = "An elaborate black and gold cloak. It looks just a little bit evil."
	icon_state = "blackbishopcloak"
	item_state = "blackbishopcloak"

/obj/item/clothing/accessory/poncho/roles/cloak/half
	name = "rough half cloak"
	desc = "The latest fashion innovations by the Nanotrasen Uniform & Fashion Department have provided the brilliant invention of slicing a regular cloak in half! All the ponce, half the cost!"
	icon_state = "roughcloak"
	item_state = "roughcloak"
	actions_types = list(/datum/action/item_action/adjust_cloak)
	special_handling = TRUE

/obj/item/clothing/accessory/poncho/roles/cloak/half/update_clothing_icon()
	. = ..()
	if(ismob(src.loc))
		var/mob/M = src.loc
		M.update_inv_wear_suit()

CAPABILITIES(/obj/item/clothing/accessory/poncho/roles/cloak/half)
	op("half_cloak_flip_self", in_hand(), label("Flip cloak"), then(PROC_REF(half_cloak_flip_self)))

/// Old attack_self.
/obj/item/clothing/accessory/poncho/roles/cloak/half/proc/half_cloak_flip_self(datum/act/op/A)
	var/mob/user = A.actor
	if(src.icon_state == initial(icon_state))
		src.icon_state = "[icon_state]_open"
		src.item_state = "[item_state]_open"
		flags_inv = HIDETIE|HIDEHOLSTER
		to_chat(user, "You flip the cloak over your shoulder.")
	else
		src.icon_state = initial(icon_state)
		src.item_state = initial(item_state)
		flags_inv = HIDEHOLSTER
		to_chat(user, "You pull the cloak over your shoulder.")
	update_clothing_icon()

/obj/item/clothing/accessory/poncho/roles/cloak/shoulder
	name = "shoulder cloak"
	desc = "A small cape that primarily covers the left shoulder. Might help you stand out more, not necessarily for the right reasons."
	icon_state = "cape_left"
	item_state = "cape_left"

/obj/item/clothing/accessory/poncho/roles/cloak/shoulder/right
	desc = "A small cape that primarily covers the right shoulder. It might look a tad cooler if it was longer."
	icon_state = "cape_right"
	item_state = "cape_right"

//Mantles
/obj/item/clothing/accessory/poncho/roles/cloak/mantle
	name = "shoulder mantle"
	desc = "Not a cloak and not really a cape either, but a silky fabric that rests on the neck and shoulders alone."
	icon_state = "mantle"
	item_state = "mantle"

//Boat cloaks
/obj/item/clothing/accessory/poncho/roles/cloak/boat
	name = "boat cloak"
	desc = "A cloak that might've been worn on boats once or twice. It's just a flappy cape otherwise."
	icon_state = "boatcloak"
	item_state = "boatcloak"

//Shrouds
/obj/item/clothing/accessory/poncho/roles/cloak/shroud
	name = "shroud cape"
	desc = "A sharp looking cape that covers more of one side than the other. Just a bit edgy."
	icon_state = "shroud"
	item_state = "shroud"

//Crop Jackets
/obj/item/clothing/accessory/poncho/roles/cloak/crop_jacket
	name = "white crop jacket"
	desc = "A cut down jacket that looks like it's light enough to wear on top of some other clothes. This one's in plain white, more or less."
	icon_state = "cropjacket_white"
	item_state = "cropjacket_white"

//Replikant patch & jacket

/obj/item/clothing/accessory/sleekpatch
	name = "sleek uniform patch"
	desc = "A somewhat old-fashioned embroidered patch of Nanotrasen's logo."
	icon_state = "sleekpatch"
	item_state = "sleekpatch"

/obj/item/clothing/accessory/poncho/roles/cloak/custom/gestaltjacket
	name = "sleek uniform jacket"
	desc = "Barely more than a pair of long stirrup sleeves joined by a turtleneck. Has decorative red accents."
	icon_state = "gestaltjacket"
	item_state = "gestaltjacket"

//Neo Ranger Poncho

/obj/item/clothing/accessory/poncho/roles/neo_ranger
	name = "ranger poncho"
	desc = "Aim for the Heart, Ramon."
	icon_state = "neo_ranger"
	item_state = "neo_ranger"
	actions_types = list(/datum/action/item_action/adjust_poncho)
	special_handling = TRUE

/obj/item/clothing/accessory/poncho/roles/neo_ranger/update_clothing_icon()
	. = ..()
	if(ismob(src.loc))
		var/mob/M = src.loc
		M.update_inv_wear_suit()

CAPABILITIES(/obj/item/clothing/accessory/poncho/roles/neo_ranger)
	op("neo_ranger_adjust_self", in_hand(), label("Adjust"), then(PROC_REF(neo_ranger_adjust_self)))

/// Old attack_self.
/obj/item/clothing/accessory/poncho/roles/neo_ranger/proc/neo_ranger_adjust_self(datum/act/op/A)
	var/mob/user = A.actor
	if(src.icon_state == initial(icon_state))
		src.icon_state = "[icon_state]_open"
		src.item_state = "[item_state]_open"
		flags_inv = HIDETIE|HIDEHOLSTER
		to_chat(user, "You adjust your poncho.")
	else
		src.icon_state = initial(icon_state)
		src.item_state = initial(item_state)
		flags_inv = HIDEHOLSTER
		to_chat(user, "You adjust your poncho.")
	update_clothing_icon()

/obj/item/clothing/accessory/belt
	name = "Thin Belt"
	desc = "A thin belt for holding your pants up."
	icon_state = "belt_thin"
	item_state = "belt_thin"
	slot_flags = SLOT_TIE | SLOT_BELT
	slot = ACCESSORY_SLOT_DECOR

/obj/item/clothing/accessory/belt/thick
	name = "Thick Belt"
	desc = "A thick belt for holding your pants up."
	icon_state = "belt_thick"
	item_state = "belt_thick"

/obj/item/clothing/accessory/belt/strap
	name = "Strap Belt"
	desc = "A belt with no bucklet for holding your pants up."
	icon_state = "belt_strap"
	item_state = "belt_strap"

/obj/item/clothing/accessory/belt/studded
	name = "Studded Belt"
	desc = "A studded belt for holding your pants up and looking cool."
	icon_state = "belt_studded"
	item_state = "belt_studded"

/obj/item/clothing/accessory/bunny_tail
	name = "Bunny Tail"
	desc = "A little fluffy bunny tail to spice up your outfit."
	icon_state = "bunny_tail"
	item_state = "bunny_tail"
	slot_flags = SLOT_TIE | SLOT_BELT
	slot = ACCESSORY_SLOT_DECOR

/obj/item/clothing/accessory/collar/casinoslave
	name = "a disabled Sentient Prize Collar"
	desc = "A collar worn by sentient prizes on the Golden Goose Casino. Although the red text on it shows its disconnected and nonfunctional."
	icon = 'icons/obj/clothing/ties_ch.dmi'
	icon_override = 'icons/mob/ties_ch.dmi'

	icon_state = "casinoslave"
	item_state = "casinoslave"
	overlay_state = "casinoslave"
	sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/accessory/mob_ch_teshari.dmi')

	var/ownername = null	//Name for system to put on collar description
	special_collar = TRUE

/obj/item/clothing/accessory/collar/holo/casinoslave_fake
	name = "a Sentient Prize Collar"
	desc = "A collar worn by sentient prizes on the Golden Goose Casino. This one has been disconnected from the system and is now an accessory!"
	icon = 'icons/obj/clothing/ties_ch.dmi'
	icon_override = 'icons/mob/ties_ch.dmi'

	icon_state = "casinoslave_owned"
	item_state = "casinoslave_owned"
	overlay_state = "casinoslave_owned"
	sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/accessory/mob_ch_teshari.dmi')

/obj/item/clothing/accessory/poncho/roles/cloak/blueshield
	name = "bodyguard's cloak"
	desc = "A dark blue cloak with silver trim around the neck. The mark of a professional bodyguard, and ideal for concealing holsters or other items."
	icon = 'icons/obj/clothing/ties_yw.dmi' //Moved to archive
	icon_state = "cloak_blueshield"
	icon_override = 'icons/mob/ties_yw.dmi' //Moved to archive
	item_state = "cloak_blueshield"

/obj/item/clothing/accessory/poncho/roles/cloak/blueshield/dropped(mob/user, equipping, slot) //makes the blueshield suit not kek when used by a teshari
	..()
	icon_override = 'icons/mob/ties_yw.dmi' //Moved to archive

/// The suit the tie may be attached to (a relation view: null once it is deleted).
/obj/item/clothing/accessory/proc/has_suit() as /obj/item/clothing
	return has_suit

/// the breathmask this refers to (a relation view: null once it is deleted).
/obj/item/clothing/accessory/gaiter/proc/breathmask() as /obj/item/clothing/mask/breath
	return breathmask

/// the radio_connection this refers to (a relation view: null once it is deleted).
/obj/item/clothing/accessory/collar/shock/proc/radio_connection() as /datum/radio_frequency
	return radio_connection
