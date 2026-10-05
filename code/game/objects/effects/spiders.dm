//generic procs copied from obj/effect/alien
/obj/effect/spider
	uses_integrity = TRUE
	name = "web"
	desc = "it's stringy and sticky"
	icon = 'icons/effects/effects.dmi'
	anchored = TRUE
	density = FALSE
	max_integrity = 10

//similar to weeds, but only barfed out by nurses manually
CAPABILITIES(/obj/effect/spider)
	op("hit_web", item(/obj/item), then(PROC_REF(interaction_hit_web)))

/// Old attackby: any item hits the web (afterattack still follows, as before).
/obj/effect/spider/proc/interaction_hit_web(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	var/obj/item/W = held
	user.setClickCooldown(user.get_attack_speed(W))

	if(LAZYLEN(W.attack_verb))
		act_message(src, user, others = span_warning("%U% has been [pick(W.attack_verb)] with %I%[user ? " by %T%." : "."]"), item = W)
	else
		act_message(src, user, others = span_warning("%U% has been attacked with %I%[user ? " by %T%." : "."]"), item = W)

	receive_weapon_hit(W, user, W.force / 4)
	return OP_PASS

/obj/effect/spider/welder_act(mob/user, obj/item/tool)
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder.remove_fuel(0, user))
		return ITEM_INTERACT_BLOCKING
	user.setClickCooldown(user.get_attack_speed(tool))
	act_message(src, user, others = span_warning("%U% has been burned with %I% by %T%."), item = tool)
	playsound(src, tool.usesound, 100, TRUE)
	take_damage(15, BRUTE, MELEE, sound_effect = FALSE)
	return ITEM_INTERACT_SUCCESS

EXTEND_INTERACTIONS(/obj/effect/spider/spiderling, \
	INTERACT_HAND("Stomp", PROC_REF(interaction_stomp_spiderling)), \
)

/// Old attack_hand: try to stomp the spiderling.
/obj/effect/spider/spiderling/proc/interaction_stomp_spiderling(mob/living/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	user.do_attack_animation(src)
	if(prob(20))
		act_message(user, src, others = span_warning("%U% tries to stomp on %T%, but misses!"))
		var/list/nearby = oview(2, src)
		if(length(nearby))
			walk_to(src, pick(nearby), 2)
			return
	act_message(user, src, others = span_warning("%U% stomps %T% dead!"))
	die()

/obj/effect/spider/proc/die()
	consume(src)

/obj/effect/spider/atom_destruction(damage_flag)
	die()
	return ..()

/obj/effect/spider/stickyweb
	icon_state = "stickyweb1"

/obj/effect/spider/stickyweb/Initialize(mapload)
	if(prob(50))
		icon_state = "stickyweb2"
	return ..()

/obj/effect/spider/stickyweb/CanPass(atom/movable/mover, turf/target)
	if(istype(mover, /mob/living/simple_mob/animal/giant_spider))
		return TRUE
	else if(isliving(mover))
		if(prob(50))
			to_chat(mover, span_warning("You get stuck in \the [src] for a moment."))
			return FALSE
	else if(istype(mover, /obj/item/projectile))
		return prob(30)
	return TRUE

/obj/effect/spider/eggcluster
	name = "egg cluster"
	desc = "They seem to pulse slightly with an inner life"
	icon_state = "eggs"
	var/amount_grown = 0
	var/spiders_min = 6
	var/spiders_max = 24
	var/spider_type = /obj/effect/spider/spiderling
	var/faction = FACTION_SPIDERS

/obj/effect/spider/eggcluster/Initialize(mapload, atom/parent)
	pixel_x = rand(3,-3)
	pixel_y = rand(3,-3)
	after(src, egg_hatch_steps() * 2 SECONDS, PROC_REF(hatch))
	. = ..()
	get_light_and_color(parent)

// leaves the implant list of the limb it was laid in.

/// Hatches (its growth timer).
/obj/effect/spider/eggcluster/proc/hatch()
	if(QDELETED(src))
		return
	amount_grown = 100
	if(amount_grown >= 100)
		var/num = rand(spiders_min, spiders_max)
		var/obj/item/organ/external/O = null
		if(istype(loc, /obj/item/organ/external))
			O = loc

		for(var/i=0, i<num, i++)
			var/obj/effect/spider/spiderling/spiderling = new spider_type(src.loc, src)
			if(O)
				rel_add(O, nameof(O.implants), spiderling)
			spiderling.faction = faction
		consume(src)

/obj/effect/spider/eggcluster/small
	spiders_min = 2
	spiders_max = 6

/obj/effect/spider/eggcluster/small/frost
	spider_type = /obj/effect/spider/spiderling/frost

/obj/effect/spider/eggcluster/royal
	spiders_min = 2
	spiders_max = 6
	spider_type = /obj/effect/spider/spiderling/varied

/obj/effect/spider/spiderling
	name = "spiderling"
	desc = "It never stays still for long."
	icon_state = "spiderling"
	anchored = FALSE
	layer = HIDING_LAYER
	max_integrity = 3
	COOLDOWN_DECLARE(itch_cooldown)
	var/amount_grown = 0
	var/obj/machinery/atmospherics/unary/vent_pump/entry_vent
	var/travelling_in_vent = 0
	var/faction = FACTION_SPIDERS

	var/stunted = FALSE

TYPE_TABLE_DECLARE(/obj/effect/spider/spiderling, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider, /mob/living/simple_mob/animal/giant_spider/hunter))

/obj/effect/spider/spiderling/frost

TYPE_TABLE(/obj/effect/spider/spiderling/frost, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider/frost))

/obj/effect/spider/spiderling/varied

TYPE_TABLE(/obj/effect/spider/spiderling/varied, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider, /mob/living/simple_mob/animal/giant_spider/nurse, /mob/living/simple_mob/animal/giant_spider/hunter, \
			/mob/living/simple_mob/animal/giant_spider/frost, /mob/living/simple_mob/animal/giant_spider/electric, /mob/living/simple_mob/animal/giant_spider/lurker, \
			/mob/living/simple_mob/animal/giant_spider/pepper, /mob/living/simple_mob/animal/giant_spider/thermic, /mob/living/simple_mob/animal/giant_spider/tunneler, \
			/mob/living/simple_mob/animal/giant_spider/webslinger, /mob/living/simple_mob/animal/giant_spider/phorogenic, /mob/living/simple_mob/animal/giant_spider/carrier, \
			/mob/living/simple_mob/animal/giant_spider/ion))

/obj/effect/spider/spiderling/Initialize(mapload, atom/parent)
	. = ..()
	pixel_x = rand(6,-6)
	pixel_y = rand(6,-6)
	//50% chance to grow up
	if(amount_grown != -1 && prob(50))
		amount_grown = 1
	get_light_and_color(parent)

DECLARE_PERIODIC(/obj/effect/spider/spiderling, PERIODIC_SLOW)

/obj/effect/spider/spiderling/Bump(atom/user)
	if(istype(user, /obj/structure/table))
		src.forceMove(user.loc)
	else
		..()

/obj/effect/spider/spiderling/die()
	visible_message(span_warning("[src] dies!"))
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)
	..()

/obj/effect/spider/spiderling/periodic_step()
	if(travelling_in_vent)
		if(istype(src.loc, /turf))
			travelling_in_vent = 0
			rel_clear(src, nameof(entry_vent))
	else if(entry_vent())
		if(get_dist(src, entry_vent()) <= 1)
			var/obj/machinery/atmospherics/unary/vent_pump/exit_vent = get_safe_ventcrawl_target(entry_vent())
			if(!exit_vent)
				return
			vent_crawl_async(entry_vent(), exit_vent)

	if(isturf(loc))
		skitter()

	else if(isorgan(loc))
		if(amount_grown < 0) amount_grown = 1
		var/obj/item/organ/external/O = loc
		if(!O.owner || O.owner.stat == DEAD || amount_grown > 80)
			rel_remove(O, nameof(O.implants), src)
			src.forceMove(O.owner ? O.owner.loc : O.loc)
			src.visible_message(span_warning("\A [src] makes its way out of [O.owner ? "[O.owner]'s [O.name]" : "\the [O]"]!"))
			if(O.owner)
				O.owner.injure(INJURY_PIERCE, 1, O.organ_tag, src)
		else if(prob(1))
			O.owner.injure(INJURY_TOXIN, 1, O.organ_tag, src)
			if(COOLDOWN_FINISHED(src, itch_cooldown))
				COOLDOWN_START(src, itch_cooldown, 30 SECONDS)
				to_chat(O.owner, span_notice("Your [O.name] itches..."))
	else if(prob(1))
		src.visible_message(span_infoplain(span_bold("\The [src]") + " skitters."))

	if(amount_grown >= 0)
		amount_grown += rand(0,2)

/obj/effect/spider/spiderling/proc/vent_crawl_async(obj/machinery/atmospherics/unary/vent_pump/entry, obj/machinery/atmospherics/unary/vent_pump/exit_vent)
	after(src, rand(2 SECONDS,6 SECONDS), PROC_REF(vent_crawl_enter), with = list(entry, exit_vent))

/obj/effect/spider/spiderling/proc/vent_crawl_enter(obj/machinery/atmospherics/unary/vent_pump/entry, obj/machinery/atmospherics/unary/vent_pump/exit_vent)
	forceMove(exit_vent)
	var/travel_time = round(get_dist(loc, exit_vent.loc) / 2)
	after(src, travel_time, PROC_REF(vent_crawl_midway), with = list(entry, exit_vent, travel_time))

/obj/effect/spider/spiderling/proc/vent_crawl_midway(obj/machinery/atmospherics/unary/vent_pump/entry, obj/machinery/atmospherics/unary/vent_pump/exit_vent, travel_time)
	if(!exit_vent || exit_vent.welded)
		forceMove(entry)
		rel_clear(src, nameof(entry_vent))
		return

	if(prob(50))
		src.visible_message(span_notice("You hear something squeezing through the ventilation ducts."),2)
		SSmotiontracker.ping(src,10)
	after(src, travel_time, PROC_REF(vent_crawl_exit), with = list(entry, exit_vent))

/obj/effect/spider/spiderling/proc/vent_crawl_exit(obj/machinery/atmospherics/unary/vent_pump/entry, obj/machinery/atmospherics/unary/vent_pump/exit_vent)
	if(!exit_vent || exit_vent.welded)
		forceMove(entry)
		rel_clear(src, nameof(entry_vent))
		return
	forceMove(exit_vent.loc)
	rel_clear(src, nameof(entry_vent))
	var/area/new_area = get_area(loc)
	if(new_area)
		new_area.Entered(src)

/obj/effect/spider/spiderling/proc/skitter()
	if(isturf(loc))
		if(prob(25))
			var/list/nearby = trange(5, src) - loc
			if(nearby.len)
				var/target_atom = pick(nearby)
				walk_to(src, target_atom, 5)
				if(prob(25))
					src.visible_message(span_notice("\The [src] skitters[pick(" away"," around","")]."))
				SSmotiontracker.ping(src,10)
		else if(amount_grown < 75 && prob(5))
			//vent crawl!
			for(var/obj/machinery/atmospherics/unary/vent_pump/v in view(7,src))
				if(!v.welded)
					rel_set(src, nameof(entry_vent), v)
					walk_to(src, entry_vent(), 5)
					break
		if(amount_grown >= 100)
			var/spawn_type = pick(TYPE_TABLE_GET(src, spiderling_grow_as))
			var/mob/living/simple_mob/animal/giant_spider/GS = new spawn_type(src.loc, src)
			GS.faction = faction
			if(stunted)
				after(GS, 0.2 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/animal/giant_spider, make_spiderling))
			replace_with(src, GS)

/obj/effect/spider/spiderling/stunted
	stunted = TRUE

TYPE_TABLE(/obj/effect/spider/spiderling/stunted, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider, /mob/living/simple_mob/animal/giant_spider/hunter))


/obj/effect/spider/spiderling/non_growing
	amount_grown = -1

/obj/effect/spider/spiderling/princess
	name = "royal spiderling"
	desc = "There's a special aura about this one."

TYPE_TABLE(/obj/effect/spider/spiderling/princess, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider/nurse/queen))

/obj/effect/spider/spiderling/princess/Initialize(mapload, atom/parent)
	. = ..()
	amount_grown = 50

/obj/effect/decal/cleanable/spiderling_remains
	name = "spiderling remains"
	desc = "Green squishy mess."
	icon = 'icons/effects/effects.dmi'
	icon_state = "greenshatter"

/obj/effect/spider/cocoon
	name = "cocoon"
	desc = "Something wrapped in silky spider web"
	icon_state = "cocoon1"
	max_integrity = 15

/obj/effect/spider/cocoon/Initialize(mapload)
	. = ..()
	icon_state = pick("cocoon1","cocoon2","cocoon3")

// the cocoon splits open and drops its contents.
DESTROY_EFFECTS(/obj/effect/spider/cocoon, new /datum/destroy_effects_data(message = "%SRC% splits open."))

CAPABILITIES(/obj/effect/spider/cocoon)
	owns_many(nameof(contents), on_destroy = ON_DESTROY_SPILL)

/obj/effect/spider/spiderling/non_growing/horror
	icon_state = "tendrils"

/obj/effect/spider/spiderling/non_growing/horror/die()
	visible_message(span_cult("[src] stops squirming."))
	var/obj/effect/decal/cleanable/tendril_remains/remains = new /obj/effect/decal/cleanable/tendril_remains(src.loc)
	remains.color = color
	replace_with(src, remains)

/obj/effect/decal/cleanable/tendril_remains
	name = "tendril remains"
	desc = "A disgusting pile of unmoving fleshy tendrils."
	icon = 'icons/effects/effects.dmi'
	icon_state = "tendril_dead"

// === merged from spiders_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/effect/spider/spiderling/virgo

// === merged from spiders_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
//Eggs

TYPE_TABLE(/obj/effect/spider/spiderling/virgo, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider/event, /mob/living/simple_mob/animal/giant_spider/hunter/event))
/obj/effect/spider/eggcluster/broodling
	spider_type = /obj/effect/spider/spiderling/broodling

/obj/effect/spider/eggcluster/royal/broodling
	spider_type = /obj/effect/spider/spiderling/varied/broodling

//Spiderling types
/obj/effect/spider/spiderling/broodling
	name = "brood spiderling"

TYPE_TABLE(/obj/effect/spider/spiderling/broodling, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider/broodling, /mob/living/simple_mob/animal/giant_spider/nurse/broodling, /mob/living/simple_mob/animal/giant_spider/hunter/broodling))

/obj/effect/spider/spiderling/varied/broodling

//Space Spiderling

TYPE_TABLE(/obj/effect/spider/spiderling/varied/broodling, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider/broodling, /mob/living/simple_mob/animal/giant_spider/nurse/broodling, /mob/living/simple_mob/animal/giant_spider/hunter/broodling, \
			/mob/living/simple_mob/animal/giant_spider/frost/broodling, /mob/living/simple_mob/animal/giant_spider/electric/broodling, /mob/living/simple_mob/animal/giant_spider/lurker/broodling, \
			/mob/living/simple_mob/animal/giant_spider/pepper/broodling, /mob/living/simple_mob/animal/giant_spider/thermic/broodling, /mob/living/simple_mob/animal/giant_spider/tunneler/broodling, \
			/mob/living/simple_mob/animal/giant_spider/webslinger/broodling))
/obj/effect/spider/eggcluster/space
	spider_type = /obj/effect/spider/spiderling/space

/obj/effect/spider/eggcluster/royal/space
	spider_type = /obj/effect/spider/spiderling/varied/space

/obj/effect/spider/spiderling/space
	name = "brood spiderling"

TYPE_TABLE(/obj/effect/spider/spiderling/space, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider/space, /mob/living/simple_mob/animal/giant_spider/nurse/space, /mob/living/simple_mob/animal/giant_spider/hunter/space))

/obj/effect/spider/spiderling/varied/space

/// Steps (one per 2 s) a growth of rand(0, 2) a step takes to reach 100: the old growth loop's
/// hatch time, drawn once so the egg sleeps on a single timer until it hatches.

TYPE_TABLE(/obj/effect/spider/spiderling/varied/space, spiderling_grow_as, list(/mob/living/simple_mob/animal/giant_spider/space, /mob/living/simple_mob/animal/giant_spider/nurse/space, /mob/living/simple_mob/animal/giant_spider/hunter/space, \
			/mob/living/simple_mob/animal/giant_spider/frost/space, /mob/living/simple_mob/animal/giant_spider/electric/space, /mob/living/simple_mob/animal/giant_spider/lurker/space, \
			/mob/living/simple_mob/animal/giant_spider/pepper/space, /mob/living/simple_mob/animal/giant_spider/thermic/space, /mob/living/simple_mob/animal/giant_spider/tunneler/space, \
			/mob/living/simple_mob/animal/giant_spider/webslinger/space))
/proc/egg_hatch_steps()
	var/grown = 0
	. = 0
	while(grown < 100)
		grown += rand(0, 2)
		.++

/// Relation view: entry vent (reads null once it is gone).
/obj/effect/spider/spiderling/proc/entry_vent() as /obj/machinery/atmospherics/unary/vent_pump
	return entry_vent
