/obj/passthrough/emp_act(severity)
	..()

/obj/passthrough2/emp_act(severity)
	. = ..()

/obj/passthrough3/emp_act(severity)
	return ..()

/obj/passthrough4/bullet_act(obj/item/projectile/P, def_zone)
	return ..(P, def_zone)

/obj/immune/emp_act(severity)

/obj/immune2/emp_act(severity)
	return

/obj/immune3/ex_act(severity)
	return 0

/obj/immune4/ex_act(severity)
	return FALSE

/obj/immune5/ex_act(severity)
	return null

/obj/immune6/ex_act(severity)
	return (0)

/obj/immune7/ex_act(severity)
	return ( ( FALSE ) );

/obj/effect/emp_act(severity)
	sparks()
	..()

/obj/effect2/emp_act(severity, extra)
	if(severity == 1)
		alarm()
	. = ..()

/obj/reads/bullet_act(obj/item/projectile/P, def_zone)
	to_chat(src, "hit by [P.name]")
	return ..()

/obj/reads2/bullet_act(obj/item/projectile/P)
	. = ..()
	take_hit(P.damage)

/obj/returns/bullet_act(obj/item/projectile/P)
	return PROJECTILE_CONTINUE

/obj/returns2/bullet_act(obj/item/projectile/P)
	return TRUE

/obj/returns3/ex_act(severity)
	return severity

/obj/returns4/ex_act(severity)
	. = ..()
	return .

/obj/changes/ex_act(severity)
	severity++
	return ..()

/obj/changes2/ex_act(severity)
	severity = clamp(severity, 1, 2)
	..()

/obj/changes3/ex_act(severity)
	severity -= 1
	..()

/obj/changes4/ex_act(severity)
	..(severity + 1)

/obj/changes5/ex_act(severity)
	..(3)

/obj/changes6/ex_act(severity)
	..(severity = severity)

/obj/changes7/ex_act(severity)
	..(severity, extra(1, 2))

/obj/changes8/attack_generic(mob/user, damage, attack_message)
	..(user, damage / 2, attack_message)

/obj/changes9/attack_generic(mob/user, damage, attack_message)
	..(user, damage, attack_message)

/obj/fire/fire_act(datum/gas_mixture/air, temperature, volume)
	..()
	flare()

/obj/fire2/fire_act(datum/gas_mixture/air, temperature, volume)
	if(temperature > 500)
		burn()

/obj/blob/blob_act(obj/structure/blob/B)
	qdel(src)

/obj/blob2/blob_act(obj/structure/blob/B)
	B.expand()

/obj/hitby/hitby(atom/movable/AM, speed)
	visible_message("[AM] bounces off")

/obj/hitby2/hitby(atom/movable/AM, speed)
	visible_message("it bounces off")

/obj/shock/electrocute_act(shock_damage, obj/source, siemens_coeff = 1.0)
	return 0

/obj/shock2/electrocute_act(shock_damage, obj/source, siemens_coeff = 1.0)
	return shock_damage

/obj/recv/receive_emp(datum/damage_packet/packet)
	sparks()

/obj/recv2/receive_ionic(datum/damage_packet/packet)
	return packet.amount

/obj/recv3/receive_explosion(datum/damage_packet/packet)
	. = ..()
	flash()

/obj/recv4/receive_blob(datum/damage_packet/packet)
	flash()

/obj/recv5/receive_shock(datum/damage_packet/packet)
	flash()

/obj/reflect/bullet_act(obj/item/projectile/P, def_zone)
	if(prob(50))
		visible_message("<span class='danger'>[P] is reflected!</span>")
		P.redirect(P.starting.x, P.starting.y, src)
		P.reflected = 1
		return PROJECTILE_FORCE_MISS
	return ..()

/obj/reflect2/bullet_act(obj/item/projectile/P, def_zone)
	if(istype(P, /obj/item/projectile/energy))
		P.redirect(P.starting.x, P.starting.y, src)
		P.reflected = 1
		return PROJECTILE_FORCE_MISS
	return ..()

/obj/reflect3/bullet_act(obj/item/projectile/P, def_zone)
	if(P.damage > 20)
		P.redirect(P.starting.x, P.starting.y, src)
		return PROJECTILE_FORCE_MISS
	return ..()

/obj/reflect4/bullet_act(obj/item/projectile/P, def_zone)
	act_message(src, P, "x")
	P.redirect(P.starting.x, P.starting.y, src)
	return PROJECTILE_FORCE_MISS

/obj/reflect5/bullet_act(obj/item/projectile/P, def_zone)
	var/z = foo(P)
	P.redirect(P.starting.x, P.starting.y, src)
	return PROJECTILE_FORCE_MISS

/obj/proc/definition_obj/emp_act(severity)
	sparks()

/obj/proc/emp_act(severity)
	sparks()

/obj/foo/proc/emp_act(severity)
	sparks()

/obj/foo/verb_ish/verb/emp_act(severity)
	sparks()

/atom/emp_act(severity)
	sparks()

/atom/movable/emp_act(severity)
	sparks()

/obj/emp_act(severity)
	sparks()

/turf/emp_act(severity)
	sparks()

/mob/emp_act(severity)
	sparks()

/mob/living/emp_act(severity)
	sparks()

/mob/living/carbon/emp_act(severity)
	sparks()

/obj/spaced/emp_act (severity)
	sparks()

/obj/commented/emp_act(severity)
	// sparks()
	..()

/obj/commented2/emp_act(severity)
	to_chat(src, "string with // slashes") // real comment
	..()

/obj/stringy/emp_act(severity)
	var/s = "return PROJECTILE_CONTINUE \" escaped quote"
	..()

/obj/stringy2/emp_act(severity)
	var/s = "..(severity + 1)"

/obj/noparam/emp_act()
	sparks()

/obj/defaults/ex_act(severity, target = null as null|anything, forced = FALSE)
	sparks()

/obj/defaults2/hitby(atom/movable/AM as mob|obj, speed = 5)
	visible_message("x")

/obj/blankline/emp_act(severity)

	sparks()

/obj/allowed/emp_act(severity) // ALLOW(sys_entry_override): the legacy override
	sparks()

// ALLOW(sys_entry_override): above the header
/obj/allowed2/emp_act(severity)
	sparks()

/obj/mixed/ex_act(severity)
	switch(severity)
		if(1)
			qdel(src)
		if(2)
			return 2
	..()

/obj/mixed2/emp_act(severity)
	var/obj/thing/x = foo
	x.bar(severity)
	return ..()

/obj/named_p/bullet_act(obj/item/projectile/Pr)
	Pr.redirect(Pr.starting.x, 1, src)
	Pr.reflected = 1
	return PROJECTILE_FORCE_MISS

/obj/named_p2/bullet_act(obj/item/projectile/Pr)
	visible_message("[Pr] hits")
	Pr.redirect(Pr.starting.x, 1, src)
	return PROJECTILE_FORCE_MISS

/obj/first_return_reflect/bullet_act(obj/item/projectile/P, def_zone)
	if(foo)
		P.redirect(P.starting.x, P.starting.y, src)
		return PROJECTILE_FORCE_MISS
	return PROJECTILE_CONTINUE
