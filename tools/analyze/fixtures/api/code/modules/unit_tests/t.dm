/obj/machinery/thing/proc/ut_writer(obj/machinery/thing/T)
	T.on = TRUE
	on = FALSE
	on = FALSE // ALLOW(api): a test that writes on purpose
	vars["x"] = 1
	om_set_var(T, "x", 1)
	om_prompt(T)
	TIMER_COOLDOWN_START(T, "k", 5)
	om_task_timed(a, done_args = list(1, 2, 3))
	om_task_start(a, b, c, list("k" = v))
