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
	SSai_lords.lords -= src

/// The only thing a lord coordinates the pack onto: a living, cliented, alive
/// player. Mob-vs-mob stays each brain's own business, so the lord never herds the
/// pack into infighting.
/datum/ai_lord/proc/valid_prey(mob/living/H)
	return H && !QDELETED(H) && H.client && H.stat < DEAD

/// Nearest valid prey to the pack, drawn ONLY from what the MEMBERS actually SEE
/// this tick (their visible_hostiles). Each member runs its own perception, so the
/// pack engages the instant ANY member's eyes catch a player, and distance is
/// measured from the seeing member — detection range is just the members' own vision.
///
/// Deliberately does NOT read members' primary_threat: the lord SETS that via
/// command_attack, so reading it back makes focus self-perpetuating — the pack could
/// never lose sight (a member holding a lord-assigned target re-reports it as "prey
/// found"), so it would pursue forever and never stand down. Retention is the lord's
/// own job: when no member can see the player, find_focus returns null and the lord
/// pursues last_known for LORD_FOCUS_GRACE before releasing the pack.
/datum/ai_lord/proc/find_focus()
	var/mob/living/best = null
	var/best_dist = INFINITY
	for(var/mob/living/M as anything in members)
		var/datum/ai_brain/b = M.ai_brain
		if(!b || !b.model)
			continue
		for(var/mob/living/H as anything in b.model.visible_hostiles)
			if(!valid_prey(H))
				continue
			var/d = get_dist(M, H)
			if(d < best_dist)
				best = H
				best_dist = d
	return best

/// Drop the lord-assigned target on every member still locked onto our focus, so the
/// pack actually disengages (and leaves the 250ms fast tick) on standdown. Members
/// that have independently re-acquired some other target are left alone.
/datum/ai_lord/proc/release_members()
	for(var/mob/living/M as anything in members)
		var/datum/ai_brain/b = M.ai_brain
		if(b && b.primary_threat == focus)
			b.primary_threat = null
			b.lose_threat_at = 0
			b.pack_role = DQ_ROLE_NONE
			b.flank_dir = 0
			b.invalidate_selection()
			b.update_engagement()

/// Order members within LORD_COMMAND_RANGE of the prey to engage `target`. A member too far
/// to plausibly be in the fight is NOT teleport-aggroed across the layer — it engages on its
/// own once it sees (or hears) the prey. Re-pushes only on change so we don't spam reselection.
/datum/ai_lord/proc/command_attack(mob/living/target)
	for(var/mob/living/M as anything in members)
		var/datum/ai_brain/b = M.ai_brain
		if(!b || b.primary_threat == target)
			continue
		if(get_dist(M, target) > LORD_COMMAND_RANGE)
			continue
		if(dq_prey_locked_by_other(M, target)) // another member has it grabbed to eat — don't pile on
			continue
		b.give_target(target, TRUE)

/// Rough pack centre — the direction the pack is mostly coming from, used to spread
/// flankers to the sides and rear of the target. `restrict_z` counts only members on that
/// z (the quarry is multi-z; averaging across z-levels yields a meaningless tile/dir).
/datum/ai_lord/proc/pack_centroid(restrict_z = 0)
	var/sx = 0
	var/sy = 0
	var/sz = restrict_z
	var/n = 0
	for(var/mob/living/M as anything in members)
		var/turf/T = get_turf(M)
		if(!T)
			continue
		if(restrict_z && T.z != restrict_z)
			continue
		sx += T.x
		sy += T.y
		sz = T.z
		n++
	if(!n)
		return null
	return locate(round(sx / n), round(sy / n), sz)

/// Hand out pincer roles around `prey`. Ranged members harry from afar; the nearest one
/// or two melee members anchor the front (the face the pack is coming from); the rest
/// flank, each assigned a distinct slot fanning out to the sides and rear so the pack
/// surrounds the target instead of stacking onto one tile. Cheap: one sort + a walk over
/// a handful of members, only while the lord actually has a focus.
/datum/ai_lord/proc/assign_roles(mob/living/prey)
	var/turf/pt = get_turf(prey)
	if(!pt)
		return
	var/turf/centroid = pack_centroid(pt.z) // only members sharing the prey's z flank coherently
	if(!centroid)
		return
	var/front = get_dir(pt, centroid) || NORTH // the face the pack approaches from
	// Slots fan out to the SIDES of the approach face, not the rear — sending a mob to the
	// far side of the target makes it path away from the player and round the back, which
	// reads as fleeing. Side slots spread the pack laterally while everyone keeps closing.
	var/static/list/flank_turns = list(90, -90, 45, -45)
	// Bucket members: ranged → harrier (no slot); the rest are melee, ordered nearest-
	// first to the prey by a small insertion sort (packs are only a handful of mobs).
	var/list/melee = list()      // mob -> distance to prey
	var/list/ordered = list()    // melee mobs, nearest first
	for(var/mob/living/M as anything in members)
		var/datum/ai_brain/b = M.ai_brain
		if(!b)
			continue
		var/turf/mt = get_turf(M)
		if(!mt || mt.z != pt.z) // a member on another quarry layer can't flank coherently
			continue
		if(istype(M, /mob/living/simple_mob))
			var/mob/living/simple_mob/SM = M
			if(SM.projectiletype && SM.melee_damage_upper <= 0)
				b.pack_role = DQ_ROLE_HARRIER
				b.flank_dir = 0
				continue
		var/d = get_dist(mt, pt)
		melee[M] = d
		var/placed = FALSE
		for(var/i in 1 to length(ordered))
			if(d < melee[ordered[i]])
				ordered.Insert(i, M)
				placed = TRUE
				break
		if(!placed)
			ordered += M
	var/anchors = (length(ordered) >= 4) ? 2 : 1
	var/flank_i = 0
	for(var/i in 1 to length(ordered))
		var/mob/living/M = ordered[i]
		var/datum/ai_brain/b = M.ai_brain
		if(i <= anchors)
			b.pack_role = DQ_ROLE_ANCHOR
			b.flank_dir = front // press the front face head-on
		else
			b.pack_role = DQ_ROLE_FLANKER
			b.flank_dir = turn(front, flank_turns[(flank_i % length(flank_turns)) + 1])
			flank_i++

/// One coordination tick. Called by SSai_lords.
/datum/ai_lord/proc/process_lord()
	// Prune dead / gone members; disband when the pack is wiped.
	for(var/mob/living/M as anything in members.Copy())
		if(QDELETED(M) || M.stat >= DEAD || !M.ai_brain)
			remove_member(M)
	if(!length(members))
		return // disband() already ran inside remove_member

	var/mob/living/prey = find_focus()
	if(prey)
		if(focus != prey && length(members))
			dqai_pdbg(members[1], "LORD", "pack focus -> [prey.name]: commanding [length(members)] members to engage + assigning flank roles", prey)
		focus = prey
		last_known = get_turf(prey)
		lost_focus_at = 0
		command_attack(prey)
		assign_roles(prey)
		return

	// Nothing in sight. Pursue the focus's last-known tile briefly, then stand down.
	if(!focus)
		return
	if(!lost_focus_at)
		lost_focus_at = world.time
	if(world.time > lost_focus_at + LORD_FOCUS_GRACE)
		if(length(members))
			dqai_pdbg(members[1], "LORD", "pack standdown — lost [focus ? focus.name : "focus"] for [LORD_FOCUS_GRACE/10]s, releasing [length(members)] members", focus)
		release_members() // clear lord-assigned targets BEFORE nulling focus (it keys off focus)
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
