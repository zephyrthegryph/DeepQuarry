/obj/item/clothing/accessory
	name = "tie"
	desc = "A neosilk clip-on tie."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "bluetie"
	item_state_slots = list(slot_r_hand_str = "", slot_l_hand_str = "")
	appearance_flags = RESET_COLOR	// Stops has_suit's color from being multiplied onto the accessory
	w_class = ITEMSIZE_SMALL
	var/glove_level = 1							// What 'level' the accessory is on if equipped on the gloveslot. Lower = things can be put on top of it.
	var/slot = ACCESSORY_SLOT_DECOR
	var/can_remove = TRUE						// Can it be taken off once attached?
	var/tmp/obj/item/clothing/has_suit	// The suit the tie may be attached to
	var/overlay_state = null
	var/punch_force	= 0							// added melee damage
	var/punch_injury_kind						// what punches inflict (INJURY_*); null = the punch's own kind
	var/concealed_holster = 0
	var/list/on_rolled							// Lazylist. Used when jumpsuit sleeves are rolled ("rolled" entry) or it's rolled down ("down"). Set to "none" to hide in those states.
	sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/accessory/mob_teshari.dmi') //Teshari can into webbing, too!

// an attached accessory is removed from its clothing.
/obj/item/clothing/accessory/on_destroy(force)
	on_removed()
	..()

// Delegate to the global clothing_appearance_handler singleton.
// Pure: built from the accessory's inputs on every draw of the clothing it is attached to, not stored.
/obj/item/clothing/accessory/proc/get_inv_overlay()
	return GLOB.clothing_appearance_handler.build_inv_overlay(src)

/// The on-mob overlay. Pure: built from the accessory's inputs on every draw and not stored.
/obj/item/clothing/accessory/proc/get_mob_overlay()
	if(!istype(loc, /obj/item/clothing))
		return null
	if(!ishuman(has_suit()?.loc))
		return null
	return GLOB.clothing_appearance_handler.build_mob_overlay(src)

//when user attached an accessory to S
/obj/item/clothing/accessory/proc/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	rel_set(src, nameof(has_suit), S)
	src.forceMove(S)
	has_suit().set_force(combat_of(has_suit()).force + (combat_of(src).force))
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
	old_suit.set_force(combat_of_type(old_suit.type).force)
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
	ref_one(nameof(has_suit), /obj/item/clothing)
	configure(item_worn(slots = SLOT_TIE))
	configure(item_sounds(drop = SFX_ITEMS_DROP_ACCESSORY, pickup = SFX_ITEMS_PICKUP_ACCESSORY))
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
	icon_state = "maid_arms"

CAPABILITIES(/obj/item/clothing/accessory/maid_arms)
	configure(item_worn(slots = SLOT_OCLOTHING | SLOT_GLOVES | SLOT_TIE, covers = ARMS))
	configure(item_protection(heat_parts = ARMS, cold_parts = ARMS))

//Medals
/obj/item/clothing/accessory/medal
	name = "bronze medal"
	desc = "A bronze medal."
	icon_state = "bronze"
	slot = ACCESSORY_SLOT_MEDAL

CAPABILITIES(/obj/item/clothing/accessory/medal)
	configure(item_sounds(drop = SFX_ITEMS_DROP_ACCESSORY, pickup = SFX_ITEMS_PICKUP_ACCESSORY))

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

//Machete Holsters
/obj/item/clothing/accessory/holster/machete
	name = "machete sheath"
	desc = "A handsome synthetic leather sheath with matching belt."
	icon_state = "holster_machete"
	slot = ACCESSORY_SLOT_WEAPON
	concealed_holster = 0

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

CAPABILITIES(/obj/item/clothing/accessory/antediluvian)
	configure(item_worn(covers = ARMS))

/obj/item/clothing/accessory/antediluvian/loincloth
	name = "antediluvian loincloth"
	desc = "A lengthy loincloth that drapes over the loins, obviously. It's quite long."
	icon_state = "antediluvian_loin"
	item_state = "antediluvian_loin"
	overlay_state = "antediluvian_loin"

CAPABILITIES(/obj/item/clothing/accessory/antediluvian/loincloth)
	configure(item_worn(covers = LOWER_TORSO))

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

/obj/item/clothing/accessory/belt
	name = "Thin Belt"
	desc = "A thin belt for holding your pants up."
	icon_state = "belt_thin"
	item_state = "belt_thin"
	slot = ACCESSORY_SLOT_DECOR

CAPABILITIES(/obj/item/clothing/accessory/belt)
	configure(item_worn(slots = SLOT_TIE | SLOT_BELT))

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
	slot = ACCESSORY_SLOT_DECOR

CAPABILITIES(/obj/item/clothing/accessory/bunny_tail)
	configure(item_worn(slots = SLOT_TIE | SLOT_BELT))

/obj/item/clothing/accessory/poncho/roles/cloak/blueshield
	name = "bodyguard's cloak"
	desc = "A dark blue cloak with silver trim around the neck. The mark of a professional bodyguard, and ideal for concealing holsters or other items."
	icon = 'icons/obj/clothing/ties_yw.dmi' //Moved to archive
	icon_state = "cloak_blueshield"
	icon_override = 'icons/mob/ties_yw.dmi' //Moved to archive
	item_state = "cloak_blueshield"

/obj/item/clothing/accessory/poncho/roles/cloak/blueshield/dropped(mob/user, equipping, slot) //makes the blueshield suit not kek when used by a teshari
	..()
	set_icon_override('icons/mob/ties_yw.dmi') //Moved to archive

/// The suit the tie may be attached to (a relation view: null once it is deleted).
/obj/item/clothing/accessory/proc/has_suit() as /obj/item/clothing
	return has_suit

CAPABILITIES(/obj/item/clothing/accessory/scarf/teshari/neckscarf)
	fits_as(FIT_TESHARI)

CAPABILITIES(/obj/item/clothing/accessory/holster/machete)
	holder_takes(req_type(list(/obj/item/material/knife/machete, /obj/item/kinetic_crusher/machete), because = MSG(slot/doesnt_take)))
