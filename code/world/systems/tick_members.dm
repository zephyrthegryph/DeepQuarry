// Per-tick member sweeps (doc/rewrite/final_api.html section 2, "Systems"; framework_gaps.md).
//
// Work that has to run once per server tick on every member: a projectile moves in pixel steps, a thrown atom moves `speed` tiles, a
// movement-affecting status effect ticks. A coarser interval changes flight and hit timing, so none of it is a per-instance
// every() (one timer per entity per tick). Each kind is a system whose one every(WORK_EVERY_TICK, ..., members = <the system>) sweeps its
// members in join order on LANE_URGENT, in the kernel's periodic phase; the kernel spreads nothing below one tick, so every member steps on
// every tick, as the continuous cadences these replace did. A member joins with SSx.kernel_join(member) and leaves with
// SSx.kernel_leave(member) (or when its step returns PROCESS_KILL, or when it is deleted).
//
// The status effects also have a one second and a 0.2 second sweep: an effect joins the one its processing_speed names.

/// Projectiles (/obj/item/projectile): moves what the elapsed time owes.
SYSTEM_DEF(projectile_steps)
	name = "Projectile steps"
	init_stage = INITSTAGE_MAIN
	periodic_runlevels = RUNLEVELS_DEFAULT
	latency_class = LATENCY_L0

/datum/system/projectile_steps/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(step_member), when = PROC_REF(work_ready), members = /datum/system/projectile_steps, phase = KERNEL_PHASE_P, lane = LANE_URGENT)

/datum/system/projectile_steps/proc/step_member(datum/member, dt)
	var/obj/item/projectile/P = member
	if(!istype(P))
		return
	if(P.projectile_step() == PROCESS_KILL)
		kernel_leave(P)

/// Pixel-moving points (/datum/point/vector/processed): hitscan tracers and beam heads.
SYSTEM_DEF(point_steps)
	name = "Point steps"
	init_stage = INITSTAGE_MAIN
	periodic_runlevels = RUNLEVELS_DEFAULT
	latency_class = LATENCY_L0

/datum/system/point_steps/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(step_member), when = PROC_REF(work_ready), members = /datum/system/point_steps, phase = KERNEL_PHASE_P, lane = LANE_URGENT)

/datum/system/point_steps/proc/step_member(datum/member, dt)
	var/datum/point/vector/processed/V = member
	if(!istype(V))
		return
	if(V.point_step() == PROCESS_KILL)
		kernel_leave(V)

/// Thrown things (/datum/thrownthing): one server tick of flight.
SYSTEM_DEF(throw_steps)
	name = "Throw steps"
	init_stage = INITSTAGE_MAIN
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	latency_class = LATENCY_L0

/datum/system/throw_steps/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(step_member), when = PROC_REF(work_ready), members = /datum/system/throw_steps, phase = KERNEL_PHASE_P, lane = LANE_URGENT)

/datum/system/throw_steps/proc/step_member(datum/member, dt)
	var/datum/thrownthing/T = member
	if(!istype(T))
		return
	if(T.throw_step() == PROCESS_KILL)
		kernel_leave(T)

/// Priority status effects (STATUS_EFFECT_PRIORITY): movement-affecting ones tick every server tick, told the 2 ds step the cadence told them.
SYSTEM_DEF(status_priority)
	name = "Priority status effects"
	init_stage = INITSTAGE_MAIN
	periodic_runlevels = RUNLEVELS_DEFAULT
	latency_class = LATENCY_L0

/datum/system/status_priority/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(step_member), when = PROC_REF(work_ready), members = /datum/system/status_priority, phase = KERNEL_PHASE_P, lane = LANE_URGENT)

/datum/system/status_priority/proc/step_member(datum/member, dt)
	var/datum/status_effect/E = member
	if(istype(E))
		E.effect_step(STATUS_EFFECT_PRIORITY_STEP)

/// Fast status effects (STATUS_EFFECT_FAST_PROCESS): every 0.2 s.
SYSTEM_DEF(status_fast)
	name = "Fast status effects"
	init_stage = INITSTAGE_MAIN
	periodic_runlevels = RUNLEVELS_DEFAULT

/datum/system/status_fast/reactions()
	. = ..()
	. += every(STATUS_EFFECT_FAST_STEP, PROC_REF(step_member), when = PROC_REF(work_ready), members = /datum/system/status_fast, phase = KERNEL_PHASE_P, lane = LANE_SIMULATION)

/datum/system/status_fast/proc/step_member(datum/member, dt)
	var/datum/status_effect/E = member
	if(istype(E))
		E.effect_step(STATUS_EFFECT_FAST_STEP)

/// Normal status effects (STATUS_EFFECT_NORMAL_PROCESS): every second.
SYSTEM_DEF(status_normal)
	name = "Status effects"
	init_stage = INITSTAGE_MAIN
	periodic_runlevels = RUNLEVELS_DEFAULT

/datum/system/status_normal/reactions()
	. = ..()
	. += every(STATUS_EFFECT_NORMAL_STEP, PROC_REF(step_member), when = PROC_REF(work_ready), members = /datum/system/status_normal, phase = KERNEL_PHASE_P, lane = LANE_SIMULATION)

/datum/system/status_normal/proc/step_member(datum/member, dt)
	var/datum/status_effect/E = member
	if(istype(E))
		E.effect_step(STATUS_EFFECT_NORMAL_STEP)
