#define CAP_C (1<<1)
#define CAP_D (1<<30)
/obj/probe
	cap_state = CAP_A
/obj/probe/proc/run()
	cap_state |= CAP_B
