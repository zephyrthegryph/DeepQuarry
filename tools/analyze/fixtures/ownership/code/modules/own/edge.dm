// Scope and shape edge cases for proc_scopes and the per-line checks.
/obj/other/proc/rosterless_more(mob/M, obj/item/widget/W)
	rosterless.Add(src)
	rosterless.Insert(1, M)
	rosterless.Add(5)
	LAZYADD(rosterless, M)
	LAZYSET(rosterless, M, 1)
	LAZYOR(rosterless, W)
	LAZYDISTINCTADD(rosterless, 7)
	rosterless[M] = 1
	rosterless[1] = 5
	rosterless[src] = TRUE
	rosterless -= M
	rosterless.Cut()
	LAZYINITLIST(rosterless)

/obj/holder/proc/stray_lines()
	held = null
"stray string line"
	occupant = null
'stray icon line'
	stuff += src

#define SOME_DEFINE 1
	held = null

/obj/holder/proc/after_define()
	held = null
GLOBAL_LIST_EMPTY(some_list)
	occupant = null

/obj/holder/proc/default_args(obj/item/a = null, list/b = list(), c)
	a = null
	b += src
	c = 5
	held = a

/obj/holder/proc/nested(mob/M)
	if(M)
		for(var/obj/item/held in stuff)
			held = null
		held = null
	var/obj/item/stuff = null
	stuff = M
	var/c = held = null

/obj/holder/proc/misc_ops()
	held |= src
	held &= src
	held ^= src
	held -= src
	held <<= 1
	held >>= 1
	held *= 2
	count -= 1
	held++
	--held
	if(held = src)
		return
	while(held = src)
		break
	held=null
	held   =   null
	src.held=null
	src . held = null
	src.held . x = null

/obj/holder/proc/dotted_chains()
	src.occupant.client = null
	src?.held = null
	usr?.held = null
	M?.occupant?.held = null
	src.stuff.Add(src)
	src.stuff[1] = src
	QDEL_NULL(src.held)
	LAZYADD(src.stuff, src)
	LAZYADD(H.stuff, src)
	QDEL_LIST(H?.stuff)

/obj/holder/proc/assoc_and_args()
	var/list/l = list("a" = 1, held = src)
	foo(held = src)
	foo(1, held = src)
	foo(a, held = src)
	return list(held = src)
	var/y = x ? held = 1 : 2
	var/z = [held = 1]

/obj/holder/proc
	one = 1

/obj/holder/proc/one_liner() held = null

/obj/holder/proc/trailing_proc_with_comment(a) // held = null
	held = null // trailing
	stuff += src /* c */

/obj/holder/proc/multi_param(a,
	b)
	held = null
