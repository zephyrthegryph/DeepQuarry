#define CAP_X (1<<11)
#define CAP_S1 (1<<12)
#define CAP_DUP (1<<12)
#define CAP_BIG (1<<30)
/obj/x
	cap_state = CAP_A
	var/cap_state = 3
	var/obj/cap_state
/obj/x/proc/y()
	cap_state |= 2
	cap_state &= ~2
	cap_state ^= 1
	if(cap_state == 2)
		to_chat("a")
	cap_state = 5
	cap_state = /obj/x
	x.cap_state = 3
	var/s = "cap_state = 1"
	// cap_state = 1
	cap_state = 1 // trailing
		cap_state = 3
cap_state = 3
	cap_state=CAP_A
	cap_state != 3
	cap_state	=	CAP_B
