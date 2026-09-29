/// Cadences: the one vocabulary for periodic work (systems design sec 1.3). A cadence is a singleton;
/// a system names one in `periodic_cadence` and may override the interval with `periodic_interval`.
/// The standard cadences replace the ad-hoc intervals of the periodic pipelines.
/datum/cadence
	var/name = "cadence"
	// A cadence whose abstract_type is its own path is never handed out.
	abstract_type = /datum/cadence
	/// Deciseconds between steps. 0: every tick.
	var/interval = 0
	/// The scheduler lane the cadence's steps run in.
	var/lane = LANE_SIMULATION
	/// The longest a step may be late before the scheduler borrows budget for it. 0: 4 intervals.
	var/max_interval = 0
	/// Which clock the interval counts on.
	var/clock = CLOCK_WORLD
	/// RUNLEVEL_* bits the cadence runs in.
	var/runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

/// The interval in deciseconds; a per-tick cadence is one tick.
/datum/cadence/proc/interval_ds()
	return interval || world.tick_lag

/// How late a step may run before it is urgent.
/datum/cadence/proc/max_interval_ds()
	return max_interval || interval_ds() * 4

/datum/cadence/tick
	name = "tick"
	interval = 0

/datum/cadence/fast
	name = "fast"
	interval = 0.2 SECONDS

/datum/cadence/second
	name = "second"
	interval = 1 SECONDS

/datum/cadence/slow
	name = "slow"
	interval = 2 SECONDS

/datum/cadence/life
	name = "life"
	interval = LIFE_CYCLE
	clock = CLOCK_BIO

/datum/cadence/minute
	name = "minute"
	interval = 1 MINUTES

/// The singleton of a cadence type, or null for a path that is not a cadence.
/proc/cadence(path)
	var/static/list/table = list()
	if(!ispath(path, /datum/cadence))
		return null
	. = table[path]
	if(!.)
		if(is_abstract(path))
			return null
		. = table[path] = new path
	return .

/// The cadence of a system, or null for a purely reactive one.
/datum/system/proc/system_cadence()
	return periodic_cadence ? cadence(periodic_cadence) : null

/// Deciseconds between this system's periodic steps: its own periodic_interval, else its cadence's.
/datum/system/proc/step_interval()
	if(periodic_interval)
		return periodic_interval
	var/datum/cadence/C = system_cadence()
	return C ? C.interval_ds() : 0
