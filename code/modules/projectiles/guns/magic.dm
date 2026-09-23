/*
 * "Magic" "Guns"
 */

/// Real-time period of one recharge tick (was the SSobj subsystem's 2 SECONDS wait, before its retirement).
#define MAGIC_GUN_RECHARGE_PERIOD 2 SECONDS

/obj/item/gun/magic
	name = "staff of nothing"
	desc = "This staff is boring to watch because even though it came first you've seen everything it can do in other staves for years."
	icon = 'icons/obj/wizard.dmi'
	icon_state = "staffofnothing"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_magic.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_magic.dmi',
		)
	fire_sound = 'sound/weapons/emitter.ogg'
	w_class = ITEMSIZE_HUGE
	projectile_type = null
	var/checks_antimagic = TRUE
	var/max_charges = 6
	var/charges = 0
	var/recharge_rate = 4
	var/can_charge = TRUE

	/// REACT_AT token for the next recharge tick; null when not recharging.
	var/tmp/recharge_timer

/obj/item/gun/magic/consume_next_projectile()
	if(checks_antimagic && locate(/obj/item/nullrod) in usr) return null
	if(!ispath(projectile_type)) return null
	if(charges <= 0) return null

	charges -= 1
	schedule_recharge()

	return new projectile_type(src)

/obj/item/gun/magic/Initialize(mapload)
	. = ..()
	charges = max_charges
	if(can_charge)
		schedule_recharge()

/obj/item/gun/magic/on_react(reason, source, source_kind)
	. = ..()
	if(!(reason & REACT_REASON_TIMER) || source != recharge_timer)
		return
	recharge_timer = null
	if(can_charge && charges < max_charges)
		charges++
	schedule_recharge()

// Arms the next recharge tick, or cancels the timer once full / not charging.
/obj/item/gun/magic/proc/schedule_recharge()
	if(!can_charge || charges >= max_charges)
		recharge_timer = REACT_REARM(src, recharge_timer, null)
		return
	recharge_timer = REACT_REARM(src, recharge_timer, world.time + recharge_rate * MAGIC_GUN_RECHARGE_PERIOD)

/obj/item/gun/magic/handle_click_empty(mob/user)
	if (user)
		user.visible_message("*wzhzhzh*", span_danger("The [name] whizzles quietly."))
	else
		src.visible_message("*wzhzh*")
	playsound(src, 'sound/weapons/empty.ogg', 100, 1)
