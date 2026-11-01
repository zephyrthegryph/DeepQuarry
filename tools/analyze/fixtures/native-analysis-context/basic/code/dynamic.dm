#ifdef __MAIN__
#error child opened file is not the environment even with a table definition
#endif
#if defined(__MAIN__)
/datum/context_child_defined_main
#endif
#ifdef __FILE__
#error FILE is not a table macro
#endif
/proc/context_defined_probe()
    return defined(SPACEMAN_DMM)
