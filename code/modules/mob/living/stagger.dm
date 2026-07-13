// Stagger / poise — a universal "guard break" meter, separate from health and stamina.
//
// Landing melee hits and (especially) PARRIES fill a target's stagger. At the cap it
// BREAKS: the target is knocked off-balance and held open for a moment — the window to
// execute a mob, or for a predator to grapple a player. Poise decays once you stop
// applying pressure, so a break has to be earned by sustained aggression, not chip damage.
//
// Lives on /mob/living so it works both ways: the player breaks mobs open to finish them,
// and mobs break the player open to grab/devour them. Decay is lazy (computed on the next
// hit) so there's no per-tick cost on the thousands of idle fauna a layer can hold.

/mob/living
	/// Current poise damage. At max_stagger the mob breaks (see stagger_break).
	var/stagger = 0
	/// Poise ceiling. Tougher mobs raise this so they take more to break.
	var/max_stagger = DQ_STAGGER_MAX
	/// world.time the broken-open window ends. While in the future the mob is staggered.
	var/stagger_broken_until = 0
	/// world.time before which poise can't be refilled toward another break (anti-stunlock).
	var/stagger_immune_until = 0
	/// world.time of the last poise hit — decay stays paused until DQ_STAGGER_DECAY_DELAY past it.
	var/last_stagger_time = 0

/// Lazily bleed off poise for the quiet time since the last hit, then return the decayed value.
/mob/living/proc/decayed_stagger()
	if(stagger <= 0 || !last_stagger_time)
		return stagger
	var/quiet = world.time - last_stagger_time
	if(quiet <= DQ_STAGGER_DECAY_DELAY)
		return stagger
	var/recovered = (quiet - DQ_STAGGER_DECAY_DELAY) / (1 SECONDS) * DQ_STAGGER_DECAY_RATE
	stagger = max(0, stagger - recovered)
	return stagger

/// TRUE while this mob is broken open from a stagger break.
/mob/living/proc/is_stagger_broken()
	return world.time < stagger_broken_until

/// Add poise damage. `source` is the attacker (for the break message/credit). No-op on the
/// dead, already-broken (finish it instead), or inside the post-break immunity grace — so a
/// sustained attacker can't chain breaks into a perpetual stunlock.
/mob/living/proc/add_stagger(amount, mob/source)
	if(amount <= 0 || stat >= DEAD || is_stagger_broken() || world.time < stagger_immune_until)
		return
	amount *= perk_mult(DQ_PERK_FX_STAGGER_RESIST) // Immovable: your guard is harder to break.
	if(amount <= 0)
		return
	decayed_stagger() // apply pending decay before topping up
	stagger = min(stagger + amount, max_stagger)
	last_stagger_time = world.time
	dqai_pdbg(source, "STAGGER", "+[amount] poise on [src] -> [round(stagger)]/[max_stagger]", src)
	if(stagger >= max_stagger)
		stagger_break(source)

/// Break: empty the meter, open the vulnerable window, knock the target off-balance, and
/// tell everyone. A broken mob is open to an execution; a broken player is open to a grapple.
/// A grace period after the window blocks an immediate re-break (anti-stunlock).
/mob/living/proc/stagger_break(mob/source)
	dqai_pdbg(source, "STAGGER", "BREAK on [src] — open [DQ_STAGGER_BREAK_DURATION/10]s, immune [(DQ_STAGGER_BREAK_DURATION+DQ_STAGGER_IMMUNE_GRACE)/10]s", src)
	stagger = 0
	stagger_broken_until = world.time + DQ_STAGGER_BREAK_DURATION
	stagger_immune_until = stagger_broken_until + DQ_STAGGER_IMMUNE_GRACE
	Weaken(2)
	if(isliving(source)) // Concussive Blows: a staggered target is left reeling.
		var/mob/living/staggerer = source
		if(staggerer.has_perk(/datum/perk/body/str_concussive))
			Weaken(2)
	melee_locked_until = max(melee_locked_until, world.time + DQ_STAGGER_BREAK_DURATION)
	visible_message(
		span_danger("\The [src]'s guard breaks — they're staggered wide open!"),
		span_danger("Your guard shatters — you're staggered and wide open!"),
	)
	playsound(src, 'sound/effects/bonebreak1.ogg', 55, 1, -1)
	var/turf/T = get_turf(src)
	if(T)
		dq_telegraph(T, 4, DQ_TELEGRAPH_DODGE) // a red pop on the broken tile
