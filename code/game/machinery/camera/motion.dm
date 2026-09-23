/obj/machinery/camera
	var/list/motionTargets = null
	var/detectTime = 0
	var/area/ai_monitored/area_motion = null
	var/alarm_delay = 100 // Don't forget, there's another 10 seconds in queueAlarm()

/// The motion alarm fires once a target has been seen for alarm_delay (the camera's timer).
/obj/machinery/camera/proc/check_motion_alarm()
	if(stat & (NOPOWER|EMPED))
		return
	if(!isMotion())
		return
	if(detectTime > 0 && world.time - detectTime > alarm_delay)
		triggerAlarm()

/obj/machinery/camera/proc/newTarget(mob/target)
	if (isAI(target)) return 0
	if (detectTime == 0)
		detectTime = world.time // start the clock
	if (!(target in motionTargets))
		LAZYADD(motionTargets, target)
		// Losing a target is event driven: it moves, dies or is deleted.
		RegisterSignal(target, COMSIG_MOVABLE_MOVED, PROC_REF(on_motion_target_changed), TRUE)
		RegisterSignal(target, COMSIG_MOB_STATCHANGE, PROC_REF(on_motion_target_changed), TRUE)
		RegisterSignal(target, COMSIG_QDELETING, PROC_REF(on_motion_target_deleted), TRUE)
	schedule_camera_timer()
	return 1

/// A tracked target moved or changed stat: drop it if it died or (outside an
/// ai_monitored area, which tracks its own exits) left the camera's range.
/obj/machinery/camera/proc/on_motion_target_changed(mob/target)
	SIGNAL_HANDLER
	if(target.stat == DEAD || (!area_motion && !in_range(src, target)))
		lostTarget(target)

/obj/machinery/camera/proc/on_motion_target_deleted(mob/target)
	SIGNAL_HANDLER
	lostTarget(target)

/obj/machinery/camera/proc/lostTarget(mob/target)
	if (target in motionTargets)
		LAZYREMOVE(motionTargets, target)
		UnregisterSignal(target, list(COMSIG_MOVABLE_MOVED, COMSIG_MOB_STATCHANGE, COMSIG_QDELETING))
	if (LAZYLEN(motionTargets) == 0)
		cancelAlarm()

/obj/machinery/camera/proc/cancelAlarm()
	if (!status || (stat & NOPOWER))
		return 0
	if (detectTime == -1)
		GLOB.motion_alarm.clearAlarm(loc, src)
	detectTime = 0
	return 1

/obj/machinery/camera/proc/triggerAlarm()
	if (!status || (stat & NOPOWER))
		return 0
	if (!detectTime) return 0
	GLOB.motion_alarm.triggerAlarm(loc, src)
	detectTime = -1
	return 1

/obj/machinery/camera/HasProximity(turf/T, datum/weakref/WF, old_loc)
	if(isnull(WF))
		return
	var/atom/movable/AM = WF.resolve()
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return
	// Motion cameras outside of an "ai monitored" area will use this to detect stuff.
	if (!area_motion)
		if(isliving(AM))
			newTarget(AM)
