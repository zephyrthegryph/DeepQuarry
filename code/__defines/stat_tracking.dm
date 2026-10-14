//
// Defines used for advanced performance profiling of subsystems.
// Currently used only by SSoverlays (2018-02-24 ~Leshana)
//
#define STAT_ENTRY_TIME 1
#define STAT_ENTRY_COUNT 2
#define STAT_ENTRY_LENGTH 2

#define STAT_START_STOPWATCH var/STAT_STOP_WATCH = TICK_USAGE
#define STAT_STOP_STOPWATCH var/STAT_TIME = TICK_USAGE_TO_MS(STAT_STOP_WATCH)
