// rolls(target, generator, when =, from =): per-instance randomness, rolled when the instance is created, before its init code reads it
// (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 1).
//
//	CAPABILITIES(/obj/item/trash/cigbutt)
//		rolls(ROLL_PIXEL, PIXEL_JITTER(10))                                     // was randpixel_xy() in Initialize()
//		rolls(nameof(transform_angle), range_of(0, 359))
//	CAPABILITIES(/obj/item/rock)
//		rolls(nameof(icon_state), pick_one(list("rock1", "rock2", "rock3")))
//		rolls(nameof(mineral), pick_weighted(list(/datum/ore/iron = 5, /datum/ore/gold = 1)))
//		rolls(nameof(cracked), chance(15))
//		rolls(nameof(desc), PROC_REF(roll_desc), from = list(nameof(mineral)))   // a roll that reads another roll
//		rolls(nameof(glows), chance(50), when = nameof(radioactive))
//
// Generators: pick_one(list) (uniform, or weighted by the values of an associative list), pick_weighted(list) (weighted by the values),
// range_of(lo, hi, step = 1) (a number in [lo, hi] on the step; a step of 0 is a real number), PIXEL_JITTER(n) (with ROLL_PIXEL: each pixel
// offset in -n..n), chance(p) (TRUE with p percent), and PROC_REF(x), a holder proc x(datum/roller/R) that answers the value from R's
// draws (R.number(lo, hi), R.choose(list), R.chance(p), R.weighted(list), R.unit(), R.hex_colour(), R.saturated_colour()).
//
// The seed. Every instance rolls from its own deterministic stream: the round seed with the map position of a map-loaded instance (its turf
// and its index among the same type there), or its creator's stream for an instance created while another one initializes (contents, a
// make(..., by =) call). Anything else takes the round seed and a creation serial. The same round seed on the same map rolls the same map.
// rolls_fix_seed(seed) fixes the round seed for a test; GLOB.round_seed is set once per round otherwise.
//
// A map-edited value suppresses the roll, as does a value a param() or make() gave: a target whose value differs from its compiled default is
// left alone. `when =` gates one roll on a condition (section 5), read after the rolls before it. `from =` names other targets whose rolls must
// come first; the engine orders them, and a cycle is a declaration error.
//
// Behaviour change (doc/rewrite/intended_changes.md): the distributions are the same, the realisation is seeded (a converted rand() no longer
// draws from the world RNG).

/proc/rolls(target, generator, when = null, from = null)
	if(isnull(target) || isnull(generator))
		declare_report("rolls(): needs a target and a generator")
		return null
	if(!islist(from) && !isnull(from))
		from = list(from)
	return entry_make(ENTRY_ROLLS, "rolls:[target]", list("target" = target, "gen" = generator, "when" = when, "from" = from))

/// A generator datum entry (PIXEL_JITTER and the named generators below build one).
/proc/roll_gen(kind, list/gen_args)
	return entry_make("roll_gen", null, list("gen" = kind, "args" = gen_args))

/// pick_weighted(list(a = 3, b = 1)): one key, weighted by its value.
/proc/pick_weighted(list/weighted)
	return roll_gen("weighted", list(weighted))

/// range_of(lo, hi, step = 1): a number in [lo, hi]. `range` is BYOND's own proc and `between` a clamp macro here: the generator is range_of().
/proc/range_of(lo, hi, step = 1)
	if(!isnum(lo) || !isnum(hi) || hi < lo)
		declare_report("range_of([lo], [hi]): needs two numbers, lo <= hi")
	return roll_gen("range", list(lo, hi, step))

// ---- the seed ----

/// The round's seed (a 24-bit number), drawn once from the world RNG. Fixed by a test with rolls_fix_seed().
GLOBAL_VAR_INIT(round_seed, rand(1, 16777215))
/// A serial for instances rolled with no position and no creator.
GLOBAL_VAR_INIT(roll_serial, 0)
/// The rollers of the instances initializing now, innermost last: an instance created while one initializes rolls from its stream.
GLOBAL_LIST_EMPTY(roll_creators)
/// instance -> its roller, while it initializes.
GLOBAL_LIST_EMPTY(roll_rollers)

/proc/round_seed()
	if(isnull(GLOB?.round_seed))
		return 1 // the globals are still being made: a fixed seed for what rolls before them
	return GLOB.round_seed

/// Fixes the round seed (tests): the same seed and the same creation order give the same rolls. Resets the creation serial.
/proc/rolls_fix_seed(seed)
	GLOB.round_seed = seed
	GLOB.roll_serial = 0

/// A deterministic stream of draws. Each draw is md5 of the stream's base and a counter: native, stable across builds and platforms.
/datum/roller
	/// The stream's identity: the seed text every draw hashes.
	var/base
	var/draws = 0
	/// How many instances this stream has created (each child's stream is base/child_n).
	var/children = 0

/datum/roller/New(base)
	src.base = base

/// A number in [0, 1).
/datum/roller/proc/unit()
	draws++
	var/hex = copytext(md5("[base]|[draws]"), 1, 7)
	return text2num(hex, 16) / 16777216

/// An integer in [lo, hi].
/datum/roller/proc/number(lo = 0, hi = 1)
	if(hi < lo)
		var/swap = lo
		lo = hi
		hi = swap
	return lo + min(floor(unit() * (hi - lo + 1)), hi - lo)

/// TRUE with `percent` percent.
/datum/roller/proc/chance(percent)
	return unit() * 100 < percent

/// One element of `L`, uniform.
/datum/roller/proc/choose(list/L)
	if(!length(L))
		return null
	return L[number(1, length(L))]

/// One key of `L`, weighted by its value (a missing or non-number weight counts 1).
/datum/roller/proc/weighted(list/L)
	var/total = 0
	for(var/key in L)
		var/w = L[key]
		total += isnum(w) ? max(w, 0) : 1
	if(total <= 0)
		return choose(L)
	var/at = unit() * total
	for(var/key in L)
		var/w = L[key]
		at -= isnum(w) ? max(w, 0) : 1
		if(at < 0)
			return key
	return L[length(L)]

/// A "#RRGGBB" colour, each channel in [lower, upper] (get_random_colour()'s distribution).
/datum/roller/proc/hex_colour(lower = 0, upper = 255)
	. = "#"
	for(var/i in 1 to 3)
		var/channel = num2hex(number(lower, upper), 2)
		. += length(channel) < 2 ? "0[channel]" : channel

/// A colour kept away from pure black and pure white, for greyscale sprites (random_color(TRUE)'s distribution).
/datum/roller/proc/saturated_colour()
	var/r = number(1, 255)
	var/g = number(1, 255)
	var/b = number(1, 255)
	if(r + g + b < 50)
		r += number(5, 20)
		g += number(5, 20)
		b += number(5, 20)
	else if(r + g + b > 700)
		r -= number(5, 50)
		g -= number(5, 50)
		b -= number(5, 50)
	return rgb(r, g, b)

/// The seed text of a new instance: its creator's stream, its map position, or the round seed and a serial.
/proc/roll_base_for(datum/holder)
	var/datum/roller/creator = length(GLOB?.roll_creators) ? GLOB.roll_creators[length(GLOB.roll_creators)] : null
	if(creator && creator != GLOB.roll_rollers[holder])
		creator.children++
		return "[creator.base]/[creator.children]"
	if(isatom(holder))
		var/atom/A = holder
		if(isturf(A))
			return "[round_seed()]@[A.x],[A.y],[A.z]:[A.type]"
		var/turf/T = A.loc
		if(isturf(T))
			// Directly on a turf (a map-placed instance): its position and its index among the same type there.
			var/index = 0
			for(var/atom/movable/other as anything in contents_of(T))
				if(other.type == A.type)
					index++
				if(other == A)
					break
			return "[round_seed()]@[T.x],[T.y],[T.z]:[A.type]:[index]"
	return "[round_seed()]#[++GLOB.roll_serial]:[holder.type]"

/// The roller of `holder` while it initializes (made on first use).
/proc/roller_of(datum/holder)
	RETURN_TYPE(/datum/roller)
	if(!islist(GLOB?.roll_rollers))
		return new /datum/roller("1#[holder.type]") // the globals are still being made
	var/datum/roller/R = GLOB.roll_rollers[holder]
	if(!R)
		R = new /datum/roller(roll_base_for(holder))
		GLOB.roll_rollers[holder] = R
	return R

/// While `holder` creates its contents, what it creates rolls from its stream. Returns TRUE when it pushed (pop it after).
/proc/roll_creator_push(datum/holder)
	GLOB.roll_creators += roller_of(holder)
	return TRUE

/proc/roll_creator_pop(datum/holder)
	var/datum/roller/R = GLOB.roll_rollers[holder]
	if(length(GLOB.roll_creators) && GLOB.roll_creators[length(GLOB.roll_creators)] == R)
		GLOB.roll_creators.len--
	GLOB.roll_rollers -= holder

// ---- rolling ----

/// Rolls every rolls() of the type on `holder`, in dependency order.
/proc/rolls_run(datum/holder, datum/lifeform_plan/P, mapload)
	var/datum/roller/R = roller_of(holder)
	var/list/pending = P.rolls.Copy()
	var/list/done = list()
	var/guard = length(pending) + 1
	while(length(pending) && guard-- > 0)
		for(var/datum/centry/C as anything in pending.Copy())
			var/datum/entry/E = C.item
			var/ready = TRUE
			for(var/dep in E.args["from"])
				if(!done[dep] && rolls_target_declared(P, dep))
					ready = FALSE
					break
			if(!ready)
				continue
			pending -= C
			done[E.args["target"]] = TRUE
			roll_one(holder, R, C)
	for(var/datum/centry/C as anything in pending)
		var/datum/entry/E = C.item
		declare_report("[C.origin]: rolls([E.args["target"]]) on [holder.type]: its from = makes a cycle; it was not rolled")
	// The roller stays while the instance initializes (its contents roll from it); lifeform_init() drops it.
	if(!(lifeform_plan_of(holder).init))
		GLOB.roll_rollers -= holder

/proc/rolls_target_declared(datum/lifeform_plan/P, target)
	for(var/datum/centry/C as anything in P.rolls)
		var/datum/entry/E = C.item
		if(E.args["target"] == target)
			return TRUE
	return FALSE

/// TRUE when `target` of `holder` holds its compiled default (no map edit, no param): only then does a roll write it.
/proc/roll_target_untouched(datum/holder, target)
	if(target == ROLL_PIXEL)
		var/atom/A = holder
		return A.pixel_x == initial(A.pixel_x) && A.pixel_y == initial(A.pixel_y)
	if(!(target in holder.vars))
		return FALSE
	return holder.vars[target] == initial(holder.vars[target])

/proc/roll_one(datum/holder, datum/roller/R, datum/centry/C)
	var/datum/entry/E = C.item
	var/target = E.args["target"]
	if(target != ROLL_PIXEL && !(target in holder.vars))
		declare_report("[C.origin]: rolls([target]) on [holder.type]: no such var")
		return
	if(!roll_target_untouched(holder, target))
		return
	if(C.whens && !op_whens_hold(holder, C.whens))
		return
	if(!isnull(E.args["when"]) && !condition_holds(holder, E.args["when"]))
		return
	var/value = roll_generate(holder, R, E.args["gen"], C)
	if(target == ROLL_PIXEL)
		var/atom/A = holder
		if(islist(value))
			A.pixel_x = value[1]
			A.pixel_y = value[2]
		return
	holder.vars[target] = value // ALLOW(api): a roll writes its declared target before init, as a map edit would

/// One value of `gen` for `holder` from stream R.
/proc/roll_generate(datum/holder, datum/roller/R, gen, datum/centry/C)
	if(istext(gen))
		if(hascall(holder, gen))
			return call(holder, gen)(R)
		declare_report("[C?.origin]: rolls(): [holder.type] has no proc [gen] to roll with")
		return null
	if(islist(gen))
		return R.choose(gen)
	var/datum/entry/G = gen
	if(!istype(G))
		return gen
	switch(G.kind)
		if("pick_one")
			var/list/choices = G.args["weights"]
			if(roll_list_weighted(choices))
				return R.weighted(choices)
			return R.choose(choices)
		if(ENTRY_CHANCE)
			return R.chance(G.args["percent"])
		if("roll_gen")
			var/list/gen_args = G.args["args"]
			switch(G.args["gen"])
				if("weighted")
					return R.weighted(gen_args[1])
				if("range")
					var/lo = gen_args[1]
					var/hi = gen_args[2]
					var/step = gen_args[3]
					if(!step)
						return lo + R.unit() * (hi - lo)
					return lo + step * R.number(0, floor((hi - lo) / step))
				if("jitter")
					var/n = gen_args[1]
					if(istext(n))
						n = (n in holder.vars) ? holder.vars[n] : 0 // PIXEL_JITTER(nameof(randpixel)): the holder's own range
					return list(R.number(-n, n), R.number(-n, n))
	declare_report("[C?.origin]: rolls(): [G.kind] is not a generator (pick_one, pick_weighted, range_of, PIXEL_JITTER, chance, PROC_REF)")
	return null

/// TRUE when an associative list carries number weights.
/proc/roll_list_weighted(list/L)
	for(var/key in L)
		if(!isnum(key) && isnum(L[key]))
			return TRUE
	return FALSE
