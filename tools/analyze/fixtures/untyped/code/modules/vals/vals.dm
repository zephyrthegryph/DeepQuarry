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
	call(src, handler)()
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

// --- locals: a local holds what was assigned to it, so a call result passed through locals is still judged
/datum/localer
	var/via_one_local
	var/via_local_chain
	var/via_number_local
	var/via_value_call_local

/datum/localer/proc/hold()
	var/one = mixed(1)
	via_one_local = one
	var/first = mixed(1)
	var/second = first
	var/third = second
	via_local_chain = third
	var/count = 4
	count += 2
	via_number_local = count
	var/size = fact(2)
	via_value_call_local = size

// --- an external function's result is text or null, never a reference; call()() is a dynamic call and stays unknown
/proc/ffi_text(f)
	return call_ext(f)(1)

/proc/ffi_dynamic(o, p)
	return call(o, p)()

/datum/ffier
	var/from_ffi
	var/from_ffi_dynamic

/datum/ffier/proc/use_ffi()
	from_ffi = ffi_text("x")
	from_ffi_dynamic = ffi_dynamic(src, "y")

// --- builtins that hand back text or a number
/datum/reffer
	var/from_ref
	var/from_url
	var/from_sort

/datum/reffer/proc/use_builtins()
	from_ref = ref(src)
	from_url = url_encode("a b")
	from_sort = sorttext("a", "b")

// --- a var is the type that declares it and its name: a write through a typed receiver reaches that var only; a write through an untyped one reaches every var of the name
/datum/keyed_a
	var/amount = 0

/datum/keyed_a/proc/get()
	return amount

/datum/keyed_b
	var/amount = 0

/datum/keyed_b/proc/get()
	return amount

/datum/keyed_b/proc/spoil(datum/keyed_b/other)
	other.amount = new /datum/thing

/datum/keyed_c
	var/from_a
	var/from_b

/datum/keyed_c/proc/read(datum/keyed_a/A, datum/keyed_b/B)
	from_a = A.get()
	from_b = B.get()

/datum/keyed_d
	var/level = 0

/datum/keyed_d/proc/get()
	return level

/datum/keyed_e
	var/level = 0

/datum/keyed_e/proc/get()
	return level

/proc/spoil_blind(thing)
	thing.level = new /datum/thing

/datum/keyed_f
	var/from_d
	var/from_e

/datum/keyed_f/proc/read(datum/keyed_d/D, datum/keyed_e/E)
	from_d = D.get()
	from_e = E.get()

// builtin value forms: a literal pick, a list method with no definition in the tree, a number/flag/string config read.
/datum/controller/configuration
	var/entries = 0
	var/list/entries_by_type = list()

/datum/controller/configuration/proc/Get(entry_type)
	var/datum/config_entry/E = entries_by_type[entry_type]
	return E.config_entry_value

/datum/config_entry
	var/config_entry_value

/datum/config_entry/proc/ValidateAndSet(str_val)
	return TRUE

/datum/config_entry/number

/datum/config_entry/number/ValidateAndSet(str_val)
	config_entry_value = text2num(str_val)
	return TRUE

/datum/config_entry/number/limit
/datum/config_entry/number/overridden
/datum/config_entry/number/benign
/datum/config_entry/number/benign/ValidateAndSet(str_val)
	. = ..()
	if(.)
		note_set()

/datum/config_entry/number/benign/proc/note_set()
	return 1


/datum/config_entry/number/overridden/ValidateAndSet(str_val)
	config_entry_value = new /datum/thing
	return TRUE

/datum/config_entry/other
/datum/config_entry/other/thing

var/datum/controller/configuration/config = new

/proc/pick_literals()
	return pick("small", "medium", 3)

/proc/pick_weighted()
	return pickweight(list("a" = 1, "b" = 2))

/proc/pick_mixed()
	return pick("small", new /datum/thing)

/proc/pick_list(list/L)
	return pick(L)

/proc/index_of(list/L)
	return L.Find("x")

/proc/joined_of(list/L)
	return L.Join(", ")

/datum/builtin_values
	var/picked_literals
	var/picked_weighted
	var/picked_mixed
	var/picked_list
	var/found_index
	var/joined
	var/config_number
	var/config_overridden
	var/config_benign
	var/from_regex
	var/from_regex_find
	var/config_other
	var/config_unknown

/datum/builtin_values/proc/use(list/L)
	picked_literals = pick_literals()
	picked_weighted = pick_weighted()
	picked_mixed = pick_mixed()
	picked_list = pick_list(L)
	found_index = index_of(L)
	joined = joined_of(L)
	config_number = global.config.Get(/datum/config_entry/number/limit)
	config_overridden = global.config.Get(/datum/config_entry/number/overridden)
	config_benign = global.config.Get(/datum/config_entry/number/benign)
	var/regex/R = regex("a")
	from_regex = R.Replace("abc", "b")
	from_regex_find = R.Find("abc")
	config_other = global.config.Get(/datum/config_entry/other/thing)
	config_unknown = global.config.Get(config_number)

// A declared `as text` / `as num` return, an `as text` parameter, and a finding listing every assigning line.
/datum/declared
	var/declared_ret
	var/declared_num
	var/echoed
	var/echoed_bad
	var/two_writes
	var/interpolated

/datum/declared/proc/id_text()
	return "[type]"

/datum/declared/proc/declared_text() as text
	return mixed(1)

/datum/declared/proc/declared_number() as num
	return mixed(0)

/datum/declared/proc/declared_thing() as /datum/thing
	return mixed(1)

/proc/echo_text(table as text)
	return table

/proc/echo_bad(table as text)
	return table

/proc/feed_bad()
	return echo_bad(new /datum/thing)

/datum/declared/proc/use()
	declared_ret = declared_text()
	declared_num = declared_number()
	echoed = echo_text("x")
	echoed_bad = echo_bad("x")
	two_writes = mixed(1)
	interpolated = id_text()

/datum/declared/proc/use_again(flag)
	two_writes = mixed(flag)
	two_writes = declared_thing()
