/obj/machinery/e1/proc/five_before(mob/user, obj/item/I)
	user.drop_item()
	var/a = 1
	var/b = 2
	var/c = 3
	var/d = 4
	own_set(src, nameof(src.thing), I)
/obj/machinery/e1/proc/six_before(mob/user, obj/item/I)
	user.drop_item()
	var/a = 1
	var/b = 2
	var/c = 3
	var/d = 4
	var/e = 5
	own_set(src, nameof(src.thing), I)
/obj/machinery/e1/proc/two_after(mob/user, obj/item/I)
	own_set(src, nameof(src.thing), I)
	var/a = 1
	user.drop_item()
/obj/machinery/e1/proc/three_after(mob/user, obj/item/I)
	own_set(src, nameof(src.thing), I)
	var/a = 1
	var/b = 2
	user.drop_item()
/obj/machinery/e1/proc/header_stops_after(mob/user, obj/item/I)
	own_set(src, nameof(src.thing), I)
/obj/machinery/e1/proc/dropper(mob/user)
	user.drop_item()
/obj/machinery/e1/proc/commented(mob/user, obj/item/I)
	// user.drop_item()
	user.drop_item() // x
	own_put(src, nameof(src.thing), I)
/obj/machinery/e1/proc/commented2(mob/user, obj/item/I)
	// user.drop_item()
	own_put(src, nameof(src.thing), I)
/obj/machinery/e1/proc/string_form(obj/item/I)
	I.forceMove(src)
	own_set(src, "cell", I)
/obj/machinery/e1/proc/safe_nav(obj/item/I)
	I?.forceMove(src)
	own_add(src, nameof(src.parts), I)
/obj/machinery/e1/proc/named_holder(obj/item/I, obj/machinery/H)
	I.forceMove(H)
	own_set(H, nameof(H.cell), I)
/obj/machinery/e1/proc/wrong_holder(obj/item/I, obj/machinery/H)
	I.forceMove(H)
	own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/loc_assign(obj/item/I)
	I.loc = src
	own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/loc_assign_comment(obj/item/I)
	I.loc = src // moved
	own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/loc_not_at_end(obj/item/I)
	I.loc = src.other
	own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/extra_arg(mob/user, obj/item/I)
	user.remove_from_mob(I)
	own_set(src, nameof(src.cell), "extra", I)
/obj/machinery/e1/proc/nested_nameof(mob/user, obj/item/I)
	user.drop_from_inventory(I)
	own_set(src, nameof(src.cell), I, into = TRUE)
/obj/machinery/e1/proc/other_takes(mob/user, obj/item/I)
	user.drop_l_hand()
	user.drop_r_hand()
	user.drop_active_hand()
	own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/storage(obj/item/I)
	I.remove_from_storage(src)
	own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/not_a_call(obj/item/I)
	var/drop_item = 1
	own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/allowed(mob/user, obj/item/I)
	user.drop_item()
	own_set(src, nameof(src.cell), I) // ALLOW(sys_manual_transfer): fixture keeps this one
	// ALLOW(sys_manual_transfer): fixture keeps the next one
	own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/allowed_move(obj/item/I)
	I.forceMove(src)
	own_set(src, nameof(src.cell), I) // ALLOW(sys_manual_move_adopt): fixture keeps this one
/obj/machinery/e1/proc/in_string()
	var/s = "user.drop_item()"
	own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/own_in_comment(mob/user)
	user.drop_item()
	// own_set(src, nameof(src.cell), I)
/obj/machinery/e1/proc/two_owns(mob/user, obj/item/I)
	user.drop_item()
	own_set(src, nameof(src.cell), I)
	own_set(src, nameof(src.cell2), I)
/obj/machinery/e1/proc/own_remove_not_matched(mob/user, obj/item/I)
	user.drop_item()
	own_remove(src, nameof(src.cell), I)
	own_set(src, nameof(src.cell), I, a, b)
	own_set(src, nameof(src.cell))
	own_set(thing.other, nameof(src.cell), I.x)
