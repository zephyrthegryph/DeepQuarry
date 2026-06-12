// AI Lord — a per-pack coordinator that extends the brain framework.
//
// Every quarry mob pack is assigned one /datum/ai_lord. The lord is a lightweight
// "brain of brains": it updates on its own faster subsystem (SSai_lords, every
// LORD_TICK_INTERVAL) and does the pack's shared tracking ONCE, then pushes orders
// down to the individual /datum/ai_brain members:
//   - shared threat detection: the moment ANY member sees a player (or the lord's
//     own scan does), the WHOLE pack engages that player — coordinated aggro that
//     reacts as fast as the pack's best set of eyes, not each mob independently.
//   - shared focus: members converge on one target instead of scattering.
//   - coordinated pursuit: when the player breaks line of sight, the lord steers
//     idle members toward the player's last-known tile for a grace period, then
//     stands the pack down.
//
// Members keep their own brains for moment-to-moment behavior (attacking, dodging,
// pathing). The lord only supplies pack-level awareness and target coordination —
// it never moves or attacks itself.

/datum/ai_lord
	/// Member mobs. Each has an ai_brain whose .lord points back here.
	var/list/members = list()
	/// The player the pack is currently focused on, or null when idle.
	var/mob/living/focus = null
	/// focus's last-known turf, steered toward during pursuit once LOS is lost.
	var/turf/last_known = null
	/// world.time the focus was lost; the pack pursues until +LORD_FOCUS_GRACE.
	var/lost_focus_at = 0
	/// How far the lord senses prey around the pack centroid.
	var/detect_range = LORD_DETECT_RANGE
	/// Shared perception: the living mobs seen from the centroid on the last scan,
	/// reused in place. Members bucket from this (cheap distance + disposition)
	/// instead of each running their own dview — one scan per pack per tick, not
	/// one per mob. Read by /datum/world_model/update_perception.
	var/list/perceived = list()
	/// world.time of the last scan; members fall back to self-scan once it's stale.
	var/perceived_at = 0

/datum/ai_lord/New(list/initial_members)
	SSai_lords.lords += src
	if(initial_members)
		for(var/mob/living/M as anything in initial_members)
			add_member(M)

/datum/ai_lord/Destroy()
	disband()
	return ..()

/datum/ai_lord/proc/add_member(mob/living/M)
	if(!istype(M) || !M.ai_brain || (M in members))
		return
	members += M
	M.ai_brain.lord = src

/datum/ai_lord/proc/remove_member(mob/living/M)
	members -= M
	if(M?.ai_brain && M.ai_brain.lord == src)
		M.ai_brain.lord = null
	if(!length(members))
		disband()

/// Tear down: drop member backrefs and leave the processing list. The datum then
/// has no references and is collected. Idempotent (safe to call twice).
/datum/ai_lord/proc/disband()
	for(var/mob/living/M as anything in members)
		if(M?.ai_brain && M.ai_brain.lord == src)
			M.ai_brain.lord = null
	members.Cut()
	perceived.Cut()
	SSai_lords.lords -= src

/// Rough pack centre (average member position) — detection + pursuit origin.
/datum/ai_lord/proc/pack_centroid()
	var/sx = 0
	var/sy = 0
	var/sz = 0
	var/n = 0
	for(var/mob/living/M as anything in members)
		var/turf/T = get_turf(M)
		if(!T)
			continue
		sx += T.x
		sy += T.y
		sz = T.z
		n++
	if(!n)
		return null
	return locate(round(sx / n), round(sy / n), sz)

/// The only thing a lord coordinates the pack onto: a living, cliented, alive
/// player. Mob-vs-mob stays each brain's own business, so the lord never herds the
/// pack into infighting.
/datum/ai_lord/proc/valid_prey(mob/living/H)
	return H && !QDELETED(H) && H.client && H.stat < DEAD

/// One pack-wide perception scan from the centroid, sized so it covers every
/// member's own vision (centroid distance + that member's vision_range). Fills
/// `perceived` with the living mobs in view; members read it via perception_fresh()
/// in place of a per-mob dview. dview is lighting-independent (a cave predator
/// senses prey in the dark) but opacity-blocked, so walls still hide a target.
/datum/ai_lord/proc/scan(turf/centroid)
	perceived.Cut()
	if(!centroid)
		return
	var/scan_range = detect_range
	for(var/mob/living/M as anything in members)
		var/turf/T = get_turf(M)
		if(!T)
			continue
		var/datum/ai_brain/b = M.ai_brain
		var/v = b ? b.vision_range : 7
		var/r = get_dist(centroid, T) + v
		if(r > scan_range)
			scan_range = r
	scan_range = min(scan_range, LORD_PERCEPTION_MAX_RANGE)
	for(var/mob/living/H in dview(scan_range, centroid))
		if(H.stat >= DEAD)
			continue
		perceived += H
	perceived_at = world.time

/// True when the shared scan is recent enough for members to read instead of
/// running their own dview. A scan that legitimately found nothing still counts
/// as fresh (perceived_at is set), so members in an empty area skip the dview too.
/datum/ai_lord/proc/perception_fresh()
	return perceived_at && (world.time - perceived_at <= LORD_PERCEPTION_TTL)

/// Nearest valid prey to the pack: the shared centroid scan, plus any player a
/// member is already locked onto. The member fallback preserves pack aggro when a
/// player attacks from cover the centroid can't see — without a per-member scan.
/datum/ai_lord/proc/find_focus(turf/centroid)
	var/mob/living/best = null
	var/best_dist = INFINITY
	for(var/mob/living/H as anything in perceived)
		if(!valid_prey(H))
			continue
		var/d = centroid ? get_dist(centroid, H) : 0
		if(d < best_dist)
			best = H
			best_dist = d
	for(var/mob/living/M as anything in members)
		var/datum/ai_brain/b = M.ai_brain
		var/mob/living/t = b?.primary_threat
		if(!valid_prey(t))
			continue
		var/d = centroid ? get_dist(centroid, t) : 0
		if(d < best_dist)
			best = t
			best_dist = d
	return best

/// Order every member to engage `target`. Re-pushes only on change so we don't
/// spam give_target / reselection.
/datum/ai_lord/proc/command_attack(mob/living/target)
	for(var/mob/living/M as anything in members)
		var/datum/ai_brain/b = M.ai_brain
		if(b && b.primary_threat != target)
			b.give_target(target, TRUE)

/// One coordination tick. Called by SSai_lords.
/datum/ai_lord/proc/process_lord()
	// Prune dead / gone members; disband when the pack is wiped.
	for(var/mob/living/M as anything in members.Copy())
		if(QDELETED(M) || M.stat >= DEAD || !M.ai_brain)
			remove_member(M)
	if(!length(members))
		return // disband() already ran inside remove_member

	var/turf/centroid = pack_centroid()
	// One scan for the whole pack; members read the result instead of each
	// running their own dview this strategic tick.
	scan(centroid)
	var/mob/living/prey = find_focus(centroid)
	if(prey)
		focus = prey
		last_known = get_turf(prey)
		lost_focus_at = 0
		command_attack(prey)
		return

	// Nothing in sight. Pursue the focus's last-known tile briefly, then stand down.
	if(!focus)
		return
	if(!lost_focus_at)
		lost_focus_at = world.time
	if(world.time > lost_focus_at + LORD_FOCUS_GRACE)
		focus = null
		last_known = null
		lost_focus_at = 0
		return
	if(last_known)
		for(var/mob/living/M as anything in members)
			var/datum/ai_brain/b = M.ai_brain
			if(b && !b.primary_threat)
				b.give_destination(last_known)

/// Form a lord over the brain-bearing mobs in `mobs`. Returns the lord, or null if
/// none of them have a brain. Call at every quarry pack spawn.
/proc/dq_assign_lord(list/mobs)
	if(!length(mobs))
		return null
	var/list/brained = list()
	for(var/mob/living/M in mobs)
		if(M.ai_brain)
			brained += M
	if(!length(brained))
		return null
	return new /datum/ai_lord(brained)
