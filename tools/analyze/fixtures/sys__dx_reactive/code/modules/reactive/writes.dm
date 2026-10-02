/obj/machinery/writer/should_run()
	var/list/L = list()
	var/n = 0
	L += "x"
	L[1] = 2
	L.Add(3)
	L.Cut(1)
	n++
	n += 1
	n = 5
	++n
	x = 5
	src.y = 3
	src.y++
	y--
	--y
	z[1] = 2
	src[1] = 2
	L[1]++
	a.b = 3
	a.b += 3
	a?.b = 3
	. = 1
	.[1] = 2
	. += 3
	look.x = 1
	data["a"] = 1
	if(n == 3)
		return
	if(n != 3 && n <= 3 || n >= 3)
		return
	n <<= 1
	n >>= 1
	n |= 1
	n &= 1
	n ^= 1
	n -= 1
	n *= 2
	n /= 2
	n %= 2
	n = n == 2
	foo(a = 1, b = 2)
	for(var/i = 1, i <= 3, i++)
		n = i
	for(k = 1, k < 3, k++)
		return
	for (var/m in L) q = 1
	var/q = 5
	var/w = foo.bar
	if(n) y = 1
	else if(n) y = 2
	while(n) y = 3
	if(n) {y = 4}
	a = 1; b = 2
	var/v = 1; zz = 2
	return n

/obj/machinery/writer/hidden_verbs()
	holder.verbs.Remove(x)
	user.Add(1)
	L.Add(1)
	data.Add(1)
	look.set_icon("x")
	src.set_x(1)
	set_foo(1)
	..()
	var/list/M = list()
	M.Add(1)
	M.Swap(1, 2)
	M.Splice(1, 2)
	M.Insert(1, 2)
	M.RemoveAll(list())
	M.Remove(1)
	cell.Cut()
	cell?.Cut()
	src.cell.Cut()
	src.forceMove(null)
	src?.qdel()
	x.add_fingerprint(usr)
	x?.update_icon()
	x.set_light(1)
	var/obj/O = x
	O.set_thing(2)
	return M

/obj/machinery/writer/tgui_data(mob/user)
	changed(src)
	cap_set(src, 1)
	timed_cancel(src, "x")
	own_take(src, "x")
	own_take_all(src, "x")
	rel_clear(src, "x")
	om_set(src, "x", 1)
	qdel(src)
	forceMove(null)
	set_light(1)
	update_icon()
	add_fingerprint(user)
	to_chat(user, "hi")
	playsound(src, 'x.ogg', 50)
	own_transfer(src, "a", user)
	own_move(src, "a", user)
	rel_set(src, "a", user)
	rel_add(src, "a", user)
	rel_remove(src, "a", user)
	own_set(src, "a", user)
	own_add(src, "a", user)
	own_put(src, "a", user)
	own_remove(src, "a", user)
	own_clear(src, "a")
	own_take_member(src, "a", user)
	timed_set(src, "a", 1)
	x.own_set(1)
	obj.changed()
	changed_thing(1)
	return TRUE

/obj/machinery/writer/proc/not_reactive()
	x = 5
	changed(src)

/datum/capability/writer/draw(atom/holder, datum/look/look)
	holder.x = 1
	look.state("x")
	var/q = holder.y
	q = 2
	"[to_chat(holder, "x")]"
	"to_chat(holder, x)"
	// changed(holder)
	return

/datum/capability/writer/gate(atom/holder, mob/user, datum/interaction/entry)
	user.stat = 1 // ALLOW(sys_dx_reactive_write): fixture keeps this one
	// ALLOW(sys_dx_reactive_write): fixture keeps the next one
	user.stat = 2
	user.stat = 3
	return
