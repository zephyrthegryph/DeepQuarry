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

/proc/via_or(a)
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
