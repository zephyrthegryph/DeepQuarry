/obj/machine/gizmo/tgui_id = "Gizmo"

/obj/machine/pick_helper(p)
	return ui_text(p)

/obj/machine/gizmo/pick_helper(p)
	world << p

/obj/machine/gizmo/proc/act_spin(mob/user, rate, mode, target, camel_case, hyphen_key, ghost)
	rate = ui_number(rate, 1, 5)
	if(isnull(mode))
		return
	if(mode == "fast" || "slow" == mode)
		return
	if(target != null)
		return
	return camel_case + hyphen_key

// ALLOW(ui_actions): internal flag kept on purpose
/obj/machine/gizmo/proc/act_kept_above(mob/user, secret)
	return secret

/obj/machine/gizmo/proc/act_kept_same(mob/user, secret) // ALLOW(ui_actions): same-line keep
	return secret

/obj/machine/gizmo/proc/act_open_ended(mob/user, anything_goes)
	return anything_goes

/obj/machine/gizmo/proc/act_checks(mob/user, a, b, c, d, e, f, g, h, i, j, k)
	if(!a)
		return
	if(a)
		return
	b = ui_text(b)
	b = trim(b)
	var/x = ui_bool(c)
	switch(d)
		if(1)
			return
	if(islist(e))
		return
	if(!!f)
		return
	if(!g || g == 3)
		return
	if(h in list("a"))
		return
	if(!i in list("a"))
		return
	var/obj/j/marker = null
	to_chat(user, "[k]")

/obj/machine/gizmo/proc/act_numbers(mob/user, n1, n2, n3, n4, n5, n6, n7, n8)
	if(n1 == -1)
		return
	if(n2 == 2.5)
		return
	if(3 == n3)
		return
	if("x" == n4)
		return
	if(n5 == TRUE)
		return
	if(n6 == MODE_A)
		return
	if(n7 == foo)
		return
	if(n8 == ModeB)
		return

/obj/machine/gizmo/proc/act_helpers(mob/user, v1, v2, v3, v4, v5, v6, v7, v8, v9)
	pick_helper(v1)
	global_check(v2)
	src.pick_helper(v3)
	user?.thing(v4)
	ui_number(5, v5)
	ui_number(min = v6)
	named_helper(value = v7)
	one_param(1, v8)
	rec(v9)

/proc/global_check(x)
	return ui_text(x)

/obj/machine/gizmo/proc/named_helper(value)
	return ui_bool(value)

/obj/machine/gizmo/proc/one_param(a)
	return ui_bool(a)

/obj/machine/gizmo/proc/rec(r)
	rec(r)

/obj/machine/gizmo/proc/act_chain3(mob/user, v)
	h1(v)

/obj/machine/gizmo/proc/h1(p1)
	h2(p1)

/obj/machine/gizmo/proc/h2(p2)
	return ui_number(p2)

/obj/machine/gizmo/proc/act_chain4(mob/user, w)
	g1(w)

/obj/machine/gizmo/proc/g1(p1)
	g2(p1)

/obj/machine/gizmo/proc/g2(p2)
	g3(p2)

/obj/machine/gizmo/proc/g3(p3)
	g4(p3)

/obj/machine/gizmo/proc/g4(p4)
	return ui_number(p4)

/obj/machine/gizmo/proc/act_use_allowed(mob/user, q, r)
	// ALLOW(ui_actions): checked by the caller
	world << q
	world << r // ALLOW(ui_actions): same-line use keep

/obj/machine/gizmo/proc/act_use_allowed_elsewhere(mob/user, s)
	world << s
	// ALLOW(ui_actions): too far from the first use
	return TRUE

// A subtype on its own interface overrides an act_ proc.
/obj/machine/gizmo/big
	tgui_id = "GizmoBig"
/obj/machine/gizmo/big/proc/act_spin(mob/user, rate)
	return ui_number(rate)

// No tgui_id anywhere in the lineage or below: nothing reaches it.
/obj/orphan/proc/act_orphan(mob/user, zzz)
	return zzz

// Two hosts share one interface; only one answers each action.
/obj/shared_a
	tgui_id = "Shared"
/obj/shared_b
	tgui_id = "Shared"
/obj/shared_a/proc/act_only_a(mob/user, alpha)
	alpha = ui_number(alpha)
/obj/shared_b/proc/act_only_b(mob/user, beta)
	beta = ui_number(beta)

// A legacy DECLARE_UI host: skipped until it migrates.
/obj/legacy_host
	tgui_id = "Legacy"
DECLARE_UI(/obj/legacy_host, UI_TITLE("Legacy"))
/obj/legacy_host/proc/act_legacy_thing(mob/user, legacy_param)
	return legacy_param
