/*
CONTAINS:
MATCHES
CIGARETTES
CIGARS
SMOKING PIPES
CUSTOM CIGS
CHEAP LIGHTERS
ZIPPO

CIGARETTE PACKETS ARE IN FANCY.DM
*/

//For anything that can light stuff on fire
/obj/item/flame

/// Burns (flame_step) every 2 s while lit.
/obj/item/flame/var/lit = 0
TRACKED(/obj/item/flame, lit)

CAPABILITIES(/obj/item/flame)
	every(2 SECONDS, then(PROC_REF(flame_step)), when = nameof(lit))

/// One burn step of a lit flame; each kind of flame overrides it with what it burns.
/obj/item/flame/proc/flame_step(datum/act/timer/A)
	return

/obj/item/flame/is_hot()
	return lit

///////////
//MATCHES//
///////////
/obj/item/flame/match
	name = "match"
	desc = "A simple match stick, used for lighting fine smokables."
	icon = 'icons/obj/cigarettes.dmi'
	icon_state = "match_unlit"
	var/burnt = 0
	var/smoketime = 5
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	attack_verb = list("burnt", "singed")
	drop_sound = SFX_ITEMS_DROP_FOOD
	pickup_sound = SFX_ITEMS_PICKUP_FOOD

/obj/item/flame/match/flame_step(datum/act/timer/A)
	if(isliving(loc))
		var/mob/living/M = loc
		M.ignite_mob()
	var/turf/location = get_turf(src)
	smoketime--
	if(smoketime < 1)
		burn_out()
		return
	if(location)
		location.hotspot_expose(700, 5)
		return

/obj/item/flame/match/dropped(mob/user, equipping, slot)
	if(equipping)
		return ..()
	//If dropped, put ourselves out
	//not before lighting up the turf we land on, though.
	if(lit)
		after(src, 0, PROC_REF(burn_out_where_dropped))
	return ..()

/obj/item/flame/match/proc/light(mob/user)
	play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_MATCHSTICK_LIT)
	set_lit(1)
	injury_kind = INJURY_BURN
	icon_state = "match_lit"
	name = "burning match"
	desc = "A match. This one is presently on fire."

/obj/item/flame/match/proc/burn_out()
	set_lit(0)
	burnt = 1
	injury_kind = INJURY_BLUNT
	icon_state = "match_burnt"
	item_state = "cigoff"
	name = "burnt match"
	desc = "A match. This one has seen better days."

//////////////////
//FINE SMOKABLES//
//////////////////
/obj/item/clothing/mask/smokable
	name = DEVELOPER_WARNING_NAME // "smokable item"
	desc = "You're not sure what this is. You should probably ahelp it."
	body_parts_covered = 0
	var/icon_on
	var/type_butt = null
	var/chem_volume = 0
	var/max_smoketime = 0	//Related to sprites
	var/smoketime = 0
	var/is_pipe = 0		//Prevents a runtime with pipes
	var/matchmes = "USER lights NAME with FLAME"
	var/lightermes = "USER lights NAME with FLAME"
	var/zippomes = "USER lights NAME with FLAME"
	var/weldermes = "USER lights NAME with FLAME"
	var/ignitermes = "USER lights NAME with FLAME"
	var/brand
	blood_sprite_state = null //Can't bloody these
	drop_sound = SFX_ITEMS_CIGS_LIGHTERS_CIG_SNUFF


/// Smokes (smokable_step) every 2 s while lit.
/obj/item/clothing/mask/smokable/var/lit = 0
TRACKED(/obj/item/clothing/mask/smokable, max_smoketime)

/// Lighting or putting it out changes what it looks like worn and held: the in-hand and worn state follow it (a draw never writes them).
/obj/item/clothing/mask/smokable/proc/set_lit(value)
	if(lit == value)
		return FALSE
	lit = value
	tracked_changed(src, nameof(lit))
	sync_item_state()
	return TRUE

SETTER(/obj/item/clothing/mask/smokable, lit)

/// Smoking it down changes how burnt it looks (and so its in-hand and worn state).
/obj/item/clothing/mask/smokable/proc/set_smoketime(value)
	if(smoketime == value)
		return FALSE
	smoketime = value
	tracked_changed(src, nameof(smoketime))
	sync_item_state()
	return TRUE

SETTER(/obj/item/clothing/mask/smokable, smoketime)

CAPABILITIES(/obj/item/clothing/mask/smokable)
	reagents(nameof(chem_volume))
	every(2 SECONDS, then(PROC_REF(smokable_step)), when = nameof(lit))
	op("item_applied", item(/obj/item), passes(), when(req(PROC_REF(held_is_another))), then(PROC_REF(item_applied)))

/// A click with the held item on itself is the in-hand use, not an item applied to it.
/obj/item/clothing/mask/smokable/proc/held_is_another(datum/act/op/A)
	return A.held != src

/// What it shows now, as a suffix of its base state: burning, partly smoked (a pipe stays as it is), or as new.
/obj/item/clothing/mask/smokable/proc/state_suffix()
	if(lit)
		return "_on"
	if(smoketime < max_smoketime && !is_pipe)
		return "_burnt"
	return ""

/// The in-hand and worn state follows the look; mobs wearing or holding it redraw when it changes.
/obj/item/clothing/mask/smokable/proc/sync_item_state()
	var/wanted = "[initial(item_state)][state_suffix()]"
	if(item_state == wanted)
		return
	item_state = wanted
	if(ismob(loc))
		var/mob/living/M = loc
		M.update_inv_wear_mask(0)
		M.update_inv_l_hand(0)
		M.update_inv_r_hand(1)

/obj/item/clothing/mask/smokable/Initialize(mapload)
	. = ..()
	flags |= NOREACT // so it doesn't react until you light it
	if(smoketime && !max_smoketime)
		set_max_smoketime(smoketime)

/obj/item/clothing/mask/smokable/proc/smoke(amount)
	if(smoketime > max_smoketime)
		set_smoketime(max_smoketime)
	set_smoketime(smoketime - amount)
	smoke_reagents(src, amount)

/// One puff of source's reagents: into the mouth of the human wearing it as a mask, else a little
/// burns away. Shared by smokables and the smokable capability.
/proc/smoke_reagents(obj/item/source, amount)
	if(!source.reagents || !source.reagents.total_volume) // check if it has any reagents at all
		return
	if(ishuman(source.loc))
		var/mob/living/carbon/human/C = source.loc
		if (source == C.get_equipped_item(SLOT_ID_MASK) && C.check_has_mouth()) // if it's in the human/monkey mouth, transfer reagents to the mob
			source.reagents.trans_to_mob(C, amount, CHEM_INGEST, 1.5, can_dialysis = FALSE) // I don't predict significant balance issues by letting blunts actually WORK.
	else // else just remove some of the reagents
		source.reagents.remove_any(REM)

/obj/item/clothing/mask/smokable/proc/smokable_step(datum/act/timer/A)
	var/turf/location = get_turf(src)
	smoke(1)
	if(smoketime < 1)
		die()
		return
	if(location)
		location.hotspot_expose(700, 5)

/obj/item/clothing/mask/smokable/draw(datum/look/look)
	..()
	var/suffix = state_suffix()
	if(suffix)
		look.state("[initial(icon_state)][suffix]")

/obj/item/clothing/mask/smokable/examine(mob/user)
	. = ..()

	if(!is_pipe)
		var/smoke_percent = round((smoketime / max_smoketime) * 100)
		switch(smoke_percent)
			if(90 to INFINITY)
				. += "[src] is still fresh."
			if(60 to 90)
				. += "[src] has a good amount of burn time remaining."
			if(30 to 60)
				. += "[src] is about half finished."
			if(10 to 30)
				. += "[src] is starting to burn low."
			else
				. += "[src] is nearly burnt out!"

/obj/item/clothing/mask/smokable/proc/light(flavor_text = "[usr] lights the [name].")
	if(!src.lit)
		set_lit(1)
		play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_CIG_LIGHT)
		injury_kind = INJURY_BURN
		if(ignite_smoke_reagents(src))
			return
		var/turf/T = get_turf(src)
		T.visible_message(flavor_text)
		set_light(2, 0.25, "#E38F46")

/// Lighting source: phoron or fuel in it explodes (source is deleted, returns TRUE); otherwise its
/// reagents may react from now on. Shared by smokables and the smokable capability.
/proc/ignite_smoke_reagents(obj/item/source)
	if(source.reagents?.get_reagent_amount(REAGENT_ID_PHORON)) // the phoron explodes when exposed to fire
		var/datum/effect/effect/system/reagents_explosion/e = new()
		e.set_up(round(source.reagents.get_reagent_amount(REAGENT_ID_PHORON) / 2.5, 1), get_turf(source), 0, 0)
		e.start()
		destroyed(source)
		return TRUE
	if(source.reagents?.get_reagent_amount(REAGENT_ID_FUEL)) // the fuel explodes, too, but much less violently
		var/datum/effect/effect/system/reagents_explosion/e = new()
		e.set_up(round(source.reagents.get_reagent_amount(REAGENT_ID_FUEL) / 5, 1), get_turf(source), 0, 0)
		e.start()
		destroyed(source)
		return TRUE
	source.flags &= ~NOREACT // allowing reagents to react after being lit
	source.reagents?.handle_reactions()
	return FALSE

/obj/item/clothing/mask/smokable/proc/die(nomessage = 0)
	var/turf/T = get_turf(src)
	set_light(0)
	play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_CIG_SNUFF)
	set_lit(0)
	if (type_butt)
		var/obj/item/butt = new type_butt(T)
		transfer_fingerprints_to(butt)
		if(brand)
			butt.desc += " This one is \a [brand]."
		if(ismob(loc))
			var/mob/living/M = loc
			if (!nomessage)
				to_chat(M, span_notice("Your [name] goes out."))
			M.remove_from_mob(src) //un-equip it so the overlays can update
			M.update_inv_wear_mask(0)
		// Turn mind bound cigs into butts
		if(src.possessed_voice && src.possessed_voice.len)
			var/mob/living/voice/V = src.possessed_voice[1]
			butt.inhabit_item(V, null, V.tf_mob_holder, TRUE)
			destroyed(V)
		replace_with(src, butt)
	else
		new /obj/effect/decal/cleanable/ash(T)
		if(ismob(loc))
			var/mob/living/M = loc
			if (!nomessage)
				to_chat(M, span_notice("Your [name] goes out, and you empty the ash."))
				play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_CIG_SNUFF)
			set_lit(0)
			M.update_inv_wear_mask(0)
			set_smoketime(0)
			reagents.clear_reagents()
			name = "empty [initial(name)]"

/obj/item/clothing/mask/smokable/proc/quench()
	set_lit(0)

/obj/item/clothing/mask/smokable/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(lit && M == user && ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/blocked = H.check_mouth_coverage()
		if(blocked)
			to_chat(H, span_warning("\The [blocked] is in the way!"))
			return ITEM_INTERACT_FAILURE
		to_chat(H, span_notice("You take a drag on your [name]."))
		play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_INHALE)
		smoke(5)
		return ITEM_INTERACT_SUCCESS
	if(istype(M) && M.on_fire)
		user.do_attack_animation(M)
		light(span_notice("[user] coldly lights the [name] with the burning body of [M]."))
		return ITEM_INTERACT_SUCCESS
	return ..()

/// Something hot used on it lights it, and the click goes on. A kind of smokable that takes more overrides this (the cigar, the pipe, the e-cig).
/obj/item/clothing/mask/smokable/proc/item_applied(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(W.is_hot())
		var/text = matchmes
		if(istype(W, /obj/item/flame/match))
			text = matchmes
		else if(istype(W, /obj/item/flame/lighter/zippo))
			text = zippomes
		else if(istype(W, /obj/item/flame/lighter))
			text = lightermes
		else if(W.has_tool_quality(TOOL_WELDER))
			text = weldermes
		else if(istype(W, /obj/item/assembly/igniter))
			text = ignitermes
		text = replacetext(text, "USER", "[user]")
		text = replacetext(text, "NAME", "[name]")
		text = replacetext(text, "FLAME", "[W.name]")
		light(text)
	return OP_OK

/obj/item/clothing/mask/smokable/water_act(amount)
	if(amount >= 5)
		quench()

/obj/item/clothing/mask/smokable/cigarette
	name = "cigarette"
	desc = "A roll of tobacco and nicotine."
	icon_state = "cig"
	item_state = "cig"
	throw_speed = 0.5
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS | SLOT_MASK
	attack_verb = list("burnt", "singed")
	type_butt = /obj/item/trash/cigbutt
	chem_volume = 15
	max_smoketime = 300
	smoketime = 300
	matchmes = span_notice("USER lights their NAME with their FLAME.")
	lightermes = span_notice("USER manages to light their NAME with FLAME.")
	zippomes = span_notice(span_rose("With a flick of their wrist, USER lights their NAME with their FLAME."))
	weldermes = span_notice("USER casually lights the NAME with FLAME.")
	ignitermes = span_notice("USER fiddles with FLAME, and manages to light their NAME.")
	special_handling = TRUE

CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette/cigar)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 2))) // 4 total
CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette/cigar/cohiba)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 3))) // 7 total
CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette/cigar/havana)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 6))) // 10 total
CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette/joint/blunt)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 2))) // 4 total

CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 2)))
	op("put_out", in_hand(), stance(I_HELP, I_DISARM, I_GRAB), then(PROC_REF(put_out)))
	op("tread_out", in_hand(), stance(I_HURT), priority(OP_PRIORITY_ATTACK), then(PROC_REF(tread_out)))

/// A cigarette takes an active energy sword's flame too, after what any smokable takes.
/obj/item/clothing/mask/smokable/cigarette/item_applied(datum/act/op/A)
	..()
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/melee/energy/sword))
		var/obj/item/melee/energy/sword/S = W
		if(S.active)
			light(span_warning("[user] swings their [W], barely missing their nose. They light their [name] in the process."))

	return OP_OK

/obj/item/clothing/mask/smokable/cigarette/afterattack(obj/item/reagent_containers/glass/glass, mob/user as mob, proximity)
	..()
	if(!proximity)
		return
	if(istype(glass)) //you can dip cigarettes into beakers
		var/transfered = glass.reagents.trans_to_obj(src, chem_volume)
		if(transfered)	//if reagents were transfered, show the message
			to_chat(user, span_notice("You dip \the [src] into \the [glass]."))
		else			//if not, either the beaker was empty, or the cigarette was full
			if(!glass.reagents.total_volume)
				to_chat(user, span_notice("[glass] is empty."))
			else
				to_chat(user, span_notice("[src] is full."))

/// Using a lit cigarette in the hand puts it out. The clothing's own self-use still follows, as the old ..() did.
/obj/item/clothing/mask/smokable/cigarette/proc/put_out(datum/act/op/A)
	var/mob/user = A.actor
	if(lit == 1)
		act_message(user, src, others = span_notice("%U% puts out %T%."))
		quench()
	return OP_DECLINE

/// In the hurt stance the lit cigarette is dropped and trodden on.
/obj/item/clothing/mask/smokable/cigarette/proc/tread_out(datum/act/op/A)
	var/mob/user = A.actor
	if(lit == 1)
		act_message(user, src, others = span_notice("%U% drops and treads on the lit [src], putting it out instantly."))
		play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_CIG_SNUFF)
		die(1)
	return OP_DECLINE

////////////
// CIGARS //
////////////
/obj/item/clothing/mask/smokable/cigarette/cigar
	name = "premium cigar"
	desc = "A brown roll of tobacco and... well, you're not quite sure. This thing's huge!"
	description_fluff = "While the label does say that this is a 'premium cigar', it \
	really cannot match other types of cigars on the market. Is it a quality \
	cigarette? Perhaps. Was it hand-made with care? No."
	icon_state = "cigar2"
	type_butt = /obj/item/trash/cigbutt/cigarbutt
	throw_speed = 0.5
	item_state = "cigar"
	max_smoketime = 1500
	smoketime = 1500
	chem_volume = 20
	matchmes = span_notice("USER lights their NAME with their FLAME.")
	lightermes = span_notice("USER manages to offend their NAME by lighting it with FLAME.")
	zippomes = span_notice(span_rose("With a flick of their wrist, USER lights their NAME with their FLAME."))
	weldermes = span_notice("USER insults NAME by lighting it with FLAME.")
	ignitermes = span_notice("USER fiddles with FLAME, and manages to light their NAME with the power of science.")

/obj/item/clothing/mask/smokable/cigarette/cigar/cohiba
	name = "\improper Cohiba Robusto cigar"
	desc = "There's little more you could want from a cigar."
	description_fluff = "Cohiba has been a popular cigar company for centuries. \
	They are still based out of Cuba and refuse to expand and therefore have a very \
	limited quantity, making their cigars coveted all through known space. Robusto \
	is one of their most popular shapes of cigars."
	icon_state = "cigar2"

/obj/item/clothing/mask/smokable/cigarette/cigar/havana
	name = "premium Havanian cigar"
	desc = "Save these for the fancy-pantses at the next CentCom black tie reception. \
	You can't blow the smoke from such majestic stogies in just anyone's face."
	description_fluff = "'Havanian' is an umbrella term for any cigar made in the \
	typical handmade style of Cuba. This particular cigar is from Gilthari's cigar \
	manufacturers and produced galaxy-wide. While this way of making quality cigars \
	has become slightly bastardized over the years, overall quality has remained \
	relatively the same, even if there is a large quantity of 'Havanian' cigars."
	icon_state = "cigar2"
	max_smoketime = 7200
	smoketime = 7200
	chem_volume = 30

/obj/item/trash/cigbutt
	name = "cigarette butt"
	desc = "A manky old cigarette butt."
	icon = 'icons/inventory/face/item.dmi'
	icon_state = "cigbutt"
	randpixel = 10
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	throwforce = 1

CAPABILITIES(/obj/item/trash/cigbutt)
	rolls(ROLL_PIXEL, PIXEL_JITTER(10))
	rolls(nameof(transform), PROC_REF(roll_transform))

/// Rolled before init (rolls()): a butt lies at any angle.
/obj/item/trash/cigbutt/proc/roll_transform(datum/roller/R)
	return turn(transform, R.number(0, 360))

/obj/item/trash/cigbutt/cigarbutt
	name = "cigar butt"
	desc = "A manky old cigar butt."
	icon_state = "cigarbutt"

/// A cigar redraws the user's mask and hands after the cigarette handling.
/obj/item/clothing/mask/smokable/cigarette/cigar/item_applied(datum/act/op/A)
	..()
	var/mob/user = A.actor
	user.update_inv_wear_mask(0)
	user.update_inv_l_hand(0)
	user.update_inv_r_hand(1)
	return OP_OK

/////////////////
//SMOKING PIPES//
/////////////////
/obj/item/clothing/mask/smokable/pipe
	name = "smoking pipe"
	desc = "A pipe, for smoking. Made of fine, stained cherry wood."
	description_fluff = "ClassiCo Accessories and Haberdashers, originating out of Mars, \
	claim to produce products 'for the modern gentlefolk'. Most of their items are high-end \
	and expensive, but they pledge to back their prices up with quality, and usually do."
	icon_state = "pipe"
	item_state = "pipe"
	smoketime = 0
	chem_volume = 50
	matchmes = span_notice("USER lights their NAME with their FLAME.")
	lightermes = span_notice("USER manages to light their NAME with FLAME.")
	zippomes = span_notice(span_rose("With much care, USER lights their NAME with their FLAME."))
	weldermes = span_notice("USER recklessly lights NAME with FLAME.")
	ignitermes = span_notice("USER fiddles with FLAME, and manages to light their NAME with the power of science.")
	is_pipe = 1

/obj/item/clothing/mask/smokable/pipe/Initialize(mapload)
	. = ..()
	name = "empty [initial(name)]"

CAPABILITIES(/obj/item/clothing/mask/smokable/pipe)
	op("put_out", in_hand(), stance(I_HELP, I_DISARM, I_GRAB), then(PROC_REF(put_out)))
	op("empty_out", in_hand(), stance(I_HURT), priority(OP_PRIORITY_ATTACK), then(PROC_REF(empty_out)))

/// Using a lit pipe in the hand puts it out. The clothing's own self-use still follows, as the old ..() did.
/obj/item/clothing/mask/smokable/pipe/proc/put_out(datum/act/op/A)
	var/mob/user = A.actor
	if(lit == 1)
		act_message(user, src, others = span_notice("%U% puts out %T%."))
		quench()
	return OP_DECLINE

/// In the hurt stance the lit pipe is emptied on the floor.
/obj/item/clothing/mask/smokable/pipe/proc/empty_out(datum/act/op/A)
	var/mob/user = A.actor
	if(lit == 1)
		act_message(user, src, others = span_notice("%U% empties the lit [src] on the floor!."))
		play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_CIG_SNUFF)
		die(1)
	return OP_DECLINE

/// A pipe takes what any smokable takes, and is packed with a dried plant (an active energy sword does nothing to it).
/obj/item/clothing/mask/smokable/pipe/item_applied(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/melee/energy/sword))
		return OP_OK

	..()

	if (istype(W, /obj/item/reagent_containers/food/snacks))
		var/obj/item/reagent_containers/food/snacks/grown/G = W
		if (!G.dry)
			to_chat(user, span_notice("[G] must be dried before you stuff it into [src]."))
			return OP_OK
		if (smoketime)
			to_chat(user, span_notice("[src] is already packed."))
			return OP_OK
		set_max_smoketime(1000)
		set_smoketime(1000)
		if(G.reagents)
			G.reagents.trans_to_obj(src, G.reagents.total_volume)
		name = "[G.name]-packed [initial(name)]"
		consume(G, user)

	else if(istype(W, /obj/item/flame/lighter))
		var/obj/item/flame/lighter/L = W
		if(L.lit)
			light(span_notice("[user] manages to light their [name] with [W]."))

	else if(istype(W, /obj/item/flame/match))
		var/obj/item/flame/match/M = W
		if(M.lit)
			light(span_notice("[user] lights their [name] with their [W]."))

	else if(istype(W, /obj/item/assembly/igniter))
		light(span_notice("[user] fiddles with [W], and manages to light their [name] with the power of science."))

	user.update_inv_wear_mask(0)
	user.update_inv_l_hand(0)
	user.update_inv_r_hand(1)
	return OP_OK

/obj/item/clothing/mask/smokable/pipe/cobpipe
	name = "corn cob pipe"
	desc = "A nicotine delivery system popularized by folksy backwoodsmen, kept popular in the modern age and beyond by space hipsters."
	icon_state = "cobpipe"
	item_state = "cobpipe"
	chem_volume = 35

/obj/item/clothing/mask/smokable/pipe/bonepipe
	name = "Europan bone pipe"
	desc = "A smoking pipe made out of the bones of the Europan bone whale."
	description_fluff = "While most commonly associated with bone charms, bones from various sea creatures on Europa are used in a \
	variety of goods, such as this smoking pipe. While smoking in submarines is often an uncommon occurrence, due to a lack of \
	available air or space, these pipes are a common sight in the many stations of Europa. Higher-quality pipes typically have \
	scenes etched into their bones, and can tell the story of their owner's time on Europa."
	icon_state = "bonepipe"
	item_state = "bonepipe"
	chem_volume = 30

///////////////
//CUSTOM CIGS//
///////////////
//and by custom cigs i mean craftable joints. smoke weed every day

/obj/item/clothing/mask/smokable/cigarette/joint
	name = "joint"
	desc = "A joint lovingly rolled and crafted with care. Blaze it."
	icon_state = "joint"
	max_smoketime = 400
	smoketime = 400
	chem_volume = 25

/obj/item/clothing/mask/smokable/cigarette/joint/blunt
	name = "blunt"
	desc = "A blunt lovingly rolled and crafted with care. Blaze it."
	icon_state = "cigar"
	max_smoketime = 500
	smoketime = 500
	chem_volume = 45

/obj/item/reagent_containers/rollingpaper
	name = "rolling paper"
	desc = "A small, thin piece of easily flammable paper, commonly used for rolling and smoking various dried plants."
	description_fluff = "The legalization of certain substances propelled the sale of rolling \
	papers through the roof. Now almost every Trans-stellar produces a variety, often of questionable quality."
	icon = 'icons/obj/cigarettes.dmi'
	icon_state = "cig paper"
	volume = 25
	var/obj/item/clothing/mask/smokable/cigarette/crafted_type = /obj/item/clothing/mask/smokable/cigarette/joint

/obj/item/reagent_containers/rollingpaper/blunt
	name = "blunt wrap"
	desc = "A small piece of easily flammable paper similar to that which encases cigars. It's made out of tobacco, bigger than a standard rolling paper, and will last longer."
	icon_state = "blunt paper"
	volume = 45
	crafted_type = /obj/item/clothing/mask/smokable/cigarette/joint/blunt

// A rolling paper is a sealed holder of its volume: a dried plant used on it is added (if it fits), and using it in hand rolls what is in it into a joint.
CAPABILITIES(/obj/item/reagent_containers/rollingpaper)
	reagent_container(
		volume = nameof(volume),
		needle = TRUE,
		sealed = TRUE,
		settable = FALSE,
		shows_contents = FALSE)
	op("add", item(/obj/item/reagent_containers/food/snacks), label("Add it to the paper"), then(PROC_REF(plant_added)))
	op("roll", in_hand(), label("Roll it"), then(PROC_REF(rolled)))

/// A plant is added (it must be dried, and fit).
/obj/item/reagent_containers/rollingpaper/proc/plant_added(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/grown/G = A.held
	if (!G.dry)                                                                                          //This prevents people from just stuffing cheeseburgers into their joint
		to_chat(user, span_notice("[G.name] must be dried before you add it to [src]."))
		return OP_REFUSED
	if (G.reagents.total_volume + src.reagents.total_volume > src.reagents.maximum_volume)               //Check that we don't have too much already in the paper before adding things
		to_chat(user, span_warning("The [src] is too full to add [G.name]."))
		return OP_REFUSED
	if (src.reagents.total_volume == 0)
		if (istype(src, /obj/item/reagent_containers/rollingpaper/blunt))                         //update the icon if this is the first thing we're adding to the paper
			src.icon_state = "blunt_full"
		else
			src.icon_state = "paper_full"
	to_chat(user, span_notice("You add the [G.name] to the [src.name]."))
	src.add_fingerprint(user)
	if(G.reagents)
		G.reagents.trans_to_obj(src, G.reagents.total_volume)                                            //adds the reagents from the plant into the paper
	consume(G, user)
	return OP_OK

/// Rolled into a joint that holds what was in it.
/obj/item/reagent_containers/rollingpaper/proc/rolled(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/clothing/mask/smokable/cigarette/J = new crafted_type()
	to_chat(user,span_notice("You roll the [src] into a blunt!"))
	J.add_fingerprint(user)
	if(reagents)
		reagents.trans_to_obj(J, reagents.total_volume)
	user.drop_from_inventory(src)
	user.put_in_hands(J)
	consume(src, user)
	return OP_OK

/////////
//CHEAP//
/////////
/obj/item/flame/lighter
	name = "cheap lighter"
	desc = "A cheap-as-free lighter."
	description_fluff = "The 'hand-made in Altair' sticker underneath is a charming way of \
	saying 'Made with prison labour'. It's no wonder the company can sell these things so cheap."
	icon = 'icons/obj/lighters.dmi'
	icon_state = "lighter"
	item_state = "lighter"
	w_class = ITEMSIZE_TINY
	throwforce = 4
	slot_flags = SLOT_BELT
	attack_verb = list("burnt", "singed")
	var/base_state
	/// Sounds
	var/activation_sound = SFX_ITEMS_LIGHTER_ON
	var/deactivation_sound = SFX_ITEMS_LIGHTER_OFF
	/// Color of the flame and how big the flame is (pulled from Welder code)
	var/flame_color = "#FF9933"
	var/flame_intensity = 2
	/// Color List
	var/random_color = FALSE
	var/available_colors = list(COLOR_ASSEMBLY_BLACK,
								COLOR_ASSEMBLY_BGRAY,
								COLOR_ASSEMBLY_WHITE,
								COLOR_ASSEMBLY_RED,
								COLOR_ASSEMBLY_ORANGE,
								COLOR_ASSEMBLY_BEIGE,
								COLOR_ASSEMBLY_BROWN,
								COLOR_ASSEMBLY_GOLD,
								COLOR_ASSEMBLY_YELLOW,
								COLOR_ASSEMBLY_GURKHA,
								COLOR_ASSEMBLY_LGREEN,
								COLOR_ASSEMBLY_GREEN,
								COLOR_ASSEMBLY_LBLUE,
								COLOR_ASSEMBLY_BLUE,
								COLOR_ASSEMBLY_PURPLE,
								COLOR_ASSEMBLY_HOT_PINK)
	/// If we are a special variant (see: override attack_self)
	var/special_variant = FALSE
	/// Var used for detonator zippos

/// Var used for detonator zippos
/obj/item/flame/lighter/var/detonator_mode = 0
TRACKED(/obj/item/flame/lighter, detonator_mode)

CAPABILITIES(/obj/item/flame/lighter)
	op("toggle", in_hand(), then(PROC_REF(toggled)))

// TODO: Remove this path from POIs and loose maps (it's no longer needed)
/obj/item/flame/lighter/random

// Randomizes Cheap Lighters on Spawn
/obj/item/flame/lighter/Initialize(mapload)
	. = ..()
	var/image/I = image(icon, "lighter-[pick("trans","tall","matte")]")
	I.color = pick(available_colors)
	add_overlay(I) // ALLOW(decl): Initialize rolls a random pick per instance; a declaration has no random form

/// Using the lighter in the hand lights it or puts it out. Each kind of lighter overrides this; one that does not handle the use declines it, and the click goes on to the item's own use.
/obj/item/flame/lighter/proc/toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if(special_variant)
		return OP_DECLINE
	if(detonator_mode)
		return OP_DECLINE
	if(!lit)
		set_lit(TRUE)
		icon_state = "lighteron"
		playsound(src, activation_sound, 75, 1)
		act_message(user, src, others = span_notice("After a few attempts, %U% manages to light %T%."))

		set_light(2, 0.5, "#FF9933")
	else
		set_lit(FALSE)
		icon_state = "lighter"
		playsound(src, deactivation_sound, 75, 1)
		act_message(user, src, others = span_notice("%U% quietly shuts off %T%."))

		set_light(0)
	return OP_OK

/obj/item/flame/lighter/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(lit == 1)
		M.ignite_mob()
		add_attack_logs(user,M,"Lit on fire with [src]")
		return ITEM_INTERACT_SUCCESS

	if(istype(M.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/smokable/cigarette) && user.zone_sel.selecting == O_MOUTH && lit)
		var/obj/item/clothing/mask/smokable/cigarette/cig = M.get_equipped_item(SLOT_ID_MASK)
		if(M == user)
			cig.attackby(src, user)
			return ITEM_INTERACT_SUCCESS

		else
			if(istype(src, /obj/item/flame/lighter/zippo))
				cig.light(span_notice(span_rose("[user] whips the [name] out and holds it for [M].")))
			else
				cig.light(span_notice("[user] holds the [name] out for [M], and lights the [cig.name]."))
			return ITEM_INTERACT_SUCCESS
	else
		..()

/////////
//ZIPPO//
/////////
/obj/item/flame/lighter/zippo
	name = "\improper Zippo lighter"
	desc = "The zippo."
	description_fluff = "Still going after all these years."
	icon_state = "zippo"
	item_state = "zippo"
	activation_sound = SFX_ITEMS_ZIPPO_ON
	deactivation_sound = SFX_ITEMS_ZIPPO_OFF
	special_variant = TRUE

/obj/item/flame/lighter/zippo/Initialize(mapload)
	. = ..()
	cut_overlays() // ALLOW(decl): removes the parent's random overlay. Prevents the Cheap Lighter overlay from appearing on this

/// A zippo flips open and shut with its own states.
/obj/item/flame/lighter/zippo/toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if(detonator_mode)
		return OP_DECLINE
	if(!base_state)
		base_state = icon_state
	if(!lit)
		set_lit(TRUE)
		icon_state = "[base_state]on"
		item_state = "[base_state]on"
		playsound(src, activation_sound, 75, 1)
		act_message(user, src, others = span_notice(span_rose("Without even breaking stride, %U% flips open and lights %T% in one smooth movement.")))

		set_light(2, 0.5, "#FF9933")
	else
		set_lit(FALSE)
		icon_state = "[base_state]"
		item_state = "[base_state]"
		playsound(src, deactivation_sound, 75, 1)
		act_message(user, src, others = span_notice(span_rose("You hear a quiet click, as %U% shuts off %T% without even looking at what they're doing.")))

		set_light(0)
	return OP_OK

//Here we add Zippo skins.

/obj/item/flame/lighter/zippo/black
	name = "\improper holy Zippo lighter"
	desc = "Only in regards to Christianity, that is."
	icon_state = "blackzippo"

/obj/item/flame/lighter/zippo/blue
	name = "\improper blue Zippo lighter"
	icon_state = "bluezippo"

/obj/item/flame/lighter/zippo/engraved
	name = "\improper engraved Zippo lighter"
	icon_state = "engravedzippo"
	item_state = "zippo"

/obj/item/flame/lighter/zippo/gold
	name = "\improper golden Zippo lighter"
	icon_state = "goldzippo"

/obj/item/flame/lighter/zippo/moff
	name = "\improper moth Zippo lighter"
	desc = "Too cute to be a Tymisian."
	icon_state = "moffzippo"

/obj/item/flame/lighter/zippo/red
	name = "\improper red Zippo lighter"
	icon_state = "redzippo"

/obj/item/flame/lighter/zippo/ironic
	name = "\improper ironic Zippo lighter"
	desc = "What a quiant idea."
	icon_state = "ironiczippo"

/obj/item/flame/lighter/zippo/capitalist
	name = "\improper capitalist Zippo lighter"
	desc = "Made of gold and obsidian, this is truly not worth however much you spent on it."
	icon_state = "cappiezippo"

/obj/item/flame/lighter/zippo/communist
	name = "\improper communist Zippo lighter"
	desc = "All you need to spark a revolution."
	icon_state = "commiezippo"

/obj/item/flame/lighter/zippo/royal
	name = "\improper royal Zippo lighter"
	desc = "An incredibly fancy lighter, gilded and covered in the color of royalty."
	icon_state = "royalzippo"

/obj/item/flame/lighter/zippo/gonzo
	name = "\improper Gonzo Zippo lighter"
	desc = "A lighter with the iconic Gonzo fist painted on it."
	icon_state = "gonzozippo"

/obj/item/flame/lighter/zippo/rainbow
	name = "\improper rainbow Zippo lighter"
	icon_state = "rainbowzippo"

/obj/item/flame/lighter/zippo/skull
	name = "\improper badass Zippo lighter"
	desc = "An absolutely badass zippo lighter. Just look at that skull!"
	icon_state = "skullzippo"

/obj/item/flame/lighter/supermatter
	name = "Hardlight Supermatter Zippo"	// Base SM Lighter
	desc = "State of the Art Supermatter Lighter."
	description_fluff = "A zippo style lighter with a tiny supermatter sliver held by a hardlight shield. When lighting a cigar, make sure to hover the tip near the sliver, not against it!"
	icon_state = "SMzippo"
	item_state = "SMzippo"
	activation_sound = SFX_ITEMS_ZIPPO_ON_ALT
	deactivation_sound = SFX_ITEMS_ZIPPO_OFF
	special_variant = TRUE
	///Special supermatter var used for attack_self chain logic.
	var/special_supermatter = FALSE

/obj/item/flame/lighter/supermatter/syndismzippo
	name = "Phoron Supermatter Zippo"		// Syndicate SM Lighter
	desc = "State of the Art Supermatter Lighter."
	description_fluff = "A red zippo style lighter with a tiny supermatter sliver held by a phoron field."
	icon_state = "SyndiSMzippo"
	item_state = "SyndiSMzippo"
	activation_sound = SFX_ITEMS_ZIPPO_ON_ALT
	deactivation_sound = SFX_ITEMS_ZIPPO_OFF
	special_supermatter = TRUE

/obj/item/flame/lighter/supermatter/expsmzippo
	name = "Experimental SM Lighter"		// Dangerous WIP (admin/event only ATM)
	desc = "State of the Art Supermatter Lighter"
	description_fluff = "A unique take originating from the zippo design, a shard of supermatter placed within lead-lined walls. Cautious, VERY DANGEROUS do NOT touch!"
	icon_state = "ExpSMzippo"
	item_state = "ExpSMzippo"
	activation_sound = SFX_ITEMS_BUTTON_OPEN
	deactivation_sound = SFX_ITEMS_BUTTON_CLOSE
	special_supermatter = TRUE

// safe smzippo
/// The hardlight supermatter zippo (the dangerous ones below override this).
/obj/item/flame/lighter/supermatter/toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if(special_supermatter)
		return OP_DECLINE
	if(!base_state)
		base_state = icon_state
	if(!lit)
		set_lit(1)
		icon_state = "[base_state]on"
		item_state = "[base_state]on"
		playsound(src, activation_sound, 75, 1)
		if(prob(50))
			act_message(user, src, others = span_notice(span_rose("%U% safely activates %T% with a push of a button!")))
		else
			if(prob(95))
				act_message(user, src, others = span_notice("After a few attempts, %U% manages to excite the supermatter within %T%."))
			else			// Just like the cheap lighter, this time you can shock/burn yourself a little on the hardlight shield
				to_chat(user, span_warning("You hurt yourself on the shielding!"))
				if (user.get_left_hand() == src)
					user.injure(INJURY_BURN, 1/3, BP_L_HAND, src)
					user.injure(INJURY_BLUNT, 2/3, BP_L_HAND, src)
					user.injure(INJURY_ELECTRIC, 2, BP_L_HAND, src)
					user.injure(INJURY_CELLULAR, 3, BP_L_HAND, src)
					user.emp_act(EMP_HARMLESS)
				else
					user.injure(INJURY_BURN, 1/3, BP_R_HAND, src)
					user.injure(INJURY_BLUNT, 2/3, BP_R_HAND, src)
					user.injure(INJURY_ELECTRIC, 2, BP_R_HAND, src)
					user.injure(INJURY_CELLULAR, 3, BP_R_HAND, src)
					user.emp_act(EMP_HARMLESS)
				act_message(user, src, others = span_notice("After a few attempts, %U% manages to activate %T%, they however sting themselves on the shielding!"))

		set_light(2)
	else
		set_lit(0)
		icon_state = "[base_state]"
		item_state = "[base_state]"
		playsound(src, deactivation_sound, 75, 1)
		if(istype(src, /obj/item/flame/lighter/supermatter) )
			act_message(user, src, others = span_notice(span_rose("You hear a quiet click, as %U% shuts %T% without even looking at what they're doing.")))
		else
			act_message(user, src, others = span_notice("%U% quietly shuts %T%."))

		set_light(0)
	return OP_OK


/obj/item/flame/lighter/supermatter/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(lit == 1)
		M.ignite_mob()
		add_attack_logs(user,M,"Lit on fire with [src]")
		return ITEM_INTERACT_SUCCESS

	if(istype(M.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/smokable/cigarette) && user.zone_sel.selecting == O_MOUTH && lit)
		var/obj/item/clothing/mask/smokable/cigarette/cig = M.get_equipped_item(SLOT_ID_MASK)
		if(M == user)
			cig.attackby(src, user)
		else
			if(istype(src, /obj/item/flame/lighter/supermatter))
				cig.light(span_notice(span_rose("[user] whips the [name] out and holds it for [M].")))
			else
				cig.light(span_notice("[user] holds the [name] out for [M], and lights the [cig.name]."))
		return ITEM_INTERACT_SUCCESS
	else
		..()

// syndicate smzippo
/// The phoron supermatter zippo.
/obj/item/flame/lighter/supermatter/syndismzippo/toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!base_state)
		base_state = icon_state
	if(!lit)
		set_lit(1)
		icon_state = "[base_state]on"
		item_state = "[base_state]on"
		playsound(src, activation_sound, 75, 1)
		if(prob(50))
			act_message(user, src, others = span_notice(span_rose("%U% safely activates %T% with a push of a button!")))
		else
			if(prob(95))
				act_message(user, src, others = span_notice("After a few attempts, %U% manages to excite the supermatter within %T%."))
			else			// Just like with the cheap lighter, but this time you can hurt yourself on the heated phoron field
				to_chat(user, span_warning("You singe yourself on the phoron shielding the excited supermatter!"))
				if (user.get_left_hand() == src)
					user.injure(INJURY_PAIN, 30, BP_L_HAND, src)
					user.apply_effect(20,IRRADIATE)
					user.injure(INJURY_BURN, 5, BP_L_HAND, src)
					user.injure(INJURY_ELECTRIC, 5, BP_L_HAND, src)
				else
					user.injure(INJURY_PAIN, 30, BP_R_HAND, src)
					user.apply_effect(20,IRRADIATE)
					user.injure(INJURY_BURN, 5, BP_R_HAND, src)
					user.injure(INJURY_ELECTRIC, 5, BP_R_HAND, src)
				act_message(user, src, others = span_notice("After a few attempts, %U% manages to activate %T%, they however burn themselves with the heated phoron field!"))

		set_light(2)
	else
		set_lit(0)
		icon_state = "[base_state]"
		item_state = "[base_state]"
		playsound(src, deactivation_sound, 75, 1)
		if(istype(src, /obj/item/flame/lighter/supermatter/syndismzippo) )
			act_message(user, src, others = span_notice(span_rose("You hear a quiet click, as %U% shuts %T% without even looking at what they're doing.")))
		else
			act_message(user, src, others = span_notice("%U% quietly shuts %T%."))

		set_light(0)
	return OP_OK


/obj/item/flame/lighter/supermatter/syndismzippo/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(lit == 1)
		M.ignite_mob()
		add_attack_logs(user,M,"Lit on fire with [src]")
		return ITEM_INTERACT_SUCCESS

	if(istype(M.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/smokable/cigarette) && user.zone_sel.selecting == O_MOUTH && lit)
		var/obj/item/clothing/mask/smokable/cigarette/cig = M.get_equipped_item(SLOT_ID_MASK)
		if(M == user)
			cig.attackby(src, user)
			return ITEM_INTERACT_SUCCESS
		else
			if(istype(src, /obj/item/flame/lighter/supermatter/syndismzippo))
				cig.light(span_notice(span_rose("[user] whips the [name] out and holds it for [M].")))
			else
				cig.light(span_notice("[user] holds the [name] out for [M], and lights the [cig.name]."))
			return ITEM_INTERACT_SUCCESS
	else
		..()

/obj/item/flame/lighter/flame_step(datum/act/timer/A)
	var/turf/location = get_turf(src)
	if(location)
		location.hotspot_expose(700, 5)
	return

// Experimental smzippo
/// The experimental supermatter lighter.
/obj/item/flame/lighter/supermatter/expsmzippo/toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if (!base_state)
		base_state = icon_state
	if (!lit)
		set_lit(1)
		icon_state = "[base_state]on"
		item_state = "[base_state]on"
		playsound(src, activation_sound, 75, 1)
		var/i = rand(1, 100)
		switch(i)
			if(1 to 22)
				act_message(user, src, MSG_SELF(span_notice(span_rose("You safely revealed the supermatter shard within %T%!"))), MSG_OTHERS(span_notice(span_rose("%U% safely reveals the supermatter shard within %T%!"))))
				if (user.get_left_hand() == src)
					user.injure(INJURY_RADIATION, 1, BP_L_HAND, src)
				else			// Even using this safely will irradiate you a tiny tiny bit.
					user.injure(INJURY_RADIATION, 1, BP_R_HAND, src)
			if(23 to 33)
				act_message(user, null, MSG_SELF(span_notice("You accidentally grazed your hand across the supermatter!")), MSG_OTHERS(span_warning("%U%'s hand slipped and they brush against the supermatter within [src]!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_RADIATION, 10, BP_L_HAND, src)
					user.injure(INJURY_BURN, 20, BP_L_HAND, src)
					user.injure(INJURY_ELECTRIC, 20, BP_L_HAND, src)
					user.injure(INJURY_PAIN, 50, BP_L_HAND, src)
				else			// One of the outcomes will burn and shock you, the pain is the worst part of this one though.
					user.injure(INJURY_RADIATION, 10, BP_R_HAND, src)
					user.injure(INJURY_BURN, 20, BP_R_HAND, src)
					user.injure(INJURY_ELECTRIC, 20, BP_R_HAND, src)
					user.injure(INJURY_PAIN, 50, BP_R_HAND, src)
			if(34 to 44)
				act_message(user, src, MSG_SELF(span_notice("You accidentally burn yourself on %T%!")), MSG_OTHERS(span_warning("%U% burned themselves on %T%!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_RADIATION, 30, BP_L_HAND, src)
					user.injure(INJURY_BURN, 20 / 3, BP_L_HAND, src)
					user.injure(INJURY_BLUNT, 40 / 3, BP_L_HAND, src)
					user.injure(INJURY_BURN, 15, BP_L_HAND, src)
				else			// One of the outcomes is pure burn and radiation.
					user.injure(INJURY_RADIATION, 30, BP_R_HAND, src)
					user.injure(INJURY_BURN, 20 / 3, BP_R_HAND, src)
					user.injure(INJURY_BLUNT, 40 / 3, BP_R_HAND, src)
					user.injure(INJURY_BURN, 15, BP_R_HAND, src)
			if(45 to 55)
				act_message(user, src, MSG_SELF(span_notice("You fumble %T%, letting the supermatter spark as the case opens!")), MSG_OTHERS(span_warning("%U% fumbled %T% and the supermatter let out sparks!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_ELECTRIC, 1, BP_L_HAND, src)
					user.emp_act(EMP_HEAVY)
				else			// This one is mostly dangerous to synthetics and it will EMP you. But otherwise it's safe.
					user.injure(INJURY_ELECTRIC, 1, BP_R_HAND, src)
					user.emp_act(EMP_HEAVY)
			if(56 to 66)
				act_message(user, src, MSG_SELF(span_notice("You struggle to get the case to open, and when it does the heat that pours out of %T% burns!")), MSG_OTHERS(span_warning("%U% struggles to open their [src], but when they do they get burned by the extreme heat within!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_RADIATION, 1, BP_L_HAND, src)
					user.injure(INJURY_BLUNT, 1, BP_L_HAND, src)
					user.injure(INJURY_BURN, 200, BP_L_HAND, src)
					user.drop_l_hand()
				else			// This will INSTA-DUST your hand that you're holding the item in, and then make you drop the lighter.
					user.injure(INJURY_RADIATION, 1, BP_R_HAND, src)
					user.injure(INJURY_BLUNT, 1, BP_R_HAND, src)
					user.injure(INJURY_BURN, 200, BP_R_HAND, src)
					user.drop_r_hand()
			if(67 to 77)
				act_message(user, null, MSG_SELF(span_notice("You accidentally pushed your finger against the supermatter!")), MSG_OTHERS(span_warning("Ouch! While pushing on the release to open the [src], %U%'s finger slipped right as the case opened, pressing their finger firm against the supermatter!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_PAIN, 50, BP_L_HAND, src)
					user.injure(INJURY_RADIATION, 40, BP_L_HAND, src)
					user.injure(INJURY_BURN, 30, BP_L_HAND, src)
					user.injure(INJURY_TOXIN, 20, BP_L_HAND, src)
					user.injure(INJURY_ELECTRIC, 10, BP_L_HAND, src)
					user.apply_effect(25, STUTTER)
					user.apply_effect(15, SLUR)
					user.apply_effect(5, STUN)
				else			// This one is VERY punishing, you get a ton of damage, a lot of pain, and a minor stun. Once the stun goes away you'll be stuttering for awhile as if in crit.
					user.injure(INJURY_PAIN, 50, BP_R_HAND, src)
					user.injure(INJURY_RADIATION, 40, BP_R_HAND, src)
					user.injure(INJURY_BURN, 30, BP_R_HAND, src)
					user.injure(INJURY_TOXIN, 20, BP_R_HAND, src)
					user.injure(INJURY_ELECTRIC, 10, BP_R_HAND, src)
					user.apply_effect(25, STUTTER)
					user.apply_effect(15, SLUR)
					user.apply_effect(5, STUN)
			if(78 to 88)
				act_message(user, null, MSG_SELF(span_notice("You manage to pinch yourself on the case!")), MSG_OTHERS(span_notice("%U% managed to pinch themselves on the case of their [src]... it could have been worse.")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_CELLULAR, 1, BP_L_HAND, src)
					user.injure(INJURY_PAIN, 1, BP_L_HAND, src)
				else			// Aside from the base, this one isn't punishing outside of giving you genetic damage.
					user.injure(INJURY_CELLULAR, 1, BP_R_HAND, src)
					user.injure(INJURY_PAIN, 1, BP_R_HAND, src)
			if(89 to 99)
				act_message(user, null, MSG_SELF(span_notice("You find yourself looking at the supermatter for longer than you should...")), MSG_OTHERS(span_notice("%U% opened the [src] but forgot that you aren't supposed to look at supermatter!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_PAIN, 15, BP_L_HAND, src)
					user.apply_effect(5, WEAKEN)
					user.injure(INJURY_RADIATION, 15, BP_L_HAND, src)
					user.apply_effect(100, EYE_BLUR)
					user.apply_effect(50, AGONY)
					user.add_oxygen_debt(5, src)
					user.status_set(STAT_BLURRY, 10)
				else			// This one just blinds and blurs your screen, but otherwise doesn't actually risk harming you. Even the oxy damage heals on its own.
					user.injure(INJURY_PAIN, 15, BP_R_HAND, src)
					user.apply_effect(5, WEAKEN)
					user.injure(INJURY_RADIATION, 15, BP_L_HAND, src)
					user.apply_effect(100, EYE_BLUR)
					user.apply_effect(50, AGONY)
					user.add_oxygen_debt(15, src)
					user.status_set(STAT_BLURRY, 10)
			if(100)				// This is the part that makes it admin only for the moment, it spawns 500 rads from the carbon's position, and dusts the carbon instantly. It does also drop everything unlike the supermatter crystal though, so hopefully you won't lose any items if you fumble this badly!
				act_message(user, src, MSG_SELF(span_danger("You almost dropped your [src], thank goodness you caught it! By the glowing crystal within. You find your ears filled with unearthly ringing and your last thought is \"Oh, fuck.\"")), MSG_OTHERS(span_warning("OH NO! %U% almost dropped their live %T%! Thank goodness they caught it... by the glowing yellow crystal... oh.")))
				user.drop_r_hand() // To ensure the lighter is dropped <3
				user.drop_l_hand() // To ensure the lighter is dropped <3
				for(var/obj/item/e in user)
					user.drop_from_inventory(e)
				log_and_message_admins("[user] dusted themselves and caused massive radiation with [src]!",user)
				user.dust()
				radiation_pulse(
					src,
					max_range = 12,
					threshold = RAD_HEAVY_INSULATION,
					chance = URANIUM_IRRADIATION_CHANCE * 2,
					strength = 300
				)
		set_light(5)
	else
		set_lit(0)
		icon_state = "[base_state]"
		item_state = "[base_state]"
		playsound(src, deactivation_sound, 75, 1)
		if (istype(src, /obj/item/flame/lighter/supermatter/expsmzippo))
			act_message(user, src, others = span_notice(span_rose("You hear a quiet click, as %U% closes %T%.")))
		else
			act_message(user, src, others = span_notice("%U% quietly shuts %T%."))

		set_light(0)
	return OP_OK

/obj/item/flame/lighter/supermatter/expsmzippo/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if (lit == 1)
		M.ignite_mob()
		add_attack_logs(user, M, "Lit on fire with [src]")

	if (istype(M.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/smokable/cigarette) && user.zone_sel.selecting == O_MOUTH && lit)
		var/obj/item/clothing/mask/smokable/cigarette/cig = M.get_equipped_item(SLOT_ID_MASK)
		if (M == user)
			cig.attackby(src, user)
		else
			if (istype(src, /obj/item/flame/lighter/supermatter/expsmzippo))
				cig.light(span_notice(span_rose("[user] whips the [name] out and holds it for [M].")))
			else
				cig.light(span_notice("[user] holds the [name] out for [M], and lights the [cig.name]."))
	else
		..()

/// Lights up the turf the match landed on, then goes out.
/obj/item/flame/match/proc/burn_out_where_dropped()
	var/turf/location = loc
	if(istype(location))
		location.hotspot_expose(700, 5)
	burn_out()
