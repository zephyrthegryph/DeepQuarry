//todo: toothbrushes, and some sort of "toilet-filthinator" for the hos

/// The toilet's contents changed (what a hand finds in the cistern).
#define TOILET_CISTERN_KEY "toilet_cistern"
/// The biowaste tank's filter caught or let go of something.
#define BIOWASTE_CAUGHT_KEY "biowaste_caught"
#define SHOWER_FREEZING "freezing"
#define SHOWER_TEMP_FREEZING T0C
#define SHOWER_NORMAL "normal"
#define SHOWER_TEMP_NORMAL 293
#define SHOWER_BOILING "boiling"
#define SHOWER_TEMP_BOILING T0C + 100

/obj/structure/toilet
	name = "toilet"
	desc = "The HT-451, a torque rotation-based, waste disposal unit for small matter. This one seems remarkably clean."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "toilet"
	density = FALSE
	anchored = TRUE
	var/open = FALSE			//if the lid is up
	var/cistern = FALSE			//if the cistern bit is open
	var/w_items = 0				//the combined w_class of all the items in the cistern

	/// Used to both track the crystal needed to upgrade the toilet, and to tell if the toilet is teleplumbed. Set to True in subtypes or mapping if you'd like it to be teleplumbed on init.
	var/obj/item/teleplumb_crystal = null
	/// Bin used to upgrade this toilet. Turned into a real object on init.
	var/obj/item/stock_parts/matter_bin/bin	= /obj/item/stock_parts/matter_bin

	//Flushing stuff
	var/panic_mult = 1
	var/refilling = FALSE
	/// Relation view: the mob being given a swirlie.
	var/mob/living/swirlie_mob
	/// Relation view: the destination of this toilet if it's teleplumbed.
	var/atom/teleplumb_dest
	var/list/currently_held_objects //List of objects currently in the toilet, used for flushing.
	COOLDOWN_DECLARE(panic_flush)

TRACKED(/obj/structure/toilet, open)

TRACKED(/obj/structure/toilet, cistern)

TRACKED(/obj/structure/toilet, refilling)

CAPABILITIES(/obj/structure/toilet)
	hose_sockets(list(/datum/hose_connector/endless_drain))
	owns_one(nameof(bin), /obj/item/stock_parts/matter_bin, starts = nameof(bin))
	owns_one(nameof(teleplumb_crystal), /obj/item)
	ref_one(nameof(swirlie_mob), /mob/living)
	ref_one(nameof(teleplumb_dest))
	op("use_wrench", tool(TOOL_WRENCH), wait(5 SECONDS), needs(req_bool(PROC_REF(cistern_open), silent = TRUE), req_bool(PROC_REF(not_refilling), because = MSG(toilet/refilling))), begins(MSG(toilet/dismantling)), then(PROC_REF(wrench_act_done)))
	op("use_crowbar", tool(TOOL_CROWBAR), wait(3 SECONDS), begins(PROC_REF(crowbar_begins)), plays(SFX_EFFECTS_STONEDOOR_OPENCLOSE, at_start = TRUE), then(PROC_REF(crowbar_act_done)))
	rolls(nameof(open), range_of(0, 1))   // the lid starts up or down
	// the old attack_hand: slam the swirlie victim, loot the cistern (a person may take the teleplumbing crystal from an empty one, after a yes), or the lid
	op("use", hand(), label("Use"),
		asks(/datum/prompt/yes_no, fields = list("title" = "Toilet Crystal", "question" = "You see a glimmering crystal attached to parts of the toilet's components... Do you want to take it?", "yes_text" = "Take it!", "no_text" = "Leave it.", "timeout" = 0), step = "crystal", when = PROC_REF(offers_crystal)),
		then(PROC_REF(interaction_hand)))
	// the old attack_ai: the hand's Use for a silicon, except a cyborg that is remote viewing or has no player
	op("silicon_use", remote(), label("Use"), needs(req(PROC_REF(silicon_at_hand), silent = TRUE)), then(PROC_REF(interaction_hand)))
	op("swirlie", item(/obj/item/grab), label("Give a swirlie"), priority(OP_PRIORITY_DEFAULT), when(PROC_REF(swirlie_possible)), starts(PROC_REF(swirlie_started)), begins(PROC_REF(swirlie_begins)), wait(3 SECONDS), then(PROC_REF(swirlie_done)))
	op("insert_crystal", item(/obj/item/bluespace_crystal), label("Insert"), priority(OP_PRIORITY_DEFAULT), when(PROC_REF(crystal_slot_free)), begins(MSG(toilet/inserting_crystal)), wait(2 SECONDS), then(PROC_REF(crystal_inserted)))
	op("replace_bin", item(/obj/item/stock_parts/matter_bin), label("Replace the bin"), priority(OP_PRIORITY_DEFAULT), when(nameof(cistern)), begins(PROC_REF(bin_begins)), wait(2 SECONDS), then(PROC_REF(bin_replaced)))
	op("item", item(/obj/item), label("Use"), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), then(PROC_REF(interaction_item)))
	op("item_cyborg", item(/obj/item), label("Use"), when(req_actor_kind(/mob/living/silicon/robot)), then(PROC_REF(interaction_item_cyborg)))
	// the old click_alt: pull the flush lever (a living, conscious actor; the lid open)
	op("flush_yank", hand(), ungated(), gesture(GESTURE_ALT), stance(I_HURT), label("Yank the flush lever"), when(req_actor_kind(/mob/living)),
		needs(req_conscious(), req_is(nameof(open), TRUE, because = MSG(toilet/lid_closed))), then(PROC_REF(interaction_alt_harm)))
	op("flush", hand(), ungated(), gesture(GESTURE_ALT), stance(I_HELP, I_DISARM, I_GRAB), label("Flush"), when(req_actor_kind(/mob/living)),
		needs(req_conscious(), req_is(nameof(open), TRUE, because = MSG(toilet/lid_closed))), then(PROC_REF(interaction_alt)))

/obj/structure/toilet/Initialize(mapload)
	. = ..()

	if(teleplumb_crystal)
		rel_set(src, nameof(teleplumb_crystal), new /obj/item/bluespace_crystal(src))
		rel_set(src, nameof(teleplumb_dest), locate(/obj/effect/landmark/teleplumb_exit))
		desc = "The BS-500, a bluespace rift-rotation-based waste disposal unit for small matter. This one seems remarkably clean."

	// Non-bluespace plumbing. For POIs and player construction n' stuff.
	var/obj/structure/disposalpipe/trunk/trunk = locate_on(get_turf(src), /obj/structure/disposalpipe/trunk)
	add_disposal_connection(FALSE) //Dont show our disposal connection, and we want to handle failed flushes on our own.
	observe(src, /datum/notice/disposal_receive, src, then(PROC_REF(toilet_reflux)))
	if(trunk)
		PUBLISH_LEGACY(src, /datum/notice/disposal_link, trunk)

// non-basic bins, the teleplumb crystal and flushed objects drop out
// (before phase 4 deletes the owned bin).
/obj/structure/toilet/lifecycle_prerelease()
	..()
	if(bin)
		if(bin.type == /obj/item/stock_parts/matter_bin) //Specifically, if this is a basic bin, you dont get it back. Other bins are returned.
			rel_clear(src, nameof(bin))
		else
			bin.forceMove(src.loc)
			rel_take(src, nameof(bin))
	if(teleplumb_crystal)
		teleplumb_crystal.forceMove(src.loc)
		rel_take(src, nameof(teleplumb_crystal))
	for(var/atom/movable/AM in currently_held_objects)
		AM.forceMove(src.loc)
	rel_clear(src, nameof(currently_held_objects))

/// The look (the draw sweep: from its template).
/obj/structure/toilet/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][open][cistern]")

/// The hand finds the teleplumbing crystal: the cistern is open (lid down) and holds nothing else, and a person is looking.
/obj/structure/toilet/proc/offers_crystal(datum/act/op/A)
	return cistern && !open && teleplumb_crystal && ishuman(A.actor) && !swirlie_mob && !cistern_loot_count()

/// What lies in the cistern besides its bin and its crystal.
/obj/structure/toilet/proc/cistern_loot_count()
	. = 0
	FOR_REAL_CONTENTS(var/atom/movable/AM, src)
		if(AM != bin && AM != teleplumb_crystal)
			.++
READS_AS(/obj/structure/toilet/proc/cistern_loot_count, TOILET_CISTERN_KEY)

/// What is in the toilet changed: a hand that would look for the crystal asks again.
/obj/structure/toilet/on_slot_changed(slot_id, atom/movable/thing, inserted)
	. = ..()
	PUBLISH_CHANGE(src, TOILET_CISTERN_KEY)

/// The crystal question was answered: a yes takes it.
/obj/structure/toilet/proc/crystal_answered(mob/living/user, datum/prompt/R)
	if(!R.value || !teleplumb_crystal || !cistern)
		to_chat(user, span_notice("You decide to leave it."))
		return
	user.put_in_hands(teleplumb_crystal)
	to_chat(user, span_notice("You take \the [teleplumb_crystal]."))
	rel_take(src, nameof(teleplumb_crystal))
	rel_clear(src, nameof(teleplumb_dest))
	desc = initial(desc)

/// A silicon's hand is its own: a cyborg uses the toilet only from its body, with a player in it.
/obj/structure/toilet/proc/silicon_at_hand(datum/act/op/A)
	return (read_once(silicon_in_body(A.actor))) ? null : /datum/msg/req_silent // a player's presence is asked when the click is made

/// Is `user` a silicon acting from its own body (not a cyborg remote viewing, or one with no player)?
/obj/structure/toilet/proc/silicon_in_body(mob/user)
	return !(isrobot(user) && (!user.client || user.is_remote_viewing()))

MSG_DEF_SELF(toilet/lid_closed, "You need to open the lid before flushing it.")

/// Old attack_hand: slam the swirlie victim, loot the cistern, or open/close the lid.
/obj/structure/toilet/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/swirlie = swirlie_mob
	if(swirlie)
		user.setClickCooldown(user.get_attack_speed())
		act_message(user, null, MSG_SELF(span_notice("You slam the toilet seat onto [swirlie.name]'s head!")), \
			MSG_OTHERS(span_danger("%U% slams the toilet seat onto [swirlie.name]'s head!")), \
			MSG_BLIND("You hear reverberating porcelain."))
		swirlie.injure(INJURY_BLUNT, 5, BP_HEAD, src)
		return OP_OK

	if(cistern && !open)
		var/list/cistern_loot = list()
		for(var/atom/movable/AM in contents)
			if(AM == bin || AM == teleplumb_crystal)
				continue
			cistern_loot += AM

		if(!length(cistern_loot))
			//You can take the bluespace crystal out if there's nothing else in the cistern.
			var/datum/prompt/asked = A.step_answers?["crystal"]
			if(asked) //Only humans can grief the toilets: the op asked them about the crystal
				crystal_answered(user, asked)
				return OP_OK
			to_chat(user, span_notice("The cistern is empty."))
			return OP_OK
		var/obj/item/I = pick(cistern_loot)
		if(ishuman(user))
			user.put_in_hands(I)
		else
			I.forceMove(get_turf(src))
		to_chat(user, span_notice("You find \an [I] in the cistern."))
		w_items -= I.w_class
		return OP_OK

	set_open(!open)
	return OP_OK

/// Old attackby: give a grabbed mob a swirlie, insert a crystal/bin, or fill the cistern.
/obj/structure/toilet/proc/interaction_item(datum/act/op/A)
	return toilet_item_used(A, FALSE)

/// A cyborg's module never goes in the cistern.
/obj/structure/toilet/proc/interaction_item_cyborg(datum/act/op/A)
	return toilet_item_used(A, TRUE)

/obj/structure/toilet/proc/toilet_item_used(datum/act/op/A, cyborg)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/grab))
		user.setClickCooldown(user.get_attack_speed(I))
		var/obj/item/grab/G = I

		if(isliving(G?.grab_target()))
			var/mob/living/GM = G?.grab_target()

			if(G.state <= GRAB_PASSIVE)
				to_chat(user, span_notice("You need a tighter grip."))
				return OP_OK
			if(GM.loc != get_turf(src))
				to_chat(user, span_notice("[GM.name] needs to be on the toilet."))
				return OP_OK
			// the swirlie itself is the "swirlie" op; anything else slams the head
			act_message(user, GM, MSG_SELF(span_notice("You slam %T% into the [src]!")), MSG_OTHERS(span_danger("%U% slams %T% into the [src]!")))
			GM.injure(INJURY_BLUNT, 5, BP_HEAD, src)

	if(cistern && !cyborg) //STOP PUTTING YOUR MODULES IN THE TOILET.
		if(I.w_class > ITEMSIZE_NORMAL) //3
			to_chat(user, span_notice("\The [I] does not fit."))
			return OP_OK
		if(w_items + I.w_class > ITEMSIZE_COST_TINY * 5) // 5 tiny or 2 small and 1 tiny
			to_chat(user, span_notice("The cistern is full."))
			return OP_OK
		if(!own_bring_in(src, nameof(contents), I, null, user, TRUE, null, FALSE))
			return OP_OK
		w_items += I.w_class
		to_chat(user, "You carefully place \the [I] into the cistern.")
		return OP_OK
	return OP_DECLINE

/// Requirement: a grab holding a mob tightly on the open toilet, with nobody already in it.
/obj/structure/toilet/proc/swirlie_possible(datum/act/op/A)
	var/obj/item/grab/G = A.held
	if(!istype(G) || !open || swirlie_mob)
		return FALSE
	var/mob/living/GM = G.grab_target()
	if(!isliving(GM) || read_once(G.state <= GRAB_PASSIVE))
		return FALSE
	return read_once(GM.loc == get_turf(src))

/obj/structure/toilet/proc/swirlie_started(datum/act/op/A)
	var/mob/living/user = A.actor
	user.setClickCooldown(user.get_attack_speed(A.held))

/obj/structure/toilet/proc/swirlie_begins(datum/act/op/A)
	var/obj/item/grab/G = A.held
	var/mob/living/GM = G.grab_target()
	return msg_text(span_notice("You start to give [GM] a swirlie!"), span_danger("[A.actor] starts to give [GM] a swirlie!"))

/obj/structure/toilet/proc/swirlie_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/grab/G = A.held
	var/mob/living/GM = G.grab_target()
	if(!isliving(GM))
		return OP_OK
	if(!open) //Someone closed it while we were trying to swirlie. Rude.
		set_open(TRUE) //Open it.
	if(!refilling)
		act_message(user, GM, MSG_SELF(span_notice("You give %T% a swirlie!")), \
			MSG_OTHERS(span_danger("%U% gives %T% a swirlie!")), \
			MSG_BLIND("You hear a toilet flushing."))
		if(!GM.internal)
			GM.body?.add_restriction(src, BF_AIRWAY, 0, 5 SECONDS) // a faceful of water
		if(GM.size_multiplier <= 0.75)
			act_message(GM, src, MSG_SELF(span_userdanger("You get sucked into %T%!")), \
				MSG_OTHERS(span_danger("%U% gets sucked into %T% due to their small size!")))
			GM.forceMove(get_turf(src))
			GM.status_at_least(STAT_WEAKENED, 5)
		flush()
	else
		act_message(user, GM, MSG_SELF(span_warning("You cant give %T% swirlie while \the [src] is still refilling!")), \
			MSG_OTHERS(span_warning("%U% tries to give [GM.name] a swirlie, but the toilet was still refilling!")))
	return OP_OK

MSG_DEF_SELF(toilet/inserting_crystal, span_notice("You begin to insert %I% into %T%..."))

/// The cistern is open and has no teleplumbing crystal yet.
/obj/structure/toilet/proc/crystal_slot_free(datum/act/op/A)
	return cistern && !teleplumb_crystal

/obj/structure/toilet/proc/crystal_inserted(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	to_chat(user, span_notice("You insert \the [I] into \the [src]. A deep rumble eminates from within it, and a faint blue glow eminates from the bottom of the bowl for a moment."))
	user.drop_item()
	I.forceMove(src)
	own_move(I, src, nameof(teleplumb_crystal))
	//TODO: add a way to link this to custom destinations.
	rel_set(src, nameof(teleplumb_dest), locate(/obj/effect/landmark/teleplumb_exit))
	desc = "The BS-500, a bluespace rift-rotation-based waste disposal unit for small matter. This one seems remarkably clean."
	return OP_OK

/obj/structure/toilet/proc/bin_begins(datum/act/op/A)
	return msg_text(span_notice("You begin to replace \the [bin] in \the [src] with \the [A.held]."))

/obj/structure/toilet/proc/bin_replaced(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	to_chat(user, span_notice("You replace \the [bin] with \the [I]."))
	bin.forceMove(src.loc) //Remove the old bin.
	move_into(src, nameof(src.bin), I, user)
	return OP_OK

/// Old click_alt: pull the flush lever.
/obj/structure/toilet/proc/interaction_alt(datum/act/op/A)
	return toilet_lever_pulled(A, FALSE)

/// Combat mode: pulling the lever mid-flush makes the flush bigger.
/obj/structure/toilet/proc/interaction_alt_harm(datum/act/op/A)
	return toilet_lever_pulled(A, TRUE)

/obj/structure/toilet/proc/toilet_lever_pulled(datum/act/op/A, harm)
	var/mob/user = A.actor
	if(user.loc == src)
		return OP_OK
	if(refilling)
		to_chat(user, span_notice("The toilet is still refilling its tank."))
		play_sfx(src, SFX_MACHINES_DOOR_LOCKED)
		//Even while it's flushing, you can repeatedly pull down the lever for a bigger flush.
		if(harm)
			if(COOLDOWN_FINISHED(src, panic_flush))
				panic_mult++
				COOLDOWN_START(src, panic_flush, 1 SECOND) //Let's not encourage hitting the click-cap.
				act_message(user, null, MSG_SELF(span_notice("You full the flush lever mid-flush!")), \
					MSG_OTHERS(span_notice("%U% pulls the flush lever mid-flush!")), \
					MSG_BLIND("you hear the sound of a toilet handle being jiggled."))
				return OP_OK
			to_chat(user, span_notice("You need to wait [round((COOLDOWN_TIMELEFT(src, panic_flush)) / 10, 0.1)] more seconds longer before you can pull the flush lever again!"))
		return OP_OK
	//Flush succeeds
	act_message(user, null, MSG_SELF(span_notice("You flush the toilet.")), \
		MSG_OTHERS(span_notice("%U% flushes the toilet.")), \
		MSG_BLIND("you hear a toilet flushing."))
	flush()
	return OP_OK

/obj/structure/toilet/proc/flush()
	set_refilling(TRUE)
	play_sfx(src, SFX_VORE_DEATH7) //Got lazy about getting new sound files. Have a sick remix lmao.
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	play_sfx(src, SFX_MECHA_POWERUP)

	var/list/bowl_contents = list()
	for(var/obj/item/I in turf_contents_of_type(loc, /obj/item))
		if(istype(I) && !I.anchored)
			bowl_contents += I
	for(var/mob/living/L in turf_contents_of_type(loc, /mob/living))
		if(L?.buckled_to() || !(L.resting || L.lying))
			continue
		var/bin_bonus = 0.15
		if(bin)
			bin_bonus *= bin.rating
		if(L.size_multiplier <= 0.6 + bin_bonus)
			bowl_contents += L

	if(!length(bowl_contents)) //Reduced recharge if nothing is being flushed
		after(src, 7.5 SECONDS, PROC_REF(refill_done), with = list(TRUE))
		return

	begin_flush(bowl_contents[1], bowl_contents)
	return

/// after() target: the tank has refilled (and a dry flush also calms the panic lever).
/obj/structure/toilet/proc/refill_done(reset_panic)
	set_refilling(FALSE)
	if(reset_panic)
		panic_mult = initial(panic_mult)

///Timer proc that takes the object given and begins the flush process. Makes the object spin.
/obj/structure/toilet/proc/begin_flush(atom/movable/flushed, list/pick_list)
	flushed.SpinAnimation(5,3)
	after(src, 0.2 SECONDS, PROC_REF(secondary_flush), with = list(flushed, pick_list))

///Timer proc that takes the object given and removes it from the list, beginning to spin the next object if there is one.
/obj/structure/toilet/proc/secondary_flush(atom/movable/flushed, list/pick_list)
	pick_list -= flushed

	if(!length(pick_list)) //All flushed.
		after(src, 1.5 SECONDS, PROC_REF(tertiary_flush), with = list(flushed, TRUE), keeps_dead = TRUE)
		return
	after(src, 1.5 SECONDS, PROC_REF(tertiary_flush), with = list(flushed, FALSE)) //Put the object in the bin.

	var/obj_to_be_flushed = pick_list[1]
	after(src, 0.2 SECONDS, PROC_REF(begin_flush), with = list(obj_to_be_flushed, pick_list))

///Adds the object to the toilet's current_flush list.
/obj/structure/toilet/proc/tertiary_flush(atom/movable/flushed, flush_completed)
	if(!QDELETED(flushed) && flushed.loc == loc)
		flushed.forceMove(src)
		rel_add(src, nameof(currently_held_objects), flushed)

	if(flush_completed) //Flushed it all.
		after(src, 1 SECOND, PROC_REF(flush_send), with = list(currently_held_objects))
		after(src, 20 SECONDS, PROC_REF(refill_done), with = list(FALSE))
		return

/obj/structure/toilet/proc/flush_send(list/to_send)
	var/flush_weight = 0
	var/max_flush_weight = get_flush_power()
	var/list/taken_contents = list()
	for(var/atom/movable/flushed in to_send)
		if(flushed.loc != src)
			continue

		//Mobs and items are calculated differently
		var/weight_value = 0
		if(isitem(flushed))
			var/obj/item/I = flushed
			weight_value = I.w_class
		if(isliving(flushed))
			var/mob/living/L = flushed
			weight_value = L.size_multiplier * 10

		if(flush_weight + weight_value <= max_flush_weight)
			taken_contents += flushed
			flush_weight += weight_value
			if(teleplumb_crystal && teleplumb_dest)
				if(isliving(flushed))
					var/mob/living/m = flushed
					to_chat(m, span_danger("You're glunked down by \the [src] through a series of extradimensional bluespace pipeworks!"))
				flushed.forceMove(teleplumb_dest)

	var/datum/gas_mixture/air_contents = new(1) //1 liter of nothing, ig.
	var/datum/act/flush_disposal/flush = ACT_TRY(src, flush_disposal, to_send, air_contents)
	if(!flush)
		for(var/atom/movable/flushed in to_send)
			if(isliving(flushed))
				var/mob/living/m = flushed
				to_chat(m, span_warning("You're flushed away by \the [src]!"))
	else
		act_cancel(flush) // nothing took the flush over: the toilet drops the contents itself, below

	var/flush_failed = FALSE
	for(var/atom/movable/flushed in to_send)
		if(flushed.loc != src) //Not in here, flushed or otherwise.
			continue
		flush_failed = TRUE
		flushed.forceMove(src.loc)
	if(flush_failed)
		visible_message(span_warning("\The [src] glurks and splutters, unable to guzzle more stuff down in a single flush!"), span_warning("Glornch"))
	panic_mult = initial(panic_mult)
	rel_clear(src, nameof(currently_held_objects)) //Clear the list.

/obj/structure/toilet/proc/toilet_reflux(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/disposal_receive/event = A
	var/list/received_items = event.items
	var/datum/gas_mixture/gas = event.gas
	var/turf/T = get_turf(src)
	T.assume_air(gas)

	if(!length(received_items))
		visible_message(span_warning("The water in \the [src] gurgles and bubbles ominously..."), span_notice("You hear a wet gurgling and spluttering..."), runemessage = "glurgles")
		return
	visible_message(span_danger("\The [src] gurgles for a moment, before spewing forth a bunch of stuff in a wave of toilet water!"), "GLORGLONCH!")
	for(var/atom/movable/AM in received_items)
		var/turf/target_turf = get_offset_target_turf(loc, rand(-2, 2), rand(-2, 2))

		AM.forceMove(T)
		AM.pipe_eject(0)
		AM.throw_at(target_turf, 5, 1)

	//Toilet blast !
	for(var/direction in GLOB.alldirs + null) // null is for the center tile.
		if(prob(75) && direction != null) //Only sometimes wet blast, except the center tile. That always wets.
			continue
		var/turf/target_turf = get_ranged_target_turf(src, direction, rand(1, 2))
		if(!target_turf) // This shouldn't fail but...
			continue
		var/obj/effect/effect/water/W = new(get_turf(T))
		W.create_reagents(15)
		W.reagents.add_reagent(REAGENT_ID_WATER, 15)
		W.set_color()
		W.set_up(target_turf)

/obj/structure/toilet/atom_deconstruct(disassembled)
	place_deconstruction_materials()
	for(var/atom/movable/AM in contents) //Should handle both cistern and upgrade parts.
		AM.forceMove(src.loc)

/obj/structure/toilet/proc/place_deconstruction_materials()
	new /obj/item/stack/material/steel(src.loc, 5)
	new /obj/item/reagent_containers/glass/bucket(src.loc)

/obj/structure/toilet/proc/get_flush_power()
	. = ITEMSIZE_COST_SMALL * 3 // 3 small items, or 6 tiny items.
	if(bin)
		. *= bin.rating
	. *= panic_mult
	if(teleplumb_crystal) //Teleplumbed gets applied at the end
		. *= 2

/obj/structure/toilet/teleplumbed
	teleplumb_crystal = TRUE

/obj/structure/toilet/prison
	name = "prison toilet"
	desc = "The HT-421, a torque rotation based waste disposal unit for small matter. This older model isnt quite as capable as newer units."
	icon_state = "toilet2"

/obj/structure/toilet/prison/place_deconstruction_materials()
	new /obj/item/stack/material/iron(src.loc, 5)
	new /obj/item/reagent_containers/glass/bucket(src.loc)

/obj/structure/toilet/prison/get_flush_power()
	. = ..()
	if(teleplumb_crystal) //No teleplumb bonus.
		. /= 2
	return round(. / 3) //Has a 1/3 the power of a normal toilet.

/obj/structure/toilet/prison/flush_send(list/to_send) //Permabrig escape prevention
	for(var/mob/living/escapee in to_send)
		to_chat(escapee, span_warning("A grate at the bottom of \the [src] prevents you from being flushed away!")) //Kinda gross, come to think of it.
		escapee.forceMove(src.loc)
		to_send -= escapee
	. = ..()

/obj/structure/urinal
	name = "urinal"
	desc = "The HU-452, an experimental urinal."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "urinal"
	density = FALSE
	anchored = TRUE

CAPABILITIES(/obj/structure/urinal)
	op("item", item(/obj/item/grab), label("Use"), then(PROC_REF(interaction_item)))

/obj/structure/urinal/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/grab/G = A.held
	var/mob/living/GM = G?.grab_target()
	if(isliving(GM))
		if(G.state>1)
			if(GM.loc != get_turf(src))
				to_chat(user, span_notice("[GM.name] needs to be on the urinal."))
				return TRUE
			act_message(user, src, MSG_SELF(span_notice("You slam [GM.name] into %T%!")), MSG_OTHERS(span_danger("%U% slams [GM.name] into %T%!")))
			GM.injure(INJURY_BLUNT, 8, BP_HEAD, src)
		else
			to_chat(user, span_notice("You need a tighter grip."))
	return TRUE

/obj/machinery/shower
	name = "shower"
	desc = "The HS-451. Installed in the 2550s by the Hygiene Division."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "shower"
	density = FALSE
	anchored = TRUE
	use_power = USE_POWER_OFF
	on = 0
	var/current_temperature = SHOWER_NORMAL		//SHOWER_FREEZING, SHOWER_NORMAL, or SHOWER_BOILING
	var/datum/looping_sound/showering/soundloop
	var/reagent_id = REAGENT_ID_WATER
	var/reaction_volume = 200

CAPABILITIES(/obj/machinery/shower)
	reagents(nameof(reaction_volume), starts_from = list(nameof(reagent_id) = nameof(reaction_volume)))
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(on), wakes_on = list(nameof(on)))
	owns_one(nameof(soundloop), /datum/looping_sound/showering, starts = /datum/looping_sound/showering)
	op("toggle", hand(), ungated(), label("Toggle"), then(PROC_REF(interaction_toggle)))
	op("analyze", item(/obj/item/analyzer), label("Check water temperature"), then(PROC_REF(interaction_analyze)))
	op("set_temperature", hand(), ungated(), gesture(GESTURE_ALT), label("Set temperature"), passes(),
		asks(/datum/prompt/choice, fields = list("title" = "Water Temperature Valve", "question" = "What setting would you like to set the temperature valve to?", "choices" = list("normal", "boiling", "freezing"), "timeout" = 0)),
		begins(MSG(shower/adjusting)), wait(5 SECONDS), then(PROC_REF(temperature_chosen)))

MSG_DEF_SELF(shower/adjusting, span_notice("You begin to adjust the temperature..."))

/obj/machinery/shower/Initialize(mapload)
	. = ..()

/// Washes its tile every machine step while running.
MSG_DEF_SELF(toilet/replacing_lid, span_notice("You start to replace the lid on the cistern."))
MSG_DEF_SELF(toilet/lifting_lid, span_notice("You start to lift the lid off the cistern."))
MSG_DEF_SELF(toilet/dismantling, span_notice("You begin to dismantle %T%..."))
MSG_DEF_SELF(toilet/refilling, span_notice("Wait for %T% to finish refilling..."))

/obj/structure/toilet/proc/crowbar_begins(datum/act/op/A)
	return cistern ? /datum/msg/toilet/replacing_lid : /datum/msg/toilet/lifting_lid

/obj/structure/toilet/proc/crowbar_act_done(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, null, MSG_SELF(span_notice("You [cistern ? "replace the lid on the cistern" : "lift the lid off the cistern"]!")), \
		MSG_OTHERS(span_notice("%U% [cistern ? "replaces the lid on the cistern" : "lifts the lid off the cistern"]!")), \
		MSG_BLIND("You hear grinding porcelain."))
	set_cistern(!cistern)

/obj/structure/toilet/proc/cistern_open(datum/act/op/A)
	return cistern

/obj/structure/toilet/proc/not_refilling(datum/act/op/A)
	return !refilling

/obj/structure/toilet/proc/wrench_act_done(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You dismantle \the [src]."))
	deconstruct()

//add heat controls? when emagged, you can freeze to death in it?

/// Old attack_hand (never called ..()): turn the water on or off.
/obj/machinery/shower/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	set_on(!on)
	handle_mist()
	add_fingerprint(user)
	if(on)
		work_step(null)
		soundloop.start()
	else
		soundloop.stop()
	return OP_OK

/// An analyzer reads the water temperature.
/obj/machinery/shower/proc/interaction_analyze(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("The water temperature seems to be [current_temperature]."))
	return OP_OK

/obj/machinery/shower/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/// Old click_alt: the valve is set to the chosen temperature after a while (the alt-click then goes on: the loot panel still opens).
/obj/machinery/shower/proc/temperature_chosen(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/R = A.answer
	if(!R)
		return OP_OK
	current_temperature = R.value
	handle_mist()
	act_message(user, null, MSG_SELF(span_notice("You adjust the shower to [current_temperature] temperature.")), \
		MSG_OTHERS(span_notice("%U% adjusts the shower.")))
	add_fingerprint(user)
	return OP_OK

/obj/machinery/shower/examine(mob/user)
	. = ..()
	. += span_notice("You can <b>alt-click</b> to change the temperature.")

/obj/machinery/shower/draw(datum/look/look)
	..()
	if(on)
		var/spray_color = reagent_id == REAGENT_ID_WATER ? null : reagents.get_color()
		look.overlay(look_overlay_image('icons/obj/watercloset.dmi', "water", layer = MOB_LAYER + 1, dir = dir, color = spray_color))

/obj/machinery/shower/proc/handle_mist()
	// If there is no mist, and the shower was turned on (on a non-freezing temp): make mist in 5 seconds
	// If there was already mist, and the shower was turned off (or made cold): remove the existing mist in 25 sec
	var/obj/effect/mist/mist = locate_on(loc, /obj/effect/mist)
	if(!mist && on && current_temperature != SHOWER_FREEZING)
		after(src, 5 SECONDS, PROC_REF(make_mist))

	if(mist && (!on || current_temperature == SHOWER_FREEZING))
		after(src, 25 SECONDS, PROC_REF(clear_mist))

/obj/machinery/shower/proc/make_mist()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/obj/effect/mist/mist = locate_on(loc, /obj/effect/mist)
	if(!mist && on && current_temperature != SHOWER_FREEZING)
		new /obj/effect/mist(loc)

/obj/machinery/shower/proc/clear_mist()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/obj/effect/mist/mist = locate_on(loc, /obj/effect/mist)
	if(mist && (!on || current_temperature == SHOWER_FREEZING))
		spent(mist)

/obj/machinery/shower/Crossed(atom/movable/AM)
	..()
	if(on)
		wash_atom(AM)

//Yes, showers are super powerful as far as washing goes.
/obj/machinery/shower/proc/wash_atom(atom/A)
	A.wash(CLEAN_RAD | CLEAN_TYPE_WEAK) // Clean radiation non-instantly
	A.wash(CLEAN_WASH)
	A.wash(CLEAN_SCRUB)
	reagents.splash(A, reaction_volume / 20, 1, TRUE, min_spill = 0, max_spill = 0) //Reaction volume needs to be divided by 20 due to a larger internal volume

	if(!isliving(A))
		return
	var/mob/living/L = A
	check_heat(L)
	L.extinguish_mob()
	L.adjust_fire_stacks(-20) //Douse ourselves with water to avoid fire more easily
	L.purge_radiation(5)

	if(!iscarbon(A))
		return
	//flush away reagents on the skin
	var/mob/living/carbon/C = A
	if(C.touching)
		var/remove_amount = C.touching.maximum_volume * C.reagent_permeability() //take off your suit first
		C.touching.remove_any(remove_amount)

/obj/machinery/shower/proc/work_step(datum/act/timer/A)
	if(isturf(loc)) //Wash the turf.
		wash_atom(loc)
	for(var/AM in turf_contents_of_type(loc, /atom/movable)) //Wash everything in the same loc (technically doesnt need to be a turf.)
		wash_atom(AM)

/obj/machinery/shower/proc/check_heat(mob/living/L)
	var/static/list/temperature_settings = list(SHOWER_FREEZING = SHOWER_TEMP_FREEZING, SHOWER_NORMAL = SHOWER_TEMP_NORMAL, SHOWER_BOILING = SHOWER_TEMP_BOILING)
	var/temperature = temperature_settings[current_temperature]
	switch(current_temperature)
		if(SHOWER_FREEZING)
			/* // We dont have adjust_bodytemperature()
			if(iscarbon(L))
				L.adjust_bodytemperature(-80, temperature)
			*/
			L.adjust_bodytemperature(-(80), min_temp = temperature)
			if(ishuman(L))
				var/mob/living/carbon/human/H = L
				if(temperature <= H.species.cold_level_1)
					to_chat(L, span_warning("The water is freezing cold!"))
			else
				to_chat(L, span_warning("The water is freezing cold!"))
		if(SHOWER_BOILING)
			/* // We dont have adjust_bodytemperature()
			if(iscarbon(L))
				L.adjust_bodytemperature(35, 0, temperature)
			*/
			L.adjust_bodytemperature(35, max_temp = temperature)
			if(ishuman(L))
				var/mob/living/carbon/human/H = L
				if(temperature >= H.species.heat_level_1)
					to_chat(L, span_danger("The water is searing hot!"))
					L.injure(INJURY_BURN, 5, null, src)
			else //Sorry, simplemobs just get Burnt
				to_chat(L, span_danger("The water is searing hot!"))
				L.injure(INJURY_BURN, 5, null, src)
		else
			if(L.body_temperature() < 288) // 15C
				L.adjust_bodytemperature(10, max_temp = SHOWER_TEMP_NORMAL)
			if(L.body_temperature() > 298) // 25C
				L.adjust_bodytemperature(-(10), min_temp = SHOWER_TEMP_NORMAL)

/obj/effect/mist
	name = "mist"
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "mist"
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	anchored = TRUE
	mouse_opacity = 0

////////////////////////RUBBER DUCKIES//////////////////////////////

/obj/item/bikehorn/rubberducky
	name = "rubber ducky"
	desc = "Rubber ducky you're so fine, you make bathtime lots of fuuun. Rubber ducky I'm awfully fooooond of yooooouuuu~"	//thanks doohl
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky"
	item_state = "rubberducky"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand.dmi',
	)
	honk_sound = SFX_VOICE_QUACK

//Admin spawn duckies

/obj/item/bikehorn/rubberducky/red
	name = "rubber ducky"
	desc = "From the depths of hell it arose, feathers glistening with crimson, a honk that struck fear into all men."	//thanks doohl
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_red"
	item_state = "rubberducky_red"
	honk_sound = SFX_EFFECTS_ADMINHELP
	var/honk_count = 0
	special_handling = TRUE

CAPABILITIES(/obj/item/bikehorn/rubberducky/red)
	// replaces the horn's honk (the old special_handling chain)
	op("honk", in_hand(), label("Squeeze"), then(PROC_REF(duck_red_self)))

/// Squeezed in hand.
/obj/item/bikehorn/rubberducky/red/proc/duck_red_self(datum/act/op/A)
	var/mob/user = A.actor
	if(honk_count >= 3)
		var/turf/epicenter = get_turf(src)
		explosion(epicenter, 0, 0, 1, 3)
		consume(src, user)
		return OP_OK
	else if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		playsound(src, honk_sound, 50, 1)
		add_fingerprint(user)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
		honk_count++
	return OP_OK

/obj/item/bikehorn/rubberducky/blue
	name = "rubber ducky"
	desc = "The see me rollin', they hatin'."	//thanks doohl
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_blue"
	item_state = "rubberducky_blue"
	honk_sound = SFX_EFFECTS_BUBBLES
	special_handling = TRUE

CAPABILITIES(/obj/item/bikehorn/rubberducky/blue)
	op("honk", in_hand(), label("Squeeze"), then(PROC_REF(duck_blue_self)))

/// Squeezed in hand.
/obj/item/bikehorn/rubberducky/blue/proc/duck_blue_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		playsound(src, honk_sound, 50, 1)
		add_fingerprint(user)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
		var/turf/simulated/whereweare = get_turf(src)
		whereweare.wet_floor(2)
	return OP_OK

/obj/item/bikehorn/rubberducky/pink
	name = "rubber ducky"
	desc = "It's extra squishy!"
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_pink"
	item_state = "rubberducky_pink"
	honk_sound = SFX_VORE_SUNESOUND_PRED_INSERTION_01
	special_handling = TRUE

CAPABILITIES(/obj/item/bikehorn/rubberducky/pink)
	op("honk", in_hand(), label("Squeeze"), then(PROC_REF(duck_pink_self)))

/// Squeezed in hand.
/obj/item/bikehorn/rubberducky/pink/proc/duck_pink_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		if(!user.devourable)
			to_chat(user, span_vnotice("You can't bring yourself to squeeze it..."))
			return OP_OK
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		playsound(src, honk_sound, 50, 1)
		add_fingerprint(user)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
		user.drop_item()
		user.forceMove(src)
		to_chat(user, span_vnotice("You have been swallowed alive by the rubber ducky. Your entire body compacted up and squeezed into the tiny space that makes up the oddly realistic and not at all rubbery stomach. The walls themselves are kneading over you, grinding some sort of fluids into your trapped body. You can even hear the sound of bodily functions echoing around you..."))
	return OP_OK

/obj/item/bikehorn/rubberducky/pink/container_resist(mob/living/escapee)
	if(isdisposalpacket(loc))
		escapee.forceMove(loc)
	else
		escapee.forceMove(get_turf(src))
	to_chat(escapee, span_vnotice("You managed to crawl out of the rubber ducky!"))

/obj/item/bikehorn/rubberducky/grey
	name = "rubber ducky"
	desc = "There's something otherworldly about this particular duck..."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_grey"
	item_state = "rubberducky_grey"
	honk_sound = SFX_EFFECTS_GHOST
	special_handling = TRUE

CAPABILITIES(/obj/item/bikehorn/rubberducky/grey)
	op("honk", in_hand(), label("Squeeze"), then(PROC_REF(duck_grey_self)))

/// Squeezed in hand.
/obj/item/bikehorn/rubberducky/grey/proc/duck_grey_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		playsound(src, honk_sound, 50, 1)
		add_fingerprint(user)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
		for(var/obj/machinery/light/L in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(L.z != user.z || get_dist(user,L) > 10)
				continue
			else
				L.flicker(10)
		user.drop_item()
		var/turf/T = locate(rand(1, 140), rand(1, 140), user.z)
		forceMove(T)
	return OP_OK

/obj/item/bikehorn/rubberducky/green
	name = "rubber ducky"
	desc = "Like a true Nature’s child, we were born, born to be wild."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_green"
	item_state = "rubberducky_green"
	honk_sound = SFX_ARCADE_MANA
	var/static/list/flora = list(/obj/structure/flora/ausbushes,
						/obj/structure/flora/ausbushes/reedbush,
						/obj/structure/flora/ausbushes/leafybush,
						/obj/structure/flora/ausbushes/palebush,
						/obj/structure/flora/ausbushes/stalkybush,
						/obj/structure/flora/ausbushes/grassybush,
						/obj/structure/flora/ausbushes/fernybush,
						/obj/structure/flora/ausbushes/sunnybush,
						/obj/structure/flora/ausbushes/genericbush,
						/obj/structure/flora/ausbushes/pointybush,
						/obj/structure/flora/ausbushes/lavendergrass,
						/obj/structure/flora/ausbushes/ywflowers,
						/obj/structure/flora/ausbushes/brflowers,
						/obj/structure/flora/ausbushes/ppflowers,
						/obj/structure/flora/ausbushes/sparsegrass,
						/obj/structure/flora/ausbushes/fullgrass)
	special_handling = TRUE

CAPABILITIES(/obj/item/bikehorn/rubberducky/green)
	op("honk", in_hand(), label("Squeeze"), then(PROC_REF(duck_green_self)))

/// Squeezed in hand.
/obj/item/bikehorn/rubberducky/green/proc/duck_green_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		playsound(src, honk_sound, 50, 1)
		add_fingerprint(user)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
		var/turf/simulated/whereweare = get_turf(src)
		var/obj/P = pick(flora)
		new P(whereweare)
	return OP_OK

/obj/item/bikehorn/rubberducky/white
	name = "rubber ducky"
	desc = "It's so full of energy, such a happy little guy, I just wanna give him a squeeze."	//thanks doohl
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_white"
	item_state = "rubberducky_white"
	honk_sound = SFX_EFFECTS_LIGHTNINGSHOCK
	special_handling = TRUE

CAPABILITIES(/obj/item/bikehorn/rubberducky/white)
	op("honk", in_hand(), label("Squeeze"), then(PROC_REF(duck_white_self)))

/// Squeezed in hand.
/obj/item/bikehorn/rubberducky/white/proc/duck_white_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		playsound(src, honk_sound, 50, 1)
		add_fingerprint(user)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
		lightning_strike(get_turf(src), 1)
		consume(src, user)
	return OP_OK

/obj/item/grenade/anti_photon/rubberducky/black
	desc = "Good work NanoTrasen Employee, you struck fear within the Syndicate."
	name = "rubber ducky"
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_black"
	item_state = "rubberducky_black"
	light_sound = SFX_VOICE_QUACK
	blast_sound = SFX_VOICE_QUACK

/obj/item/bikehorn/rubberducky/gold
	name = "rubber ducky"
	desc = "You could give your very life for this duck."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_gold"
	item_state = "rubberducky_gold"
	honk_sound = SFX_VOICE_QUACK_REVERB
	special_handling = TRUE

CAPABILITIES(/obj/item/bikehorn/rubberducky/gold)
	op("honk", in_hand(), label("Squeeze"), then(PROC_REF(duck_gold_self)))

/// Squeezed in hand.
/obj/item/bikehorn/rubberducky/gold/proc/duck_gold_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		playsound(src, honk_sound, 50, 1)
		add_fingerprint(user)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
		if(isliving(user))
			var/mob/living/U = user
			U.dust()
		user.drop_item()
		consume(src, user)
	return OP_OK

/obj/item/bikehorn/rubberducky/viking
	name = "rubber ducky"
	desc = "Honking is a duckie exclusive power."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_viking"
	item_state = "rubberducky_viking"
	honk_sound = SFX_VOICE_SCREAM_JELLY_M1
	honk_text = "DUK ROH DAH!"
	special_handling = TRUE

CAPABILITIES(/obj/item/bikehorn/rubberducky/viking)
	op("honk", in_hand(), label("Squeeze"), then(PROC_REF(duck_viking_self)))

/// Squeezed in hand.
/obj/item/bikehorn/rubberducky/viking/proc/duck_viking_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		playsound(src, honk_sound, 50, 1)
		add_fingerprint(user)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
		user.drop_item()
		user.throw_at_random(FALSE,9,2)
	return OP_OK

/obj/item/bikehorn/rubberducky/galaxy
	name = "rubber ducky"
	desc = "In the vastness of space all things center around thing, somewhere, a core."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "rubberducky_galaxy"
	item_state = "rubberducky_galaxy"
	honk_sound = SFX_EFFECTS_TELEPORT
	special_handling = TRUE

CAPABILITIES(/obj/item/bikehorn/rubberducky/galaxy)
	op("honk", in_hand(), label("Squeeze"), then(PROC_REF(duck_galaxy_self)))

/// Squeezed in hand.
/obj/item/bikehorn/rubberducky/galaxy/proc/duck_galaxy_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		playsound(src, honk_sound, 50, 1)
		add_fingerprint(user)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
		var/list/possible_orbiters = list()
		for(var/obj/item/I in oview(7,user))
			possible_orbiters += I
		for(var/mob/living/M in oview(7,user))
			possible_orbiters += M
		var/atom/movable/selected_orbiter = pick(possible_orbiters)
		selected_orbiter.orbit(user,32,TRUE,20,36)
	return OP_OK

//////////////////////////////SINKS//////////////////////////////

/obj/structure/sink
	name = "sink"
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "sink"
	desc = "A sink used for washing one's hands and face."
	anchored = TRUE

/// Old MouseDrop_T: an open container dragged onto the sink is tipped out into it.
/obj/structure/sink/proc/interaction_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/thing = A.held
	if(!istype(thing) || !thing.is_open_container())
		return OP_DECLINE
	if(!user.Adjacent(src))
		return OP_DECLINE
	if(!thing.reagents || thing.reagents.total_volume == 0)
		to_chat(user, span_notice("\The [thing] is empty."))
		return OP_OK
	// Clear the vessel.
	visible_message(span_infoplain(span_bold("\The [user]") + " tips the contents of \the [thing] into \the [src]."))
	thing.reagents.clear_reagents()
	return OP_PASS

CAPABILITIES(/obj/structure/sink)
	hose_sockets(list(/datum/hose_connector/endless_source/water, /datum/hose_connector/endless_drain))
	// a wash claims the sink: nobody else washes in it meanwhile; a silicon has no hands to wash
	op("wash", hand(), label("Wash hands"), when(req_actor_kind(/mob/living/silicon, not = TRUE)),
		needs(req(PROC_REF(hand_usable))), claims(), begins(MSG(sink/washing_hands)), plays(SFX_EFFECTS_SINK_LONG, at_start = TRUE), wait(4 SECONDS), on_interrupt(PROC_REF(wash_hands_stopped)), then(PROC_REF(interaction_wash)))
	op("item", item(/obj/item), label("Use"), claims(), begins(PROC_REF(wash_item_begins)), wait(PROC_REF(wash_item_time)), on_interrupt(PROC_REF(wash_item_stopped)), then(PROC_REF(interaction_item)))
	op("empty", item(/obj/item/reagent_containers), gesture(GESTURE_DRAG), label("Empty into sink"), then(PROC_REF(interaction_drag)))
	op("sink_wash_gurgled_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Wash"), when(req(PROC_REF(holding_gurgled))), claims(), begins(MSG(sink/washing_gurgled)), wait(4 SECONDS), then(PROC_REF(wash_gurgled_done)), says(MSG(sink/washed_gurgled)))

MSG_DEF_SELF(sink/busy, "Someone's already washing here.")
MSG_DEF_SELF(sink/washing_hands, span_notice("You start washing your hands."))

/// Requirement for washing: the hand the actor would wash with works.
/obj/structure/sink/proc/hand_usable(datum/act/op/A)
	var/hand_name = read_once(unusable_hand_name(A.actor)) // the limbs answer when asked
	return isnull(hand_name) ? null : "You try to move your [hand_name], but cannot."

/// The name of `user`'s active hand when it cannot be used, or null.
/obj/structure/sink/proc/unusable_hand_name(mob/user)
	if(!ishuman(user))
		return null
	var/mob/living/carbon/human/H = user
	var/obj/item/organ/external/temp = H.organs_by_name[H.hand ? BP_L_HAND : BP_R_HAND]
	if(temp && !temp.is_usable())
		return temp.name
	return null

/// Old attack_hand: wash your hands (it takes a while, and the sink is yours meanwhile).
/obj/structure/sink/proc/interaction_wash(datum/act/op/A)
	var/mob/user = A.actor
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.get_equipped_item(SLOT_ID_GLOVES))
			H.get_equipped_item(SLOT_ID_GLOVES).wash(CLEAN_SCRUB)
			H.update_inv_gloves()
			H.get_equipped_item(SLOT_ID_GLOVES).germ_level = 0
		else
			if(H.get_equipped_item(SLOT_ID_HAND_R))
				H.get_equipped_item(SLOT_ID_HAND_R).wash(CLEAN_SCRUB)
			if(H.get_equipped_item(SLOT_ID_HAND_L))
				H.get_equipped_item(SLOT_ID_HAND_L).wash(CLEAN_SCRUB)
			H.bloody_hands = 0
			H.germ_level = 0
			H.hand_blood_color = null
			H.forensic_data?.wash(CLEAN_SCRUB)
		H.update_bloodied()
	else
		user.wash(CLEAN_SCRUB)
	for(var/mob/V in viewers(src, null))
		V.show_message(span_notice("[user] washes their hands using \the [src]."))
	return OP_OK

/obj/structure/sink/proc/wash_hands_stopped(datum/act/op/A)
	to_chat(A.actor, span_notice("You stop washing your hands."))

/// Whether the held thing is washed (the timed part of the use); containers, batons that shock, mops and soap are dealt with at once.
/obj/structure/sink/proc/sink_washes(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	var/obj/item/reagent_containers/RG = O
	if(istype(RG) && RG.is_open_container())
		return FALSE
	if(istype(O, /obj/item/melee/baton))
		var/obj/item/melee/baton/B = O
		if(B.bcell && B.bcell.charge > 0 && B.status == 1)
			return FALSE
	else if(istype(O, /obj/item/mop) || istype(O, /obj/item/soap))
		return FALSE
	if(!isturf(user.loc))
		return FALSE
	if(istype(O, /obj/item/robot_tongue))
		var/obj/item/robot_tongue/J = O
		if(J.water.energy < J.water.max_energy)
			return FALSE
	return TRUE

/obj/structure/sink/proc/wash_item_time(datum/act/op/A)
	return sink_washes(A) ? 4 SECONDS : 0

/obj/structure/sink/proc/wash_item_begins(datum/act/op/A)
	return msg_text(span_notice("You start washing \the [A.held]."))

/obj/structure/sink/proc/wash_item_stopped(datum/act/op/A)
	to_chat(A.actor, span_notice("You stop washing \the [A.held]."))

/// Old attackby: fill a container, wet a mop or soap, short out a live baton, or wash the thing.
/obj/structure/sink/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	var/obj/item/reagent_containers/RG = O
	if (istype(RG) && RG.is_open_container())
		RG.reagents.add_reagent(REAGENT_ID_WATER, min(RG.reagents.get_free_space(), reagent_transfer_amount(RG)))
		act_message(user, src, MSG_SELF(span_notice("You fill %I% using %T%.")), MSG_OTHERS(span_notice("%U% fills %I% using %T%.")), item = RG)
		play_sfx(src, SFX_EFFECTS_SINK)
		return OP_OK

	else if (istype(O, /obj/item/melee/baton))
		var/obj/item/melee/baton/B = O
		if(B.bcell)
			if(B.bcell.charge > 0 && B.status == 1)
				flick("baton_active", src)
				user.status_at_least(STAT_STUNNED, 10)
				user.status_set(STAT_STUTTERING, 10)
				user.status_at_least(STAT_WEAKENED, 10)
				var/mob/living/silicon/robot/R = B.loc // a cyborg's baton module runs off the cyborg's own cell
				if(istype(R))
					R.draw_power(ROBOT_CELL_JOULES(20), src, 0, TRUE)
				else
					B.deductcharge(B.hitcost)
				act_message(user, null, MSG_SELF(span_userdanger("%U% was stunned by %THEIR% wet [O]!")), \
					MSG_OTHERS(span_danger("%U% was stunned by %THEIR% wet [O]!")))
				return OP_OK
	else if(istype(O, /obj/item/mop))
		O.reagents.add_reagent(REAGENT_ID_WATER, 5)
		to_chat(user, span_notice("You wet \the [O] in \the [src]."))
		play_sfx(src, SFX_EFFECTS_SLOSH)
		return OP_OK
	else if(istype(O, /obj/item/soap))
		var/obj/item/soap/soap = O
		to_chat(user, span_notice("You wet \the [O] in \the [src]"))
		soap.wet()
		O.wash(CLEAN_SCRUB)
		return OP_OK

	if(!sink_washes(A))
		return OP_OK

	O.wash(CLEAN_SCRUB)
	O.water_act(rand(1,10))
	act_message(user, src, MSG_SELF(span_notice("You wash \a [O] using %T%.")), MSG_OTHERS(span_notice("%U% washes \a [O] using %T%.")))
	return OP_OK

/obj/structure/sink/kitchen
	name = "kitchen sink"
	icon_state = "sink2"

/obj/structure/sink/countertop
	name = "countertop sink"
	icon_state = "sink3"

/obj/structure/sink/puddle	//splishy splashy ^_^
	name = "puddle"
	icon_state = "puddle"
	desc = "A small pool of some liquid, ostensibly water."

/// Overrides sink's interaction_wash(): splash animation around the wash.
/obj/structure/sink/puddle/interaction_wash(datum/act/op/A)
	icon_state = "puddle-splash"
	. = ..()
	icon_state = "puddle"

/// Overrides sink's interaction_item(): splash animation around the item use.
/obj/structure/sink/puddle/interaction_item(datum/act/op/A)
	icon_state = "puddle-splash"
	. = ..()
	icon_state = "puddle"

#undef SHOWER_FREEZING
#undef SHOWER_TEMP_FREEZING
#undef SHOWER_NORMAL
#undef SHOWER_TEMP_NORMAL
#undef SHOWER_BOILING
#undef SHOWER_TEMP_BOILING

CAPABILITIES(/obj/structure/toilet/item)
	after_init(0, then(PROC_REF(take_loose_items)))

// === merged from watercloset_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/// Takes in the loose items lying on its turf.
/obj/structure/toilet/item/proc/take_loose_items(datum/act/timer/A)
	if(istype(loc, /mob/living)) return
	var/obj/item/I
	for(I in turf_contents_of_type(loc, /obj/item))
		if(I.density || I.anchored || I == src) continue
		I.forceMove(src)

/obj/structure/biowaste_tank
	name = "Bluespace Bio-Compostor Terminal"
	icon = 'icons/obj/survival_pod_comp.dmi'
	icon_state = "pod_computer"
	desc = "It appears to be a massive sealed container attached to some heavy machinery and thick tubes containing a whole network of interdimensional pipeworks. It appears whatever vanished down the station's toilets ends up in this thing."
	anchored = TRUE
	density = TRUE
	var/muffin_mode = FALSE
	var/mob/living/simple_mob/vore/aggressive/corrupthound/muffinmonster
	var/obj/machinery/recycling/crusher/crusher //Bluespace connection for recyclables

/obj/structure/biowaste_tank/Initialize(mapload)
	rel_set(src, nameof(muffinmonster), new /mob/living/simple_mob/vore/aggressive/corrupthound/muffinmonster(src))
	muffinmonster().name = "Activate Muffin Monster"
	muffinmonster().init_vore(TRUE)
	rel_set(src, nameof(crusher), locate(/obj/machinery/recycling/crusher))
	return ..()

/obj/structure/biowaste_tank/AllowDrop()
	return TRUE

/obj/structure/biowaste_tank/Entered(atom/movable/thing, atom/OldLoc)
	. = ..()
	if(istype(thing, /obj/item/reagent_containers/food))
		spent(thing)
		return
	if(istype(thing, /obj/item/organ))
		spent(thing)
		return
	if(istype(thing, /obj/item/storage/vore_egg))
		var/obj/item/storage/vore_egg/egg = thing
		for(var/atom/movable/C in egg.slot_contents())
			C.forceMove(src)
		spent(thing)
		return
	if(istype(crusher(), /obj/machinery/recycling/crusher) && istype(thing, /obj/item/debris_pack))
		crusher().take_item(thing)
		return
	if(muffin_mode)
		if(muffinmonster())
			move_into(muffinmonster().vore_selected, BELLY_SLOT_INTERIOR, thing)
		else
			muffin_mode = FALSE

/// What the filter caught, to choose from.
/obj/structure/biowaste_tank/proc/caught_items(datum/act/A)
	return contents.Copy()

/// Something is caught in the filter: the console asks which to eject.
/obj/structure/biowaste_tank/proc/has_caught(datum/act/op/A)
	return caught_count() > 0

/obj/structure/biowaste_tank/proc/caught_count()
	. = 0
	FOR_REAL_CONTENTS(var/atom/movable/AM, src)
		.++
READS_AS(/obj/structure/biowaste_tank/proc/caught_count, BIOWASTE_CAUGHT_KEY)

/// What the filter holds changed: the console asks again.
/obj/structure/biowaste_tank/on_slot_changed(slot_id, atom/movable/thing, inserted)
	. = ..()
	PUBLISH_CHANGE(src, BIOWASTE_CAUGHT_KEY)

/// Old attack_hand: eject a caught item from the filter system (the muffin monster toggles instead).
/obj/structure/biowaste_tank/proc/eject_chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R)
		return OP_OK
	var/mob/user = A.actor
	var/atom/movable/choice = R.value
	if(choice.loc == src)
		if(!user.canmove)
			return OP_OK
		if(choice == muffinmonster() && muffinmonster().loc == src)
			muffin_mode = !muffin_mode
			if(muffin_mode)
				muffinmonster().name = "Deactivate Muffin Monster"
				for(var/atom/movable/C in contents)
					if(C == muffinmonster())
						continue
					move_into(muffinmonster().vore_selected, BELLY_SLOT_INTERIOR, C)
			else
				muffinmonster().name = "Activate Muffin Monster"
				muffinmonster().release_vore_contents(include_absorbed = TRUE, silent = TRUE)
			return OP_OK
		else
			choice.forceMove(get_turf(src))
	return OP_OK

CAPABILITIES(/obj/structure/biowaste_tank)
	emag(then(PROC_REF(on_emag)), repeatable = TRUE)
	op("eject", hand(), label("Use"),
		asks(/datum/prompt/choice, fields = list("title" = "Item Retrieval Console", "question" = "It appears the machine has caught some items in the lost-and-found filter system. Would you like to eject something?", "choices" = computed(PROC_REF(caught_items)), "timeout" = 0), when = PROC_REF(has_caught)),
		then(PROC_REF(eject_chosen)))

/// The sequencer shorts the grinder's safety: a muffin monster at work is let out.
/obj/structure/biowaste_tank/proc/on_emag(datum/act/op/A)
	if(muffinmonster() && muffin_mode)
		muffinmonster().name = "Muffin Monster"
		muffinmonster().forceMove(get_turf(src))
		rel_clear(src, nameof(muffinmonster))
		muffin_mode = FALSE
	return OP_OK

/mob/living/simple_mob/vore/aggressive/corrupthound/muffinmonster
	name = "Muffin Monster"
	desc = "OH GOD IT'S LOOSE!"
	icon_state = "muffinmonster"
	icon_living = "muffinmonster"
	icon_dead = "muffinmonster-dead"
	icon_rest = "muffinmonster_rest"
	icon = 'icons/mob/vore64x32_ch.dmi'
	has_eye_glow = FALSE
	vore_default_item_mode = IM_DIGEST

/mob/living/simple_mob/vore/aggressive/corrupthound/muffinmonster/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "waste hopper"
	B.desc = "With a resounding CRUNCH, your form has gotten snagged by the Muffin Monster's rotational interlocking cutters indiscriminately crunching away at anything unlucky enough to end up in its hopper, only for the insatiable machine to grind it all down into a slurry mulch fine enough to pass through the narrow sewage lines trouble-free..."
	B.digest_brute = 20
	B.special_entrance_sound = 'sound/machines/blender.ogg'
	B.recycling = TRUE

/// Relation view: muffinmonster (reads null once it is gone).
/obj/structure/biowaste_tank/proc/muffinmonster() as /mob/living/simple_mob/vore/aggressive/corrupthound
	return muffinmonster

/// Relation view: crusher (reads null once it is gone).
/obj/structure/biowaste_tank/proc/crusher() as /obj/machinery/recycling/crusher
	return crusher
