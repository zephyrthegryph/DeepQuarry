// Writes for the raw_write check.
/obj/holder/proc/writes(obj/item/arg_item, mob/M)
	held = arg_item
	src.held = arg_item
	occupant = null
	stuff += arg_item
	stuff -= arg_item
	stuff.Add(arg_item)
	stuff.Remove(arg_item)
	stuff.Insert(1, arg_item)
	stuff[1] = arg_item
	stuff.Cut()
	LAZYADD(stuff, arg_item)
	LAZYREMOVE(stuff, arg_item)
	QDEL_NULL(held)
	QDEL_LIST(stuff)
	UNSETEMPTY(stuff)
	count = 5
	count += 2
	untyped_thing = 1
	untyped_thing = new /obj/item/widget()
	untyped_thing = new /image('icon.dmi')
	untyped_thing = new
	om_plain = 2
	om_item = null
	om_view = null
	abs_held = null
	cached = null
	not_declared = null
	rosterless = src

/obj/holder/proc/compares(obj/item/arg_item)
	if(held == arg_item)
		return TRUE
	if(held != arg_item && occupant <= 3)
		return FALSE
	if(count >= 2 || stuff[1] == arg_item)
		return TRUE
	var/same = (held == occupant)
	return same

/obj/holder/proc/shadows(obj/item/held, list/stuff)
	held = null
	stuff += src
	stuff.Add(src)
	LAZYADD(stuff, src)
	QDEL_NULL(held)

/obj/holder/proc/locals()
	var/obj/item/held = new /obj/item/widget()
	held = null
	var/list/obj/stuff = list()
	stuff += src
	var/occupant
	occupant = 5
	var/obj/holder/H = src
	H.held = null
	var/count_local = 0
	count_local = 1
	var/list/L = list(/obj/item/held = 1)
	var/x = list(held = 1, occupant = 2)
	L[held] = 2

/obj/holder/proc/typed_receivers(obj/holder/H, M, X)
	H.held = null
	H.stuff += src
	H?.occupant = null
	M.unique_ent = null
	M.label = null
	X.held = null
	usr.held = null
	H.a.held = null
	M.count = 3
	M.rosterless += src
	M.nosuch_anywhere = null
	H.mixed += 1

/obj/holder/proc/inferred()
	own_add(src, nameof(roster), src)
	roster += src
	roster |= new /obj/item/widget()
	roster += 5
	roster[1] = null

/obj/other/proc/rosterless_writes(mob/M)
	var/obj/item/widget/W = new()
	rosterless += src
	rosterless += M
	rosterless += W
	rosterless |= new /obj/item/widget()
	rosterless += 5
	rosterless += list(1, 2)
	rosterless += EXPIRY_AT(src, 5)
	rosterless += new
	rosterless += image(src)

/obj/holder/proc/skipped_names()
	loc = null
	contents += src
	overlays += src
	vis_contents += src
	vars["held"] = src
	screen += src
	src = null

/obj/holder/proc/allowed_writes()
	held = null // ALLOW(ownership): the fixture keeps this raw write on purpose
	// ALLOW(ownership): the comment line above keeps the next write
	occupant = null
	// ALLOW(ownership)
	stuff += src
	stuff += src // ALLOW(other): a different lint's annotation keeps nothing here
	held = new /obj/item/widget( // ALLOW(ownership, scheduler): both names, one reason
		src)

/obj/holder/proc/text_only()
	// held = null in a comment
	var/s = "held = null"
	var/t = "x [held = 5] y"
	/* stuff += src
	held = null */
	var/u = 'held = null'

/obj/holder/proc/multi_line()
	held = new /obj/item/widget(
		src)
	stuff += list(
		src)

/obj/holder/proc/declared_shared()
	shared_item = null
	shared_item += src
	shared_thing = null
	owned_decl = null
	rel_decl = null

/obj/holder/sub/proc/subtype_writes()
	held = null
	subvar = null
	src.subvar = null

/obj/holder/verb/verb_write()
	held = null

/obj/holder/Initialize()
	held = new /obj/item/widget()
	return ..()

/proc/global_proc(obj/holder/H)
	H.held = null
	var/obj/holder/G
	G.held = null
	held = null
