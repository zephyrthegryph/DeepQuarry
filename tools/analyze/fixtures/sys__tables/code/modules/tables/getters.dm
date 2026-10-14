GLOBAL_LIST_INIT(shared_names, list("a", "b"))
GLOBAL_LIST_EMPTY(shared_empty)
GLOBAL_LIST(plain_global)

/obj/thing/proc/names()
	var/static/list/table = list("a", "b", 3)
	return table

/obj/thing/proc/names_unused()
	var/static/list/table2 = list("a")
	return other

/obj/thing/proc/names_no_init()
	var/static/list/table3
	table3 = list("x")
	return table3

/obj/thing/proc/names_tab()
	var/static/list/table4 = list(1, 2)
	return table4 // trailing

/obj/thing/other_override()
	return GLOB.shared_names

/obj/thing/other_override2()
	return global.shared_empty

/obj/thing/other_override3()
	return GLOB.not_a_global_list

/obj/thing/other_override4(x)
	return GLOB.shared_names

/obj/thing/proc/explicit_proc()
	return GLOB.shared_names

/proc/free_proc()
	return GLOB.shared_names

/obj/thing/override5()
	// a leading comment line breaks the adjacency
	return GLOB.plain_global

/obj/thing/override6()
	var/x = 1
	return GLOB.plain_global

/obj/thing/proc/literal_list()
	return list("a", "b")

/obj/thing/proc/literal_list2()
	return list(1, 2, SOME_DEFINE, /obj/item/pen, null, TRUE)

/obj/thing/proc/literal_list3()
	return alist("a" = 1)

/obj/thing/proc/literal_empty()
	return list()

/obj/thing/proc/literal_var()
	return list(some_var, "x")

/obj/thing/proc/literal_call()
	return list(foo(1), "x")

/obj/thing/proc/literal_interp()
	return list("a[b]c")

/obj/thing/proc/literal_nested()
	return list(list(1, 2), list(3, 4))

/obj/thing/proc/literal_trailing()
	return list("a", "b").Copy()

/obj/thing/proc/literal_multiline()
	return list(
		"a",
		"b", // comment
		"c"
	)

/obj/thing/proc/literal_continuation()
	return list("a", \
		"b")

/obj/thing/proc/unbalanced()
	return list("a",

/obj/thing/proc/switch_table(x)
	switch(x)
		if(1)
			return list("a")
		if(2)
			return list("b")
	return null

/obj/thing/proc/switch_mixed(x)
	if(x)
		return list("a")
	var/list/L = list()
	L += x
	return L

/obj/thing/proc/value_returns(x)
	if(x)
		return TRUE
	if(y)
		return null
	return list("a")

/obj/thing/proc/value_returns2(x)
	if(x)
		return 5
	return list("a")

/obj/thing/proc/seeded()
	. = list("a", "b")
	. += "c"
	return .

/obj/thing/proc/seeded2()
	. = list("a", "b")
	return .

/obj/thing/proc/seeded3()
	. = list("a", "b")
	.[1] = "c"

/obj/thing/proc/seeded4()
	. = list("a", "b")
	. -= "a"

/obj/thing/proc/seeded5()
	. = list("a", "b")
	..Add("x")

/obj/thing/proc/paren_return(x)
	if(foo(x)) return list("a")
	return list("b")

/obj/thing/proc/paren_return2(x)
	if(foo(x)) return list(bar)
	return list("b")

/obj/thing/proc/local_const()
	var/list/L = list("a", "b")
	return 3

/obj/thing/proc/local_const_returned()
	var/list/L = list("a", "b")
	return L

/obj/thing/proc/local_const_passed()
	var/list/L = list("a", "b")
	use_it(L)

/obj/thing/proc/local_const_passed2()
	var/list/L = list("a", "b")
	use_it(1, L, 2)

/obj/thing/proc/local_const_assigned()
	var/list/L = list("a", "b")
	M = L

/obj/thing/proc/local_const_written()
	var/list/L = list("a", "b")
	L += "c"

/obj/thing/proc/local_const_written2()
	var/list/L = list("a", "b")
	L[1] = "z"

/obj/thing/proc/local_const_written3()
	var/list/L = list("a", "b")
	L.Add("z")

/obj/thing/proc/local_const_written4()
	var/list/L = list("a", "b")
	L.len = 5

/obj/thing/proc/local_const_written5()
	var/list/L = list("a", "b")
	L = list("c")

/obj/thing/proc/local_const_read()
	var/list/L = list("a", "b")
	for(var/x in L)
		do_it(x)

/obj/thing/proc/local_var_init()
	var/list/L = list(some_var)
	return 1

/obj/thing/proc/local_empty()
	var/list/L = list()
	return 1

/obj/thing/proc/local_tail()
	var/list/L = list("a") + other
	return 1

/obj/thing/proc/block_comment()
	/* var/list/L = list("a", "b") */
	return 1

/obj/thing/proc/block_comment2()
	/*
	var/list/L = list("a", "b")
	return list("a")
	*/
	return 1

/obj/thing/proc/block_comment3()
	var/s = "not /* a comment"
	var/list/L = list("a", "b")
	return 1

/obj/thing/proc/block_comment4()
	var/list/L = list("a") /* inline */ // line comment /* nested start
	return 1

/obj/thing/proc/block_comment5()
	var/s = "string with // slashes /* and a start"
	var/list/L = list("b")
	return 1 /* trailing */

/obj/thing/proc/allowed_getter()
	// ALLOW(sys_static_getter): shared table by design
	var/static/list/table5 = list("a", "b")
	return table5

/obj/thing/proc/allowed_alloc()
	return list("a") // ALLOW(sys_const_list_alloc): fresh list per caller

/obj/thing/proc/with_annotation()
	var/list/L = list(1, 2) // ALLOW(instance_list): not worth it, per-subtype table
	return 1

/obj/thing/proc/with_annotation2()
	// ALLOW(instance_list): Not Worth It at all
	return 1

/obj/thing/proc/with_annotation3()
	// ALLOW(instance_list): worth it
	return 1

// ALLOW(instance_list): not worth it (outside any proc)
/obj/thing/var/foo = 1

/obj/thing/proc/comment_header()
// a comment at column zero
	return list("a")

//obj/thing/proc/looks_like_a_header()
	return list("a")
