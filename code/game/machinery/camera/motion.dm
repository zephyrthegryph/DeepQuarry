/obj/machinery/camera
	var/list/motionTargets = null
	EXPIRY_DECLARE(detectTime)
	var/area/ai_monitored/area_motion
	var/alarm_delay = 100 // Don't forget, there's another 10 seconds in queueAlarm()

/// The motion alarm fires once a target has been seen for alarm_delay (the camera's timer).
/obj/machinery/camera/proc/check_motion_alarm()
	if((power_lost() || emp_held()))
		return
	if(!isMotion())
		return
	if(detectTime > 0 && ELAPSED(src, detectTime, CLOCK_WORLD) > alarm_delay)
		triggerAlarm()

/obj/machinery/camera/proc/newTarget(mob/target)
	if (isAI(target)) return 0
	if (detectTime == 0)
		EXPIRY_STAMP(src, detectTime, CLOCK_WORLD) // start the clock
	if (!(target in motionTargets))
		LAZYADD(motionTargets, target)
		// Losing a target is event driven: it moves, dies or is deleted.
		observe(target, /datum/notice/moved, src, then(PROC_REF(on_motion_target_changed)))
		observe(target, /datum/notice/mob_statchange, src, then(PROC_REF(on_motion_target_changed)))
		observe(target, /datum/notice/qdeleting, src, then(PROC_REF(on_motion_target_deleted)))
	schedule_camera_timer()
	return 1

/// A tracked target moved or changed stat: drop it if it died or (outside an
/// ai_monitored area, which tracks its own exits) left the camera's range.
/obj/machinery/camera/proc/on_motion_target_changed(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/target = A.target
	if(target.stat == DEAD || (!area_motion() && !in_range(src, target)))
		lostTarget(target)

/obj/machinery/camera/proc/on_motion_target_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/target = A.target
	lostTarget(target)

/obj/machinery/camera/proc/lostTarget(mob/target)
	if (target in motionTargets)
		LAZYREMOVE(motionTargets, target)
		unobserve(target, /datum/notice/moved, src)
		unobserve(target, /datum/notice/mob_statchange, src)
		unobserve(target, /datum/notice/qdeleting, src)
	if (LAZYLEN(motionTargets) == 0)
		cancelAlarm()

/obj/machinery/camera/proc/cancelAlarm()
	if (!status || (power_lost()))
		return 0
	if (detectTime == -1)
		GLOB.motion_alarm.clearAlarm(loc, src)
	detectTime = 0
	return 1

/obj/machinery/camera/proc/triggerAlarm()
	if (!status || (power_lost()))
		return 0
	if (!detectTime) return 0
	GLOB.motion_alarm.triggerAlarm(loc, src)
	detectTime = -1
	return 1

/obj/machinery/camera/HasProximity(turf/T, WF, old_loc)
	if(isnull(WF))
		return
	var/atom/movable/AM = WF
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return
	// Motion cameras outside of an "ai monitored" area will use this to detect stuff.
	if (!area_motion())
		if(isliving(AM))
			newTarget(AM)

/// area motion (a relation view: it reads null once the target is deleted).
/obj/machinery/camera/proc/area_motion() as /area/ai_monitored
	return area_motion
