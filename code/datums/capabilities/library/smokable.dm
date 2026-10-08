// cap_smokable(): the holder (an item) is lit with something hot ("Light" with a match or lighter held,
// use_on), burns for burn_time, and goes out on its own or when put out. While lit it puffs every
// 2 seconds: its reagents go into the mouth of whoever wears it as a mask, else a little burns away
// (smoke_reagents(), shared with cigarettes). "Take a drag" (also its use in hand) draws `drag`
// units into the smoker and burns that much faster. Lighting sets off phoron or fuel in it
// (ignite_smoke_reagents()). Burnt out, it leaves `butt` (and is gone), or stays as a burnt husk.
//
//	/obj/item/clothing/mask/cheroot/capabilities()
//		. = ..()
//		. += cap_smokable(burn_time = 8 MINUTES, butt = /obj/item/trash/cigbutt, lit_state = "cheroot_on", burnt_state = "cheroot_burnt")
//
// Lit is the CAP_LIT bit; the burn time left lives in the capability data. The puff runs in the
// holder's cap_smokable timer slot (moves to a periodic lane through systems() once the core has it).

/// Time between two puffs while lit (the old smokable's periodic step).
#define SMOKABLE_PUFF_EVERY (2 SECONDS)
/// Units one puff moves.
#define SMOKABLE_PUFF_UNITS 1

/datum/capability/smokable
	data_type = /datum/cap_smokable_data
	log = LOG_GAME
	works_broken = TRUE
	works_unpowered = TRUE
	/// How long it burns from fresh.
	var/burn_time = 10 MINUTES
	/// Units one drag draws.
	var/drag = 5
	/// Left behind when it burns out (the holder is then gone), or null to stay as a burnt husk.
	var/butt
	/// The held items that light it (they must be hot, is_hot()).
	var/list/light_types
	/// The icon_state while lit / once partly burnt, or null.
	var/lit_state
	var/burnt_state

/datum/cap_smokable_data
	/// Burn time left; null while fresh.
	var/burn_left

/proc/cap_smokable(burn_time = 10 MINUTES, drag = 5, butt, list/light_types = list(/obj/item/flame, /obj/item/weldingtool, /obj/item/assembly/igniter), lit_state, burnt_state, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/smokable/C = new
	C.burn_time = burn_time
	C.drag = drag
	C.butt = butt
	C.light_types = light_types
	C.lit_state = lit_state
	C.burnt_state = burnt_state
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered)
	return C

/datum/capability/smokable/interactions(atom/holder)
	// "light" (a click with a lighter, match...), "take_drag" (the self-use: using it in hand takes a drag) and "put_out"
	// (ACT_NONE).
	var/datum/interaction/capability/light = adopt_entry(lib_op("Light", GLOBAL_PROC_REF(cap_smokable_light), OP_SHAPE_USE_ON, using = light_types, key = "light", needs = GLOBAL_PROC_REF(cap_smokable_can_light), works_broken = TRUE, works_unpowered = TRUE))
	var/datum/interaction/capability/drag_entry = adopt_entry(lib_op("Take a drag", GLOBAL_PROC_REF(cap_smokable_drag), OP_SHAPE_HAND, key = "take_drag", offered = req_self_held(), needs = GLOBAL_PROC_REF(cap_smokable_is_lit), else_say = "it isn't lit", works_broken = TRUE, works_unpowered = TRUE))
	drag_entry.entry = INTERACTION_ENTRY_SELF
	var/datum/interaction/capability/snuff = adopt_entry(lib_op("Put out", GLOBAL_PROC_REF(cap_smokable_put_out), OP_SHAPE_HAND, key = "put_out", action = ACT_NONE, needs = GLOBAL_PROC_REF(cap_smokable_is_lit), else_say = "it isn't lit", works_broken = TRUE, works_unpowered = TRUE))
	return list(light, drag_entry, snuff)

/datum/capability/smokable/examine(atom/holder, mob/user)
	var/obj/item/I = holder
	var/left_percent = round(cap_smokable_burn_left(I) / burn_time * 100)
	. = list()
	if(cap_has(holder, CAP_LIT))
		. += "It's lit."
	switch(left_percent)
		if(90 to INFINITY)
			. += "It is still fresh."
		if(60 to 90)
			. += "It has a good amount of burn time remaining."
		if(30 to 60)
			. += "It is about half finished."
		if(10 to 30)
			. += "It is starting to burn low."
		if(1 to 10)
			. += "It is nearly burnt out!"
		else
			. += "It is burnt out."

/datum/capability/smokable/draw(atom/holder, datum/look/look)
	if(cap_has(holder, CAP_LIT))
		if(lit_state)
			look.state(lit_state)
		return
	var/datum/cap_smokable_data/D = capability_data(holder)?[key]
	if(burnt_state && !isnull(D?.burn_left))
		look.state(burnt_state)

/// Burn time I has left.
/proc/cap_smokable_burn_left(obj/item/I)
	var/datum/capability/smokable/C = cap_of(I, /datum/capability/smokable)
	var/datum/cap_smokable_data/D = capability_data(I)?[C.key]
	return isnull(D?.burn_left) ? C.burn_time : D.burn_left

/// Burns `amount` of I's time; a burnt out I goes out. TRUE while it still burns.
/proc/cap_smokable_burn(obj/item/I, amount)
	var/datum/capability/smokable/C = cap_of(I, /datum/capability/smokable)
	var/datum/cap_smokable_data/D = cap_data(I, C)
	D.burn_left = max(0, cap_smokable_burn_left(I) - amount)
	changed(I, CHANGE_CAPABILITY)
	if(D.burn_left <= 0)
		cap_smokable_burn_out(I)
		return FALSE
	return TRUE

/// Lights I. FALSE when it exploded instead (phoron, fuel) or was already lit.
/proc/cap_smokable_ignite(obj/item/I)
	if(cap_has(I, CAP_LIT))
		return FALSE
	if(ignite_smoke_reagents(I))
		return FALSE
	cap_set(I, CAP_LIT, TRUE)
	play_sfx(I, SFX_ITEMS_CIGS_LIGHTERS_CIG_LIGHT)
	I.set_light(2, 0.25, "#E38F46")
	after(I, SMOKABLE_PUFF_EVERY, GLOBAL_PROC_REF(cap_smokable_puff), key = "cap_smokable", with = list(I))
	return TRUE

/// Puts I out (still smokable if it has burn time left).
/proc/cap_smokable_extinguish(obj/item/I)
	if(!cap_has(I, CAP_LIT))
		return FALSE
	cap_set(I, CAP_LIT, FALSE)
	cancel_after(I, "cap_smokable")
	I.set_light(0)
	play_sfx(I, SFX_ITEMS_CIGS_LIGHTERS_CIG_SNUFF)
	return TRUE

/// One puff of lit I: reagents into its wearer's mouth, heat on its turf, burn time down.
/proc/cap_smokable_puff(obj/item/I)
	if(QDELETED(I) || !cap_has(I, CAP_LIT))
		return
	smoke_reagents(I, SMOKABLE_PUFF_UNITS)
	var/turf/T = get_turf(I)
	T?.hotspot_expose(700, 5)
	if(cap_smokable_burn(I, SMOKABLE_PUFF_EVERY))
		after(I, SMOKABLE_PUFF_EVERY, GLOBAL_PROC_REF(cap_smokable_puff), key = "cap_smokable", with = list(I))

/// I burnt out: it goes out, and leaves its butt (and is gone) or stays burnt with its reagents gone.
/proc/cap_smokable_burn_out(obj/item/I)
	var/datum/capability/smokable/C = cap_of(I, /datum/capability/smokable)
	cap_smokable_extinguish(I)
	var/mob/living/M = ismob(I.loc) ? I.loc : null
	if(M)
		to_chat(M, span_notice("Your [I.name] goes out."))
	if(!C.butt)
		I.reagents?.clear_reagents()
		return
	var/obj/item/butt = new C.butt(get_turf(I))
	I.transfer_fingerprints_to(butt)
	if(M)
		M.remove_from_mob(I)
	consume(I, M)

// ---- handlers ----

/proc/cap_smokable_is_lit(mob/user, obj/item/holder, obj/item/held)
	return cap_has(holder, CAP_LIT)

/proc/cap_smokable_can_light(mob/user, obj/item/holder, obj/item/held)
	if(cap_has(holder, CAP_LIT))
		return "it's already lit"
	if(cap_smokable_burn_left(holder) <= 0)
		return "it's burnt out"
	if(!held?.is_hot())
		return "\the [held] isn't lit"
	return TRUE

/proc/cap_smokable_light(obj/item/holder, mob/user, obj/item/held)
	var/name_was = holder.name
	if(!cap_smokable_ignite(holder))
		if(QDELETED(holder))
			act_message(user, user, self = span_danger("\The [name_was] explodes!"), others = span_danger("%U%'s [name_was] explodes!"))
			return TRUE
		return refuse(user, "\The [holder] won't light.")
	act_message(user, holder, self = span_notice("You light %T% with \the [held]."), others = span_notice("%U% lights %T% with \the [held]."), item = held)
	return TRUE

/proc/cap_smokable_drag(obj/item/holder, mob/user, obj/item/held)
	var/reason = mouth_blocked_reason(user, user)
	if(reason)
		return refuse(user, capitalize("[reason]"))
	var/datum/capability/smokable/C = cap_of(holder, /datum/capability/smokable)
	to_chat(user, span_notice("You take a drag on \the [holder]."))
	play_sfx(holder, SFX_ITEMS_CIGS_LIGHTERS_INHALE)
	holder.reagents?.trans_to_mob(user, C.drag, CHEM_INGEST, 1.5, can_dialysis = FALSE)
	cap_smokable_burn(holder, C.drag * SMOKABLE_PUFF_EVERY)
	return TRUE

/proc/cap_smokable_put_out(obj/item/holder, mob/user, obj/item/held)
	cap_smokable_extinguish(holder)
	act_message(user, holder, self = span_notice("You put out %T%."), others = span_notice("%U% puts out %T%."))
	return TRUE

#undef SMOKABLE_PUFF_EVERY
#undef SMOKABLE_PUFF_UNITS
