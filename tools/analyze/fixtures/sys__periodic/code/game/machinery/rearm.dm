/obj/machinery/loopy/proc/tick_loop()
	do_work()
	om_after(src, 5 SECONDS, PROC_REF(tick_loop))

/obj/machinery/loopy/proc/tick_args(mob/user, amount)
	om_after(src, 5 SECONDS, PROC_REF(tick_args), user, amount)
	om_after_slot(src, 5 SECONDS, PROC_REF(tick_args), user, amount, TRUE, null, "text", SOME_DEFINE)

/obj/machinery/loopy/proc/finite(i)
	om_after(src, 2 SECONDS, PROC_REF(finite), i + 1)

/obj/machinery/loopy/proc/finite2(i)
	om_after(src, 2 SECONDS, PROC_REF(finite2), 3)

/obj/machinery/loopy/proc/finite3(i)
	om_after(src, 2 SECONDS, PROC_REF(finite3), -1)

/obj/machinery/loopy/proc/finite4(i, j)
	om_after(src, 2 SECONDS, PROC_REF(finite4), j, i)

/obj/machinery/loopy/proc/finite5(i)
	om_after(src, 2 SECONDS, PROC_REF(finite5), ++i)

/obj/machinery/loopy/proc/finite6(i)
	var/n = i
	om_after(src, 2 SECONDS, PROC_REF(finite6), n)

/obj/machinery/loopy/proc/other()
	om_after(src, 2 SECONDS, PROC_REF(tick_loop))

/obj/machinery/loopy/proc/typed()
	om_after(src, 2 SECONDS, TYPE_PROC_REF(/obj/machinery/loopy, typed))
	om_after(src, 2 SECONDS, TYPE_PROC_REF(/obj/machinery/loopy, other))

/obj/machinery/loopy/proc/nested(list/a)
	om_after(src, max(1, (2 SECONDS)), PROC_REF(nested), list(1, 2), a)

/obj/machinery/loopy/proc/nested2(a)
	om_after(src, 1 SECONDS, PROC_REF(nested2), a[1])

/obj/machinery/loopy/proc/allowed_loop()
	// ALLOW(sys_om_after_rearm): rearms until the owner is gone
	om_after(src, 5 SECONDS, PROC_REF(allowed_loop))

/obj/machinery/loopy/proc/commented()
	// om_after(src, 5 SECONDS, PROC_REF(commented))
	om_after(src, 5 SECONDS, PROC_REF(commented)) // again

/obj/machinery/loopy/proc/not_src()
	om_after(other, 5 SECONDS, PROC_REF(not_src))
	om_after(src, 5 SECONDS, PROC_REF(not_src

/obj/machinery/loopy/proc/unbalanced(a)
	om_after(src, 5 SECONDS, PROC_REF(unbalanced), a))
	om_after(src, 5 SECONDS, PROC_REF(unbalanced), a, b)
