// one line per family, then edge cases
DECLARE_INTERACTIONS(/obj/x, list())
	EXTEND_INTERACTIONS(/obj/x, list())
	INTERACT_HAND (a)
	dq_interaction_from_spec(spec)
/obj/x/proc/declare_interactions()
	return /declare_interactions(
/datum/interaction/machine_hand/foo
/datum/interaction/machine_item/foo
/datum/interaction/machine_alt/foo
/datum/interaction/machine_other/foo
 /datum/interaction/machine_hand/indented
/obj/machinery/thing/crowbar_act(mob/user, obj/item/I)
/obj/machinery/thing/analyzer_act (mob/user, obj/item/I)
/obj/machinery/thing/proc/crowbar_act(mob/user)
/obj/machinery/thing/hammer_act(mob/user)
	DECLARE_EMAG(/obj/x, PROC_REF(on_emag), "msg")
	DECLARE_EMAG_REPEATABLE(/obj/x, PROC_REF(on_emag))
/obj/x/emag_act(a)
	x.emag_act(1)
	needs = REQ_ACCESS
	REQ_FIELD(x)
	REQ_
	xREQ_FOO bar
	APPEARANCE_TEMPLATE(T, "x")
	APPEARANCE_LEVEL (a)
	APPEARANCE_NONE(1)
	DECLARE_APPEARANCE_PROC(/x, PROC_REF(y), list())
/obj/x/update_icon()
/obj/x/update_icon (a)
/obj/x/proc/update_icon()
	update_icon()
	update_icon( )
	x.update_icon()
	/update_icon()
	queue_icon_update()
	my_update_icon()
	update_icon(1)
	DECLARE_UI(/obj/x, "Iface")
	UI_ACT(/obj/x, "a", PROC_REF(b))
	UI_DATA(/obj/x, list())
	UI_ARG_NUM("a")
	UI_SUBACT(/obj/x, "a")
	act_ask(a)
	om_ask (a, b)
	om_ask_sequence(a)
	topic_ask(a)
	x.rerun_ask_on(a)
	EXPIRY_SET(a, b)
	OM_FIELD(/obj/x, y, 1)
	OM_FLAG_FIELD_X(/obj/x, y)
	OM_DERIVE_FIELD(a)
	OM_FIELD_SETTER(a)
	DECLARE_VERB(/obj/x, /obj/x/verb/y)
	DECLARE_VERB_IF(a, b)
	DECLARE_PERIODIC_WHILE(a, b, "c")
	DECLARE_REPEAT(a, b, c, "d")
/obj/x/machine_step(dt)
	x.machine_step (dt)
	add_fingerprint(user)
	user.add_fingerprint(user)
	add_fingerprint (user)
	"add_fingerprint(user)"
	var/s = "http://example.com" + add_fingerprint(user)
	// add_fingerprint(user) in a comment
	add_fingerprint(user) // ALLOW(sys_manual_fingerprint): fixture keeps this one
	// ALLOW(sys_manual_fingerprint): fixture keeps the next one
	add_fingerprint(user)
	add_fingerprint(a) // ALLOW(sys_manual_fingerprint)

   	
	DECLARE_VERB(/obj/x, /obj/x/verb/z) add_fingerprint(user) update_icon()
	REQ_A REQ_B update_icon() // ALLOW(sys_old_requirement): fixture keeps one rule only
