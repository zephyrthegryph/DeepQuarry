// untyped fixture: a call's result is a value only when the proc it resolves to returns only numbers or text.

/datum/thing

/datum/a/proc/size()
	return 5

/datum/b/proc/size()
	return new /datum/thing

/proc/lookup()
	return 7

/datum/c/proc/lookup()
	return new /datum/thing

/datum/c
	var/unscoped_c
	var/global_c

/datum/c/proc/use_unscoped()
	unscoped_c = lookup()

/datum/c/proc/use_global()
	global_c = global.lookup()

/proc/mixed(flag)
	if(flag)
		return 1
	return new /datum/thing

/proc/fact(n)
	if(n <= 1)
		return 1
	return n * fact(n - 1)

/proc/ping(n)
	if(n <= 0)
		return 0
	return pong(n - 1)

/proc/pong(n)
	return ping(n - 1) + 1

/proc/dotted(flag)
	. = 0
	if(flag)
		. = new /datum/thing

/proc/dotted_number(flag)
	. = 0
	if(flag)
		. += 2

/proc/via_local(flag)
	var/n = 3
	if(flag)
		n = new /datum/thing
	return n

/proc/via_number_local()
	var/n = 3
	n += 2
	return n

/proc/via_call()
	return mixed(1)

/proc/via_value_call()
	return fact(4) + 1

/proc/via_ternary(flag)
	return flag ? 1 : "text"

/proc/via_or(a) // every call passes a number: the parameter is a value
	return a || 2

/datum/base/proc/kind()
	return 1

/datum/base/derived/kind()
	return new /datum/thing

/datum/holder
	var/a_size
	var/b_size
	var/from_mixed
	var/from_fact
	var/from_ping
	var/from_dotted
	var/from_dotted_number
	var/from_local
	var/from_number_local
	var/from_call
	var/from_value_call
	var/from_ternary
	var/from_or
	var/from_override
	var/from_untyped
	var/from_builtin

/datum/holder/proc/fill(datum/a/A, datum/b/B, datum/base/D, U)
	a_size = A.size()
	b_size = B.size()
	from_mixed = mixed(1)
	from_fact = fact(3)
	from_ping = ping(3)
	from_dotted = dotted(1)
	from_dotted_number = dotted_number(1)
	from_local = via_local(1)
	from_number_local = via_number_local()
	from_call = via_call()
	from_value_call = via_value_call()
	from_ternary = via_ternary(1)
	from_or = via_or(1)
	from_override = D.kind()
	from_untyped = U.size()
	from_builtin = rand(1, 5)

// --- var reads: world.time, and a var that only ever holds values
/proc/world_clock()
	return world.time

/datum/clock
	var/manual
	var/shared

/datum/clock/proc/step(seconds)
	manual = seconds * 10
	manual += 2

/datum/clock/proc/clock_now()
	return isnull(manual) ? world.time : manual

/datum/clock/proc/clock_shared()
	return shared

/datum/clock/proc/store_shared(datum/thing/T)
	shared = T

/datum/clock/proc/clock_shared_viaconst()
	return shared

/datum/reader
	var/from_world
	var/from_clock_var
	var/from_clock_datum_var
	var/from_local_value
	var/from_param_local

/datum/reader/proc/read(datum/clock/C, param)
	from_world = world_clock()
	from_clock_var = C.clock_now()
	from_clock_datum_var = C.clock_shared()
	var/made = C.clock_now()
	from_local_value = made
	var/untouched = param
	from_param_local = untouched

// --- argument passthrough: a parameter is a value when every call passes one
/proc/echo(n)
	return n

/proc/echo_user()
	return echo(3) + echo("a")

/proc/echo_mixed(n)
	return n

/proc/echo_mixed_a()
	return echo_mixed(4)

/proc/echo_mixed_b(datum/thing/T)
	return echo_mixed(T)

/proc/echo_named(n)
	return n

/proc/echo_named_user()
	return echo_named(n = 5)

/proc/echo_ref(n)
	return n

/proc/echo_ref_user()
	var/handler = "echo_ref"
	return echo_ref(6)

/datum/passer
	var/from_echo
	var/from_mixed
	var/from_named
	var/from_ref

/datum/passer/proc/pass()
	from_echo = echo_user()
	from_mixed = echo_mixed_a()
	from_named = echo_named_user()
	from_ref = echo_ref_user()
