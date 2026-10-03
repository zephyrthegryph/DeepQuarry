/obj/machinery/afterloop/proc/tick_loop()
	do_work()
	after(src, 5 SECONDS, PROC_REF(tick_loop))

/obj/machinery/afterloop/proc/tick_args(mob/user, amount)
	after(src, 5 SECONDS, PROC_REF(tick_args), with = list(user, amount))
	after_slot(src, "slot", 5 SECONDS, PROC_REF(tick_args), user, amount)
	after(src, 5 SECONDS, PROC_REF(tick_args), key = "slot", with = list(user, amount, TRUE, "text"))

/obj/machinery/afterloop/proc/finite(i)
	after(src, 2 SECONDS, PROC_REF(finite), with = list(i + 1))

/obj/machinery/afterloop/proc/finite2(i, j)
	after(src, 2 SECONDS, PROC_REF(finite2), with = list(j, i))

/obj/machinery/afterloop/proc/other()
	after(src, 2 SECONDS, PROC_REF(tick_loop))

/obj/machinery/afterloop/proc/not_src()
	after(other, 5 SECONDS, PROC_REF(not_src))

/obj/machinery/afterloop/proc/allowed_loop()
	// ALLOW(sys_om_after_rearm): rearms until the owner is gone
	after(src, 5 SECONDS, PROC_REF(allowed_loop))
