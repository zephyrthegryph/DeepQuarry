/proc/rules_test(a, b, c)
	// ---- do_after_state ----
	om_task_timed(a, b, c, d, e, list(1, 2, 3))
	om_task_timed(a, b, c, d, e, list(1, 2))
	om_task_timed(a, b, done_args = list(1, 2), fail_args = list(3))
	om_task_timed(a, b, done_args = null, fail_args = list(3, 4))
	om_task_timed(a, b, done_args = some_list)
	om_task_timed(a, b, other_args = list(1, 2, 3, 4))
	om_task_timed(a,
		done_args = list(1, 2, 3))
	om_task_timed(0, 1, 2, 3, 4, 5, 6, 7, list(1, 2, 3))
	om_task_timed(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, list(f(1, 2), g[1, 2], 3))
	om_task_timed(0, 1, 2, 3, 4, list("a,b", "c"))
	om_task_timed(0, 1, 2, 3, 4, null)
	om_task_timed(0, 1, 2, 3, 4, built_elsewhere)
	om_task_timed(a, done_args = list(1, 2, 3)) // ALLOW(api): fixture keep on the line
	// ALLOW(api): fixture keep from above
	om_task_timed(a, done_args = list(1, 2, 3))
	// ALLOW(api)
	om_task_timed(a, done_args = list(1, 2, 3))
	// ALLOW(scheduler): wrong lint name
	om_task_timed(a, done_args = list(1, 2, 3))
	x = 1 // ALLOW(api): not a comment-only line
	om_task_timed(a, done_args = list(1, 2, 3))
	// om_task_timed(a, done_args = list(1, 2, 3))
	to_chat(a, "om_task_timed(a, done_args = list(1, 2, 3))")
	use_tool(a, done_args = list(1, 2, 3))
	use_tool(a, done_args = list(1, 2), fail_args = list(3))
	use_tool(a, done_args = list(1, 2))
	use_tool(a, 1, 2, 3, list(1, 2, 3))
	use_tool(a, done_args = list("x,y", "z"))
	use_tool(a, fail_args = shared)
	x.use_tool(a, done_args = list(1, 2, 3))
	// ---- vars_helpers ----
	om_set_var(a, "x", 1)
	om_set_var_then(a, "x", 1, PROC_REF(y))
	om_toggle_var(a, "x")
	cure_temporary_disability(a, 1)
	cure_temporary_sdisability(a, 1)
	om_set_var(a, "x", 1) om_toggle_var(a, "y")
	x.om_set_var(a, "x", 1)
	om_set_vars(a)
	// om_set_var(a)
	to_chat(a, "om_toggle_var")
#define om_set_var(x) 1
	# define om_toggle_var(x) 1
	om_set_var(a, "x", 1) // ALLOW(api): fixture keep
	// ---- vars_write ----
	vars["name"] = 1
	vars[x] = y
	vars[x] += y
	vars[x] == y
	a.vars[x] = y
	vars[x]=y
	vars[x] = y // ALLOW(api): framework plumbing
	// vars[x] = y
	// ---- timer_cooldown ----
	TIMER_COOLDOWN_START(a, "k", 5)
	S_TIMER_COOLDOWN_START(a, "k", 5)
	_TIMER_COOLDOWN_START(a, "k", 5)
	STIMER_COOLDOWN_START(a, "k", 5)
	XTIMER_COOLDOWN_START(a, "k", 5)
	TIMER_COOLDOWN_START (a, "k", 5)
	COOLDOWN_START(a, k, 5)
	// ---- accessor_macros ----
	BUCKLED(a)
	x.BUCKLED(a)
	/BUCKLED(a)
	BUCKLED (a)
	OM_REL_TARGET(a)
	OM_REL_TARGETS(a, b)
	OM_REL_SOURCES(a)
	OM_REL_SOURCEX(a)
	SLOT_ITEM(a, 1) + SLOT_LIST(a)
	BUCKLED_MOBS(a)
	MYBUCKLED(a)
	// ---- raw_world_bind ----
	vg_world_at(a)
	vg_world_watch_foo(a)
	vg_world_rate_watch(a)
	vg_world_step (a)
	vg_world_on_key(a)
	vg_world_clear(a)
	vg_world_cancel(a)
	vg_world_other(a)
	x/vg_world_at(a)
	// ---- string_keys ----
	om_world_publish(a, "x")
	om_world_on_key("k", PROC_REF(y))
	om_world_publish(1, 2)
	om_world_on_key(a, b, "c")
	om_world_publish(a, b) + "str"
	// ---- prompt_spec ----
	om_prompt(a, list())
	topic_prompt(a)
	om_prompt_sequence(a)
	om_prompt_chain(a)
	act_prompt(a)
	verb_prompt(a)
	client_prompt(a)
	rerun_prompt(a)
	surgery_prompt(a)
	cast_prompt(a)
	x.om_prompt(a)
	/mob/proc/om_prompt(a)
	om_ask(a, /datum/om/prompt/x)
	// ---- task_params_list ----
	om_task_start(type, actor, target, list("k" = v))
	om_task_start(type, actor, target, key = v)
	om_task_start(type, actor, target)
	om_task_start(a, b, c, d == e)
	om_task_start(a, b, c, d = e)
	om_task_start(a, b, c, d, e)
	om_task_start(a, b, c, f(x, y))
	// ---- reactor_api ----
	SSreactor.thing()
	on_react(a)
	react_every(a)
	react_sleep_violation(a)
	reactor_id = 5
	REACT_FOO
	REACT_FOO REACT_BAR
	react_everyone(a)
	// ---- raw_relation ----
	om_relation_of(a, b)
	x.om_relation_of(a, b)
	om_source_of(a)
	om_related(a)
	om_related_to(a)
	om_relation_ofx(a)
	om_related_things(a)
