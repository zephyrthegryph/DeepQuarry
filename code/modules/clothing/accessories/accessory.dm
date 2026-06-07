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
	var/obj/item/clothing/has_suit = null		// The suit the tie may be attached to
	var/image/inv_overlay = null				// Overlay used when attached to clothing.
	var/image/mob_overlay = null
	var/overlay_state = null
	var/punch_force	= 0							// added melee damage
	var/punch_damtype = BRUTE					// added melee damage type
	var/concealed_holster = 0
	var/list/on_rolled = list()					// Used when jumpsuit sleevels are rolled ("rolled" entry) or it's rolled down ("down"). Set to "none" to hide in those states.
	sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/accessory/mob_teshari.dmi') //Teshari can into webbing, too!
	drop_sound = 'sound/items/drop/accessory.ogg'
	pickup_sound = 'sound/items/pickup/accessory.ogg'

/obj/item/clothing/accessory/Destroy()
	on_removed()
	return ..()

/obj/item/clothing/accessory/proc/get_inv_overlay()
	if(!inv_overlay)
		var/tmp_icon_state = "[overlay_state? "[overlay_state]" : "[icon_state]"]"
		if(icon_override)
			if(icon_exists(icon_override, "[tmp_icon_state]_tie"))
				tmp_icon_state = "[tmp_icon_state]_tie"
			inv_overlay = image(icon = icon_override, icon_state = tmp_icon_state, dir = SOUTH)
		else
			inv_overlay = image(icon = INV_ACCESSORIES_DEF_ICON, icon_state = tmp_icon_state, dir = SOUTH)

		inv_overlay.color = src.color
		inv_overlay.appearance_flags = appearance_flags	// Stops has_suit's color from being multiplied onto the accessory
	return inv_overlay

/obj/item/clothing/accessory/proc/get_mob_overlay()
	if(!istype(loc,/obj/item/clothing/))	//don't need special handling if it's worn as normal item.
		return
	var/tmp_icon_state = "[overlay_state? "[overlay_state]" : "[icon_state]"]"
	if(ishuman(has_suit.loc))
		wearer = WEAKREF(has_suit.loc)
	else
		wearer = null

	var/mob/living/carbon/human/H = wearer?.resolve()
	if(!ishuman(H))
		return

	if(istype(loc,/obj/item/clothing/under))
		var/obj/item/clothing/under/C = loc
		if(on_rolled["down"] && C.rolled_down > 0)
			tmp_icon_state = on_rolled["down"]
		else if(on_rolled["rolled"] && C.rolled_sleeves > 0)
			tmp_icon_state = on_rolled["rolled"]

	if(icon_override)
		if(icon_exists(icon_override, "[tmp_icon_state]_mob"))
			tmp_icon_state = "[tmp_icon_state]_mob"
		mob_overlay = image("icon" = icon_override, "icon_state" = "[tmp_icon_state]")
	else if(H && LAZYACCESS(sprite_sheets, H.species.get_bodytype(H))) //Teshari can finally into webbing, too!
		mob_overlay = image("icon" = sprite_sheets[H.species.get_bodytype(H)], "icon_state" = "[tmp_icon_state]")
	else
		mob_overlay = image("icon" = INV_ACCESSORIES_DEF_ICON, "icon_state" = "[tmp_icon_state]")
	if(addblends)
		var/icon/base = new/icon("icon" = mob_overlay.icon, "icon_state" = mob_overlay.icon_state)
		var/addblend_icon = new/icon("icon" = mob_overlay.icon, "icon_state" = src.addblends)
		if(color)
			base.Blend(src.color, ICON_MULTIPLY)
		base.Blend(addblend_icon, ICON_ADD)
		mob_overlay = image(base)
	else
		mob_overlay.color = src.color

	mob_overlay.appearance_flags = appearance_flags	// Stops has_suit's color from being multiplied onto the accessory
	return mob_overlay

//when user attached an accessory to S
/obj/item/clothing/accessory/proc/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	has_suit = S
	src.forceMove(S)
	has_suit.add_overlay(get_inv_overlay())

	has_suit.force += force
	if(istype(S,/obj/item/clothing/gloves))
		var/obj/item/clothing/gloves/has_gloves = S
		has_gloves.punch_force = has_gloves.punch_force + punch_force

	if(user)
		to_chat(user, span_notice("You attach \the [src] to \the [has_suit]."))
		add_fingerprint(user)

/obj/item/clothing/accessory/proc/on_removed(mob/user)
	if(!has_suit)
		return
	has_suit.cut_overlay(get_inv_overlay())
	has_suit.force = initial(has_suit.force)
	if(istype(has_suit,/obj/item/clothing/gloves))
		var/obj/item/clothing/gloves/has_gloves = has_suit
		has_gloves.punch_force = initial(has_gloves.punch_force)
	has_suit = null
	if(QDELETED(src))
		return
	if(user && !issilicon(user))
		user.put_in_hands(src)
		add_fingerprint(user)
	else if(get_turf(src))		//We actually exist in space
		forceMove(get_turf(src))

//default attackby behaviour
/obj/item/clothing/accessory/attackby(obj/item/I, mob/user)
	..()

//default attack_hand behaviour
/obj/item/clothing/accessory/attack_hand(mob/user)
	if(has_suit)
		return	//we aren't an object on the ground so don't call parent
	..()

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

/obj/item/clothing/accessory/maid_arms
	name = "maid arm covers"
	desc = "Cylindrical looking tubes that go over your arms, weird."
	slot_flags = SLOT_OCLOTHING | SLOT_GLOVES | SLOT_TIE
	body_parts_covered = ARMS
	heat_protection = ARMS
	cold_protection = ARMS
	description_info = "Wearable as gloves, or attachable to uniforms. May visually conflict with actual gloves when attached to uniforms. Caveat emptor."
	icon_state = "maid_arms"

/obj/item/clothing/accessory/stethoscope
	name = "stethoscope"
	desc = "An outdated medical apparatus for listening to the sounds of the human body. It also makes you look like you know what you're doing."
	icon_state = "stethoscope"
	slot = ACCESSORY_SLOT_TIE

/obj/item/clothing/accessory/stethoscope/do_surgery(mob/living/carbon/human/M, mob/living/user)
	if(user.a_intent != I_HELP) //in case it is ever used as a surgery tool
		return ..()
	attack(M, user) //default surgery behaviour is just to scan as usual
	return 1

/obj/item/clothing/accessory/stethoscope/attack(mob/living/carbon/human/M, mob/living/user)
	if(ishuman(M) && isliving(user))
		if(user.a_intent == I_HELP)
			var/body_part = parse_zone(user.zone_sel.selecting)

			//Chomp Edit start
			var/message_holder	//Holds pervy message
			var/message_holder2	//Hods the nutrition related message.
			var/beat_size = ""	//Small prey = quiet
			//Chomp Edit end

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
							for(var/belly in M.vore_organs) //Pervy edit. //CHOMPEdit Start
								var/obj/belly/B = belly
								for(var/mob/living/carbon/human/H in B)
									if(H.size_multiplier < 0.5)
										beat_size = pick("quiet ", "hushed " ,"low " ,"hushed ")
									message_holder = pick("You can hear disparate heartbeats as well.", "You can hear a different [beat_size]heartbeat too.", "It sounds like there is more than one heartbeat." ,"You can pick up a [beat_size]heatbeat along with everything else.")
							if(M.nutrition > 900)	//dead
								message_holder2 = pick("Your listening is troubled by the occasional deep groan of their body.", "There is some moderate bubbling in the background.", "They seem to have a healthy metabolism as well.") //CHOMPEdit End

							var/obj/item/organ/internal/heart/heart = M.internal_organs_by_name[O_HEART]
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

							var/obj/item/organ/internal/lungs/L = M.internal_organs_by_name[O_LUNGS]
							if(!L || M.losebreath)
								sound += span_warning(" and no respiration")
							else if(M.is_lung_ruptured() || M.getOxyLoss() > 50)
								sound += span_warning(" and [pick("wheezing","gurgling")] sounds")
							else
								sound += " and healthy respiration"
						//GROIN
						//ORGANS INVENTORY: Appendix, Intestines, Kidneys, Liver, Spleen, Stomach.
						//Of these, the Intestines, Stomach, Liver, and Kidneys make noise.
						if(BP_GROIN)
							var/obj/item/organ/internal/intestine/intestine = M.internal_organs_by_name[O_INTESTINE]
							var/obj/item/organ/internal/stomach/stomach = M.internal_organs_by_name[O_STOMACH]
							var/obj/item/organ/internal/kidneys/kidneys = M.internal_organs_by_name[O_KIDNEYS]
							var/obj/item/organ/internal/liver/liver = M.internal_organs_by_name[O_LIVER]
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

				user.visible_message("[user] places [src] against [M]'s [body_part] and listens attentively.", "You place [src] against [their] [body_part]. You [sound_strength] [sound]. [message_holder] [message_holder2]") //Chomp edit. ([message holder] & [message_holder2])
				return ITEM_INTERACT_SUCCESS

	return ..(M,user)

//Medals
/obj/item/clothing/accessory/medal
	name = "bronze medal"
	desc = "A bronze medal."
	icon_state = "bronze"
	slot = ACCESSORY_SLOT_MEDAL
	drop_sound = 'sound/items/drop/accessory.ogg'
	pickup_sound = 'sound/items/pickup/accessory.ogg'

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
	species_restricted = list(SPECIES_TESHARI)

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

/obj/item/clothing/accessory/gaiter/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/clothing/mask/breath))
		to_chat(user, span_notice("You tuck [I] behind [src]."))
		breathmask = I
		breath_masked = TRUE
		user.drop_from_inventory(I, drop_location())
		I.forceMove(src)
		item_flags &= ~FLEXIBLEMATERIAL
	. = ..()

/obj/item/clothing/accessory/gaiter/click_alt(mob/user)
	. = ..()
	if(breath_masked && breathmask)
		to_chat(user, span_notice("You pull [breathmask] out from behind [src], and it drops to your feet."))
		breathmask.forceMove(drop_location())
		breathmask = null
		breath_masked = FALSE
		item_flags &= ~AIRTIGHT
		item_flags |= FLEXIBLEMATERIAL

/obj/item/clothing/accessory/gaiter/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
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
	qdel(mob_overlay) // we're gonna need to refresh these
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


// === merged from accessory_vr.dm during hard-fork de-suffix (verified no override-order change) ===
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
/obj/item/clothing/accessory/choker/Initialize(mapload)
	. = ..()
	icon_previous_override = icon_override

/obj/item/clothing/accessory/choker/equipped() //Solution for race-specific sprites for an accessory which is also a suit. Suit icons break if you don't use icon override which then also overrides race-specific sprites.
	..()
	setUniqueSpeciesSprite()

/obj/item/clothing/accessory/choker/proc/setUniqueSpeciesSprite()
	var/mob/living/carbon/human/H = loc
	if(!istype(H) && istype(has_suit) && ishuman(has_suit.loc))
		H = has_suit.loc
	if(sprite_sheets && istype(H) && H.species.get_bodytype(H) && (H.species.get_bodytype(H) in sprite_sheets))
		icon_override = sprite_sheets[H.species.get_bodytype(H)]
		update_clothing_icon()

/obj/item/clothing/accessory/choker/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	has_suit = S
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
/obj/item/clothing/accessory/collar/Initialize(mapload)
	. = ..()
	icon_previous_override = icon_override

/obj/item/clothing/accessory/collar/equipped() //Solution for race-specific sprites for an accessory which is also a suit. Suit icons break if you don't use icon override which then also overrides race-specific sprites.
	..()
	setUniqueSpeciesSprite()

/obj/item/clothing/accessory/collar/proc/setUniqueSpeciesSprite()
	var/mob/living/carbon/human/H = loc
	if(!istype(H) && istype(has_suit) && ishuman(has_suit.loc))
		H = has_suit.loc
	if(sprite_sheets && istype(H) && H.species.get_bodytype(H) && (H.species.get_bodytype(H) in sprite_sheets))
		icon_override = sprite_sheets[H.species.get_bodytype(H)]
		update_clothing_icon()

/obj/item/clothing/accessory/collar/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	has_suit = S
	setUniqueSpeciesSprite()
	..(S, user)

/obj/item/clothing/accessory/collar/dropped(mob/user, equipping, slot)
	..()
	icon_override = icon_previous_override

//ywedit start. forces different sprite sheet on equip
/obj/item/clothing/accessory/collar/Initialize(mapload)
	. = ..()
	icon_previous_override = icon_override

/obj/item/clothing/accessory/collar/equipped() //Solution for race-specific sprites for an accessory which is also a suit. Suit icons break if you don't use icon override which then also overrides race-specific sprites.
	..()
	setUniqueSpeciesSprite()

/obj/item/clothing/accessory/collar/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	has_suit = S
	setUniqueSpeciesSprite()
	..(S, user)

/obj/item/clothing/accessory/collar/dropped(mob/user)
	..()
	icon_override = icon_previous_override
//ywedit end

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

/obj/item/clothing/accessory/collar/bell/verb/jinglebell()
	set name = "Jingle Bell"
	set category = "Object"
	set src in usr
	if(!isliving(usr)) return
	if(usr.stat) return

	if(!jingled)
		usr.audible_message("[usr] jingles the [src]'s bell.", runemessage = "jingle")
		playsound(src, 'sound/items/pickup/ring.ogg', 50, 1)
		jingled = 1
		addtimer(CALLBACK(src, PROC_REF(jingledreset)), 50)
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
	var/datum/radio_frequency/radio_connection
	special_collar = TRUE

/obj/item/clothing/accessory/collar/shock/Initialize(mapload)
	. = ..()
	radio_connection = SSradio.add_object(src, frequency, RADIO_CHAT) // Makes it so you don't need to change the frequency off of default for it to work.

/obj/item/clothing/accessory/collar/shock/Destroy() //Clean up your toys when you're done.
	SSradio.remove_object(src, frequency)
	radio_connection = null //Don't delete this, this is a shared object.
	return ..()

/obj/item/clothing/accessory/collar/shock/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = SSradio.add_object(src, frequency, RADIO_CHAT)

/obj/item/clothing/accessory/collar/shock/attack_self(mob/user, flag1)
	. = ..(user)
	if(.)
		return TRUE
	if(!ishuman(user))
		return
	tgui_interact(user)

/obj/item/clothing/accessory/collar/shock/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ShockCollar", name)
		ui.open()

/obj/item/clothing/accessory/collar/shock/tgui_static_data(mob/user)
	var/list/data = ..()

	data["freq_min"] = PUBLIC_LOW_FREQ
	data["freq_max"] = PUBLIC_HIGH_FREQ

	data["code_min"] = 0
	data["code_max"] = 100

	return data

/obj/item/clothing/accessory/collar/shock/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["on"] = on
	data["frequency"] = frequency
	data["code"] = code

	return data

/obj/item/clothing/accessory/collar/shock/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("freq")
			var/new_freq = sanitize_frequency(params["freq"])
			set_frequency(new_freq)
			. = TRUE
		if("code")
			code = CLAMP(text2num(params["code"]), 1, 100)
			. = TRUE
		if("power")
			on = !on
			if(!istype(src, /obj/item/clothing/accessory/collar/shock/bluespace))
				icon_state = "collar_shk[on]"
			. = TRUE
		if("tag")
			var/sanitized = tgui_input_text(ui.user, "Tag text?", "Set Tag", "", MAX_NAME_LEN, encode = TRUE)
			if(isnull(sanitized))
				return

			if(!length(sanitized))
				to_chat(ui.user, span_notice("[src]'s tag set to blank."))
				name = initial(name)
				desc = initial(desc)
			else
				to_chat(ui.user, span_notice("[src]'s tag set to '[sanitized]'."))
				name = initial(name) + " ([sanitized])"
				desc = initial(desc) + " The tag says \"[sanitized]\"."
			. = TRUE

/obj/item/clothing/accessory/collar/shock/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption != code)
		return

	if(on)
		var/mob/M = null
		if(ismob(loc))
			M = loc
		if(ismob(loc.loc))
			M = loc.loc // This is about as terse as I can make my solution to the whole 'collar won't work when attached as accessory' thing.
		to_chat(M,span_danger("You feel a sharp shock!"))
		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		s.set_up(3, 1, M)
		s.start()
		M.Weaken(10)

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
	matter = list(MAT_STEEL = 50)

/obj/item/clothing/accessory/collar/holo/indigestible
	desc = "A special variety of the holo-collar that seems to be made of a very durable fabric that fits around the neck."
//Make indigestible
/obj/item/clothing/accessory/collar/holo/indigestible/digest_act(atom/movable/item_storage = null)
	return FALSE

/obj/item/clothing/accessory/collar/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(special_collar)
		return FALSE
	if(istype(src,/obj/item/clothing/accessory/collar/holo))
		to_chat(user,span_notice("[name]'s interface is projected onto your hand."))
	else
		if(writtenon)
			to_chat(user,span_notice("You need a pen or a screwdriver to edit the tag on this collar."))
			return
		to_chat(user,span_notice("You adjust the [name]'s tag."))

	var/str = copytext(reject_bad_text(tgui_input_text(user,"Tag text?","Set tag","",MAX_NAME_LEN)),1,MAX_NAME_LEN)

	if(!str || !length(str))
		to_chat(user,span_notice("[name]'s tag set to be blank."))
		name = initial(name)
		desc = initial(desc)
	else
		to_chat(user,span_notice("You set the [name]'s tag to '[str]'."))
		initialize_tag(str)

/obj/item/clothing/accessory/collar/proc/initialize_tag(tag)
		name = initial(name) + " ([tag])"
		desc = initial(desc) + " \"[tag]\" has been engraved on the tag."
		writtenon = 1

/obj/item/clothing/accessory/collar/holo/initialize_tag(tag)
		..()
		desc = initial(desc) + " The tag says \"[tag]\"."

/obj/item/clothing/accessory/collar/attackby(obj/item/I, mob/user)
	if(istype(src,/obj/item/clothing/accessory/collar/holo))
		return

	if(istype(I,/obj/item/tool/screwdriver))
		update_collartag(user, I, "scratched out", "scratch out", "engraved")
		return

	if(istype(I,/obj/item/pen))
		update_collartag(user, I, "crossed out", "cross out", "written")
		return

	to_chat(user,span_notice("You need a pen or a screwdriver to edit the tag on this collar."))

/obj/item/clothing/accessory/collar/proc/update_collartag(mob/user, obj/item/I, erasemethod, erasing, writemethod)
	if(!(istype(user.get_active_hand(),I)) || !(istype(user.get_inactive_hand(),src)) || (user.stat))
		return

	var/str = copytext(reject_bad_text(tgui_input_text(user,"Tag text?","Set tag","",MAX_NAME_LEN)),1,MAX_NAME_LEN)

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

//Size collar remote

/obj/item/clothing/accessory/collar/shock/bluespace
	name = "Bluespace collar"
	desc = "A collar that can manipulate the size of the wearer, and can be modified when unequiped."
	icon_state = "collar_size"
	item_state = "collar_size"
	overlay_state = "collar_size"
	var/original_size
	var/last_activated
	var/target_size = 1
	on = 1

/obj/item/clothing/accessory/collar/shock/bluespace/tgui_static_data(mob/user)
	var/list/data = ..()
	data["target_size_min"] = RESIZE_MINIMUM_DORMS
	data["target_size_max"] = RESIZE_MAXIMUM_DORMS
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()
	data["target_size"] = target_size
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("size")
			target_size = clamp((params["size"]/100), RESIZE_MINIMUM_DORMS, RESIZE_MAXIMUM_DORMS)
			to_chat(ui.user, span_notice("You set the size to [target_size * 100]%"))
			if(target_size < RESIZE_MINIMUM || target_size > RESIZE_MAXIMUM)
				to_chat(ui.user, span_notice("Note: Resizing limited to 25-200% automatically while outside dormatory areas.")) //hint that we clamp it in resize
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
		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		if(!H.resizable)
			H.visible_message(span_warning("The space around [H] compresses for a moment but then nothing happens."),span_notice("The space around you distorts but nothing happens to you."))
			return
		if(H.size_multiplier != target_size)
			if(!(world.time - last_activated > 10 SECONDS))
				to_chat(M, span_warning("\The [src] flickers. It seems to be recharging."))
				return
			last_activated = world.time
			original_size = H.size_multiplier
			H.resize(target_size, ignore_prefs = FALSE, allow_stripping = TRUE)		//In case someone else tries to put it on you.
			H.visible_message(span_warning("The space around [H] distorts as they change size!"),span_notice("The space around you distorts as you change size!"))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			s.set_up(3, 1, M)
			s.start()
		else if(H.size_multiplier == target_size)
			if(original_size == null)
				H.visible_message(span_warning("The space around [H] twists and turns for a moment but then nothing happens."),span_notice("The space around you distorts but stay the same size."))
				return
			last_activated = world.time
			H.resize(original_size, ignore_prefs = FALSE, allow_stripping = TRUE)
			original_size = null
			H.visible_message(span_warning("The space around [H] distorts as they return to their original size!"),span_notice("The space around you distorts as you return to your original size!"))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			to_chat(M, span_warning("\The [src] flickers. It is now recharging and will be ready again in ten seconds."))
			s.set_up(3, 1, M)
			s.start()
	return

/obj/item/clothing/accessory/collar/shock/bluespace/relaymove(mob/living/user,direction)
	return //For some reason equipping this item was triggering this proc, putting the wearer inside of the collars belly for some reason.

/obj/item/clothing/accessory/collar/shock/bluespace/attackby(obj/item/component, mob/user as mob)
	if (component.has_tool_quality(TOOL_WRENCH))
		to_chat(user, span_notice("You crack the bluespace crystal [src]."))
		var/turf/T = get_turf(src)
		new /obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning(T)
		user.drop_from_inventory(src)
		qdel(src)
		return
	if (!istype(component,/obj/item/assembly/signaler))
		..()
		return
	to_chat(user, span_notice("You wire the signaler into the [src]."))
	user.drop_item()
	qdel(component)
	var/turf/T = get_turf(src)
	new /obj/item/clothing/accessory/collar/shock/bluespace/modified(T)
	user.drop_from_inventory(src)
	qdel(src)
	return

// modified bluespace collar where the size is controlled by the signaller.

/obj/item/clothing/accessory/collar/shock/bluespace/modified
	name = "Bluespace collar"
	desc = "A collar that can manipulate the size of the wearer, and can be modified when unequiped. It has a little reciever attached."
	icon_state = "collar_size_mod"
	item_state = "collar_size"
	overlay_state = "collar_size"
	target_size = 1
	on = 1

/obj/item/clothing/accessory/collar/shock/bluespace/modified/attackby(obj/item/component, mob/user as mob)
	if (component.has_tool_quality(TOOL_WRENCH))
		to_chat(user, span_notice("You crack the bluespace crystal [src], the attached signaler disconnects."))
		var/turf/T = get_turf(src)
		new /obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning(T)
		user.drop_from_inventory(src)
		qdel(src)
		return
	if (!istype(component,/obj/item/assembly/signaler))
		..()
		return
	to_chat(user, span_notice("There is already a signaler wired to the [src]."))
	return

/obj/item/clothing/accessory/collar/shock/bluespace/modified/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()
	data["target_size"] = "code"
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/modified/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(action == "size")
		return // no modifying size
	. = ..()

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
		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		if(!H.resizable)
			H.visible_message(span_warning("The space around [H] compresses for a moment but then nothing happens."),span_notice("The space around you distorts but nothing happens to you."))
			return
		if (target_size < 0.26)
			H.visible_message(span_warning("The collar on [H] flickers, but fizzles out."),span_notice("Your collar flickers, but is not powerful enough to shrink you that small."))
			return
		if(H.size_multiplier != target_size)
			if(!(world.time - last_activated > 10 SECONDS))
				to_chat(M, span_warning("\The [src] flickers. It seems to be recharging."))
				return
			last_activated = world.time
			original_size = H.size_multiplier
			H.resize(target_size, ignore_prefs = FALSE, allow_stripping = TRUE)		//In case someone else tries to put it on you.
			H.visible_message(span_warning("The space around [H] distorts as they change size!"),span_notice("The space around you distorts as you change size!"))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			s.set_up(3, 1, M)
			s.start()
		else if(H.size_multiplier == target_size)
			if(original_size == null)
				H.visible_message(span_warning("The space around [H] twists and turns for a moment but then nothing happens."),span_notice("The space around you distorts but stay the same size."))
				return
			last_activated = world.time
			H.resize(original_size, ignore_prefs = FALSE, allow_stripping = TRUE)
			original_size = null
			H.visible_message(span_warning("The space around [H] distorts as they return to their original size!"),span_notice("The space around you distorts as you return to your original size!"))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			to_chat(M, span_warning("\The [src] flickers. It is now recharging and will be ready again in ten seconds."))
			s.set_up(3, 1, M)
			s.start()
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

/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning/attackby(obj/item/component, mob/user as mob)
	if (!istype(component,/obj/item/assembly/signaler))
		..()
		return
	to_chat(user, span_notice("The signaler doesn't respond to the connection attempt [src]."))
	return

/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()
	data["target_size"] = "locked"
	return data

/obj/item/clothing/accessory/collar/shock/bluespace/malfunctioning/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(action == "size")
		return // no modifying size
	. = ..()

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
		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		if(!H.resizable)
			H.visible_message(span_warning("The space around [H] compresses for a moment but then nothing happens."),span_notice("The space around you distorts but nothing happens to you."))
			return
		if (target_size < 0.25)
			H.visible_message(span_warning("The collar on [H] flickers, but fizzles out."),span_notice("Your collar flickers, but is not powerful enough to shrink you that small."))
			return
		if(currently_shrinking == 0)
			if(!(world.time - last_activated > 10 SECONDS))
				to_chat(M, span_warning("\The [src] flickers. It seems to be recharging."))
				return
			last_activated = world.time
			original_size = H.size_multiplier
			currently_shrinking = 1
			H.resize(target_size, ignore_prefs = FALSE, allow_stripping = TRUE)		//In case someone else tries to put it on you.
			H.visible_message(span_warning("The space around [H] distorts as they change size!"),span_notice("The space around you distorts as you change size!"))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			s.set_up(3, 1, M)
			s.start()
		else if(currently_shrinking == 1)
			if(original_size == null)
				H.visible_message(span_warning("The space around [H] twists and turns for a moment but then nothing happens."),span_notice("The space around you distorts but stay the same size."))
				return
			last_activated = world.time
			H.resize(original_size, ignore_prefs = FALSE, allow_stripping = TRUE)
			original_size = null
			currently_shrinking = 0
			H.visible_message(span_warning("The space around [H] distorts as they return to their original size!"),span_notice("The space around you distorts as you return to your original size!"))
			log_admin("Admin [key_name(M)]'s size was altered by a bluespace collar.")
			to_chat(M, span_warning("\The [src] flickers. It is now recharging and will be ready again in ten seconds."))
			s.set_up(3, 1, M)
			s.start()
	return

//Machete Holsters
/obj/item/clothing/accessory/holster/machete
	name = "machete sheath"
	desc = "A handsome synthetic leather sheath with matching belt."
	icon_state = "holster_machete"
	slot = ACCESSORY_SLOT_WEAPON
	concealed_holster = 0
	can_hold = list(/obj/item/material/knife/machete, /obj/item/kinetic_crusher/machete)
	//sound_in = 'sound/effects/holster/sheathin.ogg'
	//sound_out = 'sound/effects/holster/sheathout.ogg'

//Medals

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

/obj/item/clothing/accessory/collar/casinosentientprize/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	return TRUE
	//keeping it blank so people don't tag and reset collar status

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

/obj/item/clothing/accessory/poncho/roles/cloak/half/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
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

/obj/item/clothing/accessory/poncho/roles/neo_ranger/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
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


// === merged from accessory_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/clothing/accessory/collar/casinoslave
	name = "a disabled Sentient Prize Collar"
	desc = "A collar worn by sentient prizes on the Golden Goose Casino. Although the red text on it shows its disconnected and nonfunctional."
	icon = 'icons/obj/clothing/ties_ch.dmi'
	icon_override = 'icons/mob/ties_ch.dmi'

	icon_state = "casinoslave"
	item_state = "casinoslave"
	overlay_state = "casinoslave"
	sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/accessory/mob_ch_teshari.dmi')

	var/slavename = null	//Name for system to put on collar description
	var/ownername = null	//Name for system to put on collar description
	var/slaveckey = null	//Ckey for system to check who is the person and ensure no abuse of system or errors
	var/slaveflavor = null	//Description to show on the SPASM
	var/slaveooc = null		//OOC text to show on the SPASM
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
