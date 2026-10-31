/// TRUE when the running kernel pass has no budget left: a handler that walks a list saves its cursor and returns STEP_YIELD
/// (the kernel runs it again ahead of its interval).
#define KERNEL_OVER_BUDGET (TICK_USAGE > Kernel.current_ticklimit)
/// Splits the pass's remaining budget between `phase_count` stages of one handler: KERNEL_SPLIT_TICK before each stage.
#define KERNEL_SPLIT_TICK_INIT(phase_count) var/original_tick_limit = Kernel.current_ticklimit; var/split_tick_phases = ##phase_count
#define KERNEL_SPLIT_TICK \
	if(split_tick_phases > 1){\
		Kernel.current_ticklimit = ((original_tick_limit - TICK_USAGE) / split_tick_phases) + TICK_USAGE;\
		--split_tick_phases;\
	} else {\
		Kernel.current_ticklimit = original_tick_limit;\
	}


// Used to smooth out costs to try and avoid oscillation.
#define KERNEL_AVERAGE_FAST(average, current) (0.7 * (average) + 0.3 * (current))
#define KERNEL_AVERAGE(average, current) (0.8 * (average) + 0.2 * (current))
#define KERNEL_AVERAGE_SLOW(average, current) (0.9 * (average) + 0.1 * (current))

#define KERNEL_AVG_FAST_UP_SLOW_DOWN(average, current) (average > current ? KERNEL_AVERAGE_SLOW(average, current) : KERNEL_AVERAGE_FAST(average, current))
#define KERNEL_AVG_SLOW_UP_FAST_DOWN(average, current) (average < current ? KERNEL_AVERAGE_SLOW(average, current) : KERNEL_AVERAGE_FAST(average, current))

///creates a running average of "things elapsed" per time period when you need to count via a smaller time period.
///eg you want an average number of things happening per second but you measure the event every tick (50 milliseconds).
///make sure both time intervals are in the same units. doesn't work if current_duration > total_duration or if total_duration == 0
#define KERNEL_AVG_OVER_TIME(average, current, total_duration, current_duration) ((((total_duration) - (current_duration)) / (total_duration)) * (average) + (current))

#define KERNEL_AVG_MINUTES(average, current, current_duration) (KERNEL_AVG_OVER_TIME(average, current, 1 MINUTES, current_duration))

#define KERNEL_AVG_SECONDS(average, current, current_duration) (KERNEL_AVG_OVER_TIME(average, current, 1 SECONDS, current_duration))

// START_PROCESSING/STOP_PROCESSING are gone (roadmap S4): periodic work runs on object-model
// pipelines, cadence_start()/cadence_stop() (code/engine/kernel/cadences.dm).

/// Returns true if the kernel is initialized and running.
/// Optional argument init_stage controls what stage the mc must have initialized to count as initialized. Defaults to INITSTAGE_MAX if not specified.
#define KERNEL_RUNNING(INIT_STAGE...) (Kernel && Kernel.processing > 0 && Kernel.current_runlevel && Kernel.init_stage_completed >= (max(min(INITSTAGE_MAX, ##INIT_STAGE), 1)))

#define KERNEL_LOOP_RTN_NEWSTAGES 1
#define KERNEL_LOOP_RTN_GRACEFUL_EXIT 2

// Init stages: a system boots in the stage of its latest need (kernel/boot.dm)
#define INITSTAGE_FIRST 1
#define INITSTAGE_EARLY 2 //! Early init stuff that doesn't need to wait for mapload
#define INITSTAGE_MAIN 3 //! Main init stage
#define INITSTAGE_LAST 4
#define INITSTAGE_MAX 4 //! Highest initstage.

/// Declares a system and its `SS<X>` global: SSX is the instance of /datum/system/X, set when the kernel creates it
/// (kernel_create_systems(), Kernel.preboot()). The body is the system's: needs, phase, roles, every() in reactions(), initialize()
/// and its api procs.
#define SYSTEM_DEF(X) GLOBAL_REAL(SS##X, /datum/system/##X);\
/datum/system/##X/New(){\
	..();\
	SS##X = src;\
}\
/datum/system/##X



#define CURRENT_RUNLEVEL (2 ** (Kernel.current_runlevel - 1))
