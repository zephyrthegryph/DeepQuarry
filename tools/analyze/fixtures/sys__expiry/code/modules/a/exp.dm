EXPIRY_DECLARE(declared_a)
EXPIRY_TMP_DECLARE(declared_b)
STATIC_EXPIRY_DECLARE(declared_c)
EXPIRY_DECLARE(name)
EXPIRY_DECLARE(time)

/obj/thing/proc/compares()
	if(world.time > foo_until)
		return
	if(world.time < last_use + delay)
		return
	if(next_use > world.time)
		return
	if(world.time > 30 MINUTES)
		return
	if(world.time > 6000)
		return
	if(6000 < world.time)
		return
	if(world.time >= 1.5 SECONDS)
		return
	if(world.time > declared_a)
		return
	if(world.time < declared_b + 5)
		return
	if(declared_c <= world.time)
		return
	if(world.time > declared_a2)
		return
	if(world.time >= x.expires_at)
		return
	if(rec["expires"] < world.time)
		return
	if(entry[3] > world.time)
		return
	if(world.time > 30 MINUTES && foo_until)
		return
	if(world.time > 30 MINUTES || foo_until)
		return
	if(world.time > 30 MINUTES + foo)
		return
	if(a && 5 < world.time)
		return
	if(world.time == foo_until)
		return
	if(world.time != foo_until)
		return
	if(world.time << 2)
		return
	if(world.time >> 2)
		return
	if(world.time > foo_until) // ALLOW(cooldown): a recorded time, kept as a cooldown
		return
	// ALLOW(cooldown): above
	if(world.time > foo_until)
		return
	// ALLOW(cooldown)
	if(world.time > foo_until)
		return
	// ALLOW(sys_world_time_expiry): fixture keep from above
	if(world.time > foo_until)
		return
	if(world.time > foo_until) // ALLOW(sys_world_time_expiry): fixture keep on the line
		return
	if(world.time > foo_until) // trailing comment
		return
	// if(world.time > foo_until)
	to_chat(usr, "world.time > foo_until")
	if(a) // world.time > foo_until
		return
#define EXPIRED_X (world.time > foo_until)
	# define EXPIRED_Y (world.time > foo_until)
	x = world.time // a bare stamp

/obj/thing/proc/elapsed_compares()
	if(world.time - last_x > 5)
		return
	if(5 < world.time - started)
		return
	if(world.time - x.last_y >= 10)
		return
	if(world.time - last["k"] < 10)
		return
	if(world.time - (last_z) > 3)
		return
	if(world.time - 5 > 3)
		return
	if(world.time - last_x == 5)
		return
	if(a > world.time - b)
		return
	if(world.time - last_x)
		return
	var/e = world.time - last_x
	y = world.time - last_x // ALLOW(sys_world_time_expiry): fixture keep

/obj/thing/proc/writes()
	x = world.time
	x = world.time + 5
	x = (world.time + 5)
	x = ( world.time )
	x = world.time - 5
	x = world.time * 2
	x = world.time / 2
	x = world.time % 2
	x == world.time
	x != world.time
	x <= world.time
	x >= world.time
	x += world.time
	x -= world.time
	x |= world.time
	var/t = world.time
	var/obj/o = world.time
	var/static/t2 = world.time
	var/tmp/t3 = world.time
	list(a = world.time)
	foo(a = world.time)
	x = world.timex
	x = world.time_of
	x = world.time // ALLOW(sys_world_time_write): fixture keep
	// ALLOW(sys_world_time_write): fixture keep above
	x = world.time
	// x = world.time
	to_chat(usr, "x = world.time")
	x = world.time // trailing
	GLOB.last = world.time

/obj/thing/proc/macros()
	EXPIRY_SET(src, declared_a, 5)
	EXPIRY_SET(src, undeclared_z, 5)
	ELAPSED(src, undeclared_y)
	EXPIRY_ACTIVE(foo(bar), undeclared_x)
	EXPIRY_LEFT(src, declared_b)
	EXPIRY_EXTEND(src, declared_c, 5)
	EXPIRY_CLEAR(src, om_declared)
	EXPIRY_STAMP(src, undeclared_w)
	EXPIRY_EXPIRED(src, undeclared_v)
	EXPIRY_AT(src, undeclared_u, 5)
	EXPIRY_OTHER(src, undeclared_t)
	EXPIRY_SET(src, undeclared_s, 5) // ALLOW(sys_expiry_undeclared): fixture keep
	// EXPIRY_SET(src, undeclared_r, 5)
	to_chat(usr, "EXPIRY_SET(src, undeclared_q, 5)")
	EXPIRY_SET(src, undeclared_p, 5) EXPIRY_SET(src, undeclared_o, 5)
	EXPIRY_ACTIVE(a[1], undeclared_n)
	EXPIRY_ACTIVE(a(b)(c), undeclared_m)
#define EXPIRY_MACRO_X EXPIRY_SET(src, undeclared_l, 5)

/obj/thing/proc/at_writes(a, b = 5, var/c)
	x = EXPIRY_AT(src, clock, 5)
	a = EXPIRY_AT(src, clock, 5)
	b = EXPIRY_AT(src, clock, 5)
	c = EXPIRY_AT(src, clock, 5)
	src.y = EXPIRY_AT(src, clock, 5)
	GLOB.g = EXPIRY_AT(src, clock, 5)
	GLOB.o.g = EXPIRY_AT(src, clock, 5)
	var/z = EXPIRY_AT(src, clock, 5)
	z = EXPIRY_AT(src, clock, 5)
	var/obj/w
	w = EXPIRY_AT(src, clock, 5)
	x.y = EXPIRY_AT(src, clock, 5)
	x.y.z = EXPIRY_AT(src, clock, 5)
	d = EXPIRY_AT(src, clock, 5) // ALLOW(sys_world_time_write): fixture keep
	// d = EXPIRY_AT(src, clock, 5)
	to_chat(usr, "d = EXPIRY_AT(src, clock, 5)")
	list_x[1] = EXPIRY_AT(src, clock, 5)
	e += EXPIRY_AT(src, clock, 5)

/obj/thing/proc/at_writes2(a)
	x = EXPIRY_AT(src, clock, 5)
	a = EXPIRY_AT(src, clock, 5)
	c = EXPIRY_AT(src, clock, 5)

/obj/thing/var/at_member = EXPIRY_AT(src, clock, 5)
	x = EXPIRY_AT(src, clock, 5)
