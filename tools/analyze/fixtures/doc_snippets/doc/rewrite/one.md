# One

```dm fragment
/obj/machinery/power/apc/capabilities()
	. = ..()
	. += cap_cover(open_tool = TOOL_CROWBAR)
	. += wall_machine(board = /obj/item/circuitboard/apc)
	. += lock(access = list(ACCESS_ENGINE))
```

  ```dm
  /obj/machinery/pump/proc/act_set_pressure(mob/user, pressure)
  	pressure = ui_number(pressure, 0, 100)
  	look.gauge("x", level = 1)
  	look.shine("y")
  	helper_of_block(pressure)
  	set_target_pressure(pressure)
  	pump_fast()
  	pump_missing()
  /obj/machinery/pump/proc/helper_of_block(value)
  	return round(value)
  ```

```dm before
/obj/machinery/pump/proc/ui_act(action, params)
	nonexistent_old_thing(params)
```

```dm
// a complete block with no proc head: any type's proc counts
set_target_pressure(CAP_LIMIT)
lock(1)
beat()
unknown_free_call()
```

```dm fragment
/obj/item/proc/use(mob/user)
	attack_self(user)
	examine(user)
	emote("x")
	lock(user)
	user.emote("hi")
	user?.beat()
	user:lock(1)
	list_of[1].thing(2)
	list_of[1].beat()
	x.missing_member(1)
	x.Add(1)
	x.Copy()
	var/t = new type_var(args)
	var/u = new /obj/item(args)
	call_it(MACRO_CALL(user))
	spawn(0)
		sleep(1)
	for(var/i in 1 to 3)
		if(prob(5))
			world.log << "[unknown_in_string(1)] text"
			world.log << "plain unknown_in_text(2)"
	// commented_out(3)
	/* block_commented(4) */
	@"raw_string(5)"
```

```dm fragment
/proc/own_global_helper(a)
	return a

/datum/thing/proc/own_member()
	return

/datum/thing/proc/run()
	own_global_helper(1)
	own_member()
	beat()
	not_in_lineage_of_thing()
	pump_fast()
#define LOCAL_MACRO(x) x
	LOCAL_MACRO(1)
	local_macro_lower(1)
```

```dm fragment
/obj/machinery/pump/proc/fast_second()
	pump_fast()
	pump_verb()
	set_target_pressure(1)
	examine(1)
	emote(1)
	override()
	beat()
```

```dm somethingelse
/obj/item/proc/other_tag()
	tagged_unknown()
```

```dm fragment
	// ALLOW(doc_snippets): fixture keep, line below
	kept_unknown(1)
	same_line_unknown(1) // ALLOW(doc_snippets): same line keep
	still_flagged(1)
	// ALLOW(other): wrong lint name
	wrong_name_flagged(1)
	// ALLOW(doc_snippets)
	no_reason_flagged(1)
```
