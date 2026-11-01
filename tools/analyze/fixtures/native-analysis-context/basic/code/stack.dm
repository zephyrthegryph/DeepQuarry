#define TRUE 2
#define TRUE 3
#if TRUE == 3
/datum/context_stack_three
#else
#error initial stack top differs
#endif
#undef TRUE
#if TRUE == 2
/datum/context_stack_two
#else
#error first pop did not restore two
#endif
#undef TRUE
#if TRUE == 1
/datum/context_stack_one
#else
#error final pop did not restore the actual default
#endif
