// Nurses, they create webs and eggs.
// They're fragile but their attacks can cause horrifying consequences.

/datum/category_item/catalogue/fauna/giant_spider/nurse_spider
	name = "Giant Spider - Nurse"
	desc = "This specific spider has been catalogued as 'Nurse', \
	and it belongs to the 'Nurse' caste. \
	The spider has a beige coloration, with green eyes. \
	<br><br>\
	Nurses primarily spin webs and lay eggs for the other spiders, making them a critical role \
	for the survival of their species in their local area. Despite this importance, they are \
	(compared to the other spiders) rather frail and weak, thus requiring protection from the \
	other spiders. Laying eggs requires considerable amounts of resources, meaning Nurses generally \
	only lay eggs after they or another spider successfully hunts prey.\
	<br><br>\
	Unlike ordinary spiders, Nurses can create vast amounts of web in a short period of time, making \
	their nest difficult and dangerous to move around in. Their webs also sometimes obscure what is \
	behind them, giving an advantage to spiders defending their nest, and invoking paranoia in humans \
	tasked with exterminating the spiders. \
	<br><br>\
	Nurse venom causes fatigue and tiredness. They are also able to directly inject spider eggs into \
	those it bites, which can later hatch spiderlings, causing considerably physical and psychological trauma."
	value = CATALOGUER_REWARD_EASY

/mob/living/simple_mob/animal/giant_spider/nurse
	desc = "Furry and beige, it makes you shudder to look at it. This one has brilliant green eyes."
	catalogue_data = list(/datum/category_item/catalogue/fauna/giant_spider/nurse_spider)

	icon_state = "nurse"
	icon_living = "nurse"
	icon_dead = "nurse_dead"

	endurance = 40

	movement_cooldown = 1.5	// A bit faster so that they can inject the eggs easier.

	melee_damage_lower = 5	// Doesn't do a lot of damage, since the goal is to make more spiders with egg attacks.
	melee_damage_upper = 10
	poison_per_bite = 5
	poison_type = REAGENT_ID_STOXIN

	player_msg = "You can spin webs on an adjacent tile, or cocoon an object by clicking on it.<br>\
	You can also cocoon a dying or dead entity by clicking on them, and you will gain charges for egg-laying.<br>\
	To lay eggs, click a nearby tile. Laying eggs will deplete a charge."

	var/fed = 0 // Counter for how many egg laying 'charges' the spider has.
	var/laying_eggs = FALSE	// Only allow one set of eggs to be laid at once.
	var/egg_inject_chance = 25 // One in four chance to get eggs.
	var/egg_type = /obj/effect/spider/eggcluster/small
	var/web_type = /obj/effect/spider/stickyweb/dark

/mob/living/simple_mob/animal/giant_spider/nurse/inject_poison(mob/living/L, target_zone)
	..() // Inject the stoxin here.
	if(ishuman(L) && prob(egg_inject_chance) && can_lay_eggs)
		var/mob/living/carbon/human/H = L
		var/obj/item/organ/external/O = H.get_organ(target_zone)
		if(O)
			var/eggcount = 0
			for(var/obj/effect/spider/eggcluster/E in O.implants)
				eggcount++
			if(!eggcount)
				var/obj/effect/spider/eggcluster/eggs = new egg_type(O, src)
				O.implants += eggs
				eggs.faction = faction
				to_chat(H, span_critical("\The [src] injects something into your [O.name]!") ) // Oh god its laying eggs in me!

// Webs target in a web if able to.
/mob/living/simple_mob/animal/giant_spider/nurse/attack_target(atom/A)
	if(isturf(A))
		if(fed && can_lay_eggs)
			if(!laying_eggs)
				return lay_eggs(A)
		return web_tile(A)

	if(isliving(A))
		var/mob/living/L = A
		if(!L.stat)
			return ..()
		else
			if (L.anchored && L.buckled && !(L.pulledby || L.buckled.pulledby)) //don't have them trying to unbuckle someone on something that's being pulled because that's just annoying as fuck esp for a medic or something
				L.buckled.unbuckle_mob(L)
			if (!L.anchored)
				return spin_cocoon(L)
			return

	if(!istype(A, /atom/movable))
		return
	var/atom/movable/AM = A

	if(AM.anchored)
		return ..()

	return spin_cocoon(AM)

/mob/living/simple_mob/animal/giant_spider/nurse/proc/spin_cocoon(atom/movable/AM)
	if(!istype(AM))
		return FALSE // We can't cocoon walls sadly.
	if(istype(AM, /mob/living/simple_mob/animal/giant_spider))
		return FALSE
	visible_message(span_notice("\The [src] begins to secrete a sticky substance around \the [AM]."))

	// Get our AI to stay still.
	if(ai_brain) ai_brain.busy = TRUE
	if(!do_after(src,5 SECONDS, AM))
		if(ai_brain) ai_brain.busy = FALSE
		to_chat(src, span_warning("You need to stay still to spin a web around \the [AM]."))
		return FALSE

	if(ai_brain) ai_brain.busy = FALSE
	if(!AM) // Make sure it didn't get deleted for whatever reason.
		to_chat(src, span_warning("Whatever you were spinning a web for, its no longer there..."))
		return FALSE

	if(!isturf(AM.loc))
		to_chat(src, span_warning("You can't spin \the [AM] in a web while it is inside \the [AM.loc]."))
		return FALSE

	if(!Adjacent(AM))
		to_chat(src, span_warning("You need to be next to \the [AM] to spin it into a web."))
		return FALSE

	// Finally done with the checks.
	var/obj/effect/spider/cocoon/C = new(AM.loc)
	var/large_cocoon = FALSE
	for(var/mob/living/L in C.loc)
		if(istype(L, /mob/living/simple_mob/animal/giant_spider)) // Cannibalism is bad.
			continue
		fed++
		visible_message(span_warning("\The [src] sticks a proboscis into \the [L], and sucks a viscous substance out."))
		to_chat(src, span_notice("You've fed upon \the [L], and can now lay [fed] cluster\s of eggs."))
		L.forceMove(C)
		large_cocoon = TRUE
		break

	// This part's pretty stupid.
	for(var/obj/O in C.loc)
		if(!O.anchored)
			O.forceMove(C)

	// Todo: Put this code on the cocoon object itself?
	if(large_cocoon)
		C.icon_state = pick("cocoon_large1","cocoon_large2","cocoon_large3")

	ai_brain?.lose_target()

	return TRUE

/datum/om/stage/life/special/animal/giant_spider/nurse
	of = /mob/living/simple_mob/animal/giant_spider/nurse

/datum/om/stage/life/special/animal/giant_spider/nurse/perform(mob/living/simple_mob/animal/giant_spider/nurse/self, datum/om/frame/life/ctx)
	if((self.ai_brain ? (self.ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) : STANCE_IDLE) == STANCE_IDLE && !(self.ai_brain && self.ai_brain.busy) && isturf(self.loc))
		if(self.fed && self.can_lay_eggs)
			self.lay_eggs(self.loc)
		else
			self.web_tile(self.loc)

/// Starts spinning a web on `T`: a 5 s task that holds its claim on the turf and ends when the
/// spider moves off, stops being conscious, or dies. TRUE when it started.
/mob/living/simple_mob/animal/giant_spider/nurse/proc/web_tile(turf/T)
	if(!istype(T) || (locate(/obj/effect/spider/stickyweb) in T))
		return FALSE
	if(istext(om_task_start(src, /datum/om/task_def/mob_work/spider_web, T)))
		return FALSE
	visible_message(span_notice("\The [src] begins to secrete a sticky substance.") )
	ai_brain?.busy = TRUE // Get our AI to stay still.
	return TRUE

/mob/living/simple_mob/animal/giant_spider/nurse/proc/web_done(datum/om/task/task)
	ai_brain?.busy = FALSE
	var/turf/T = task.target
	if(!(locate(/obj/effect/spider/stickyweb) in T))
		new web_type(T)

/mob/living/simple_mob/animal/giant_spider/nurse/proc/work_interrupted(datum/om/task/task, reason)
	ai_brain?.busy = FALSE
	laying_eggs = FALSE
	to_chat(src, span_warning("You need to stay still to finish that on \the [task.target]."))

/// Starts laying a cluster of eggs on `T` (a 5 s task, as web_tile()). TRUE when it started.
/mob/living/simple_mob/animal/giant_spider/nurse/proc/lay_eggs(turf/T)
	if(!istype(T) || !fed || !can_lay_eggs || laying_eggs)
		return FALSE
	if(locate(/obj/effect/spider/eggcluster) in T)
		return FALSE // Already got eggs here.
	if(istext(om_task_start(src, /datum/om/task_def/mob_work/spider_eggs, T)))
		return FALSE
	visible_message(span_notice("\The [src] begins to lay a cluster of eggs.") )
	ai_brain?.busy = TRUE
	laying_eggs = TRUE // Stop players from spamming eggs.
	return TRUE

/mob/living/simple_mob/animal/giant_spider/nurse/proc/eggs_done(datum/om/task/task)
	ai_brain?.busy = FALSE
	laying_eggs = FALSE
	var/turf/T = task.target
	if(locate(/obj/effect/spider/eggcluster) in T)
		return // Spamclick protection.
	var/obj/effect/spider/eggcluster/eggs = new egg_type(T)
	eggs.faction = faction
	fed--

// Variant that 'blocks' light (by being a negative light source).
// This is done to make webbed rooms scary and allow for spiders on the other side of webs to see prey.
/obj/effect/spider/stickyweb/dark
	name = "dense web"
	desc = "It's sticky, and blocks a lot of light."
	light_color = "#FFFFFF"
	light_range = 2
	light_power = -3

// This is still stupid, but whatever.
/mob/living/simple_mob/animal/giant_spider/nurse/hat
	desc = "Furry and beige, it makes you shudder to look at it. This one has brilliant green eyes and a tiny nurse hat."
	icon_state = "nursemed"
	icon_living = "nursemed"
	icon_dead = "nursemed_dead"


// The AI for nurse spiders. Wraps things in webs by 'attacking' them.
// Get us unachored objects as an option as well.
// Select an obj if no mobs are around.
