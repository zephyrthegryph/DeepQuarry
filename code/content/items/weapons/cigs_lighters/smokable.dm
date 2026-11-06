//////////////////
//FINE SMOKABLES//
//////////////////
/obj/item/clothing/mask/smokable
	name = DEVELOPER_WARNING_NAME // "smokable item"
	desc = "You're not sure what this is. You should probably ahelp it."
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
	flags = NOREACT // so it doesn't react until you light it

/// Smokes (smokable_step) every 2 s while lit.
/obj/item/clothing/mask/smokable/var/lit = 0

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
	configure(item_worn(covers = 0))
	configure(item_sounds(drop = SFX_ITEMS_CIGS_LIGHTERS_CIG_SNUFF))
	reagents(nameof(chem_volume))
	every(2 SECONDS, then(PROC_REF(smokable_step)), when = nameof(lit))
	op("item_applied", item(/obj/item), passes(), when(req(PROC_REF(held_is_another))), then(PROC_REF(item_applied)))
	derives(nameof(max_smoketime), PROC_REF(full_smoketime))

/// A click with the held item on itself is the in-hand use, not an item applied to it.
/obj/item/clothing/mask/smokable/proc/held_is_another(datum/act/op/A)
	return (A.held != src) ? null : /datum/msg/req_failed

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
	set_item_state(wanted)

/// What it starts smoking down from (derives(), at init): a type that sets none starts full.
/obj/item/clothing/mask/smokable/proc/full_smoketime()
	return max_smoketime || smoketime

/obj/item/clothing/mask/smokable/proc/smoke(amount)
	if(smoketime > max_smoketime)
		set_smoketime(max_smoketime)
	set_smoketime(smoketime - amount)
	smoke_reagents(src, amount)

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

/obj/item/clothing/mask/smokable/proc/light(flavor_text, mob/user)
	if(isnull(flavor_text))
		flavor_text = "[user] lights the [name]."
	if(!src.lit)
		set_lit(1)
		play_sfx(src, SFX_ITEMS_CIGS_LIGHTERS_CIG_LIGHT)
		set_injury_kind(INJURY_BURN)
		if(ignite_smoke_reagents(src))
			return
		var/turf/T = get_turf(src)
		T.visible_message(flavor_text)
		set_glow(src, GLOW(2, 0.25, "#E38F46"))

/obj/item/clothing/mask/smokable/proc/die(nomessage = 0)
	var/turf/T = get_turf(src)
	set_glow(src, GLOW(0, null, null))
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
	if(istype(M) && stat_value(M, STAT_ON_FIRE))
		user.do_attack_animation(M)
		light(span_notice("[user] coldly lights the [name] with the burning body of [M]."), user)
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
		light(text, user)
	return OP_OK

/obj/item/clothing/mask/smokable/water_act(amount)
	if(amount >= 5)
		quench()
