COOLDOWN_DECLARE(declared_a)
COOLDOWN_DECLARE(declared_b)
STATIC_COOLDOWN_DECLARE(declared_c)
COOLDOWN_DECLARE(name)
COOLDOWN_DECLARE(time)

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
	COOLDOWN_START_OWN(src, declared_a, 5)
	COOLDOWN_START_OWN(src, undeclared_z, 5)
	COOLDOWN_EXTEND(src, undeclared_y, 5)
	COOLDOWN_RUNNING(foo(bar), undeclared_x)
	COOLDOWN_TIMELEFT_OWN(src, declared_b)
	COOLDOWN_EXTEND(src, declared_c, 5)
	COOLDOWN_RESET(src, om_declared)
	COOLDOWN_RUNNING(src, undeclared_w)
	COOLDOWN_LAPSED(src, undeclared_v)
	TIME_NOW(src, undeclared_u, 5)
	TIME_NOWX(src, undeclared_t)
	COOLDOWN_START_OWN(src, undeclared_s, 5) // ALLOW(sys_expiry_undeclared): fixture keep
	// COOLDOWN_START_OWN(src, undeclared_r, 5)
	to_chat(usr, "COOLDOWN_START_OWN(src, undeclared_q, 5)")
	COOLDOWN_START_OWN(src, undeclared_p, 5) COOLDOWN_START_OWN(src, undeclared_o, 5)
	COOLDOWN_RUNNING(a[1], undeclared_n)
	COOLDOWN_RUNNING(a(b)(c), undeclared_m)
#define TIME_MACRO_X COOLDOWN_START_OWN(src, undeclared_l, 5)

/obj/thing/proc/at_writes(a, b = 5, var/c)
	x = TIME_NOW(src, clock, 5)
	a = TIME_NOW(src, clock, 5)
	b = TIME_NOW(src, clock, 5)
	c = TIME_NOW(src, clock, 5)
	src.y = TIME_NOW(src, clock, 5)
	GLOB.g = TIME_NOW(src, clock, 5)
	GLOB.o.g = TIME_NOW(src, clock, 5)
	var/z = TIME_NOW(src, clock, 5)
	z = TIME_NOW(src, clock, 5)
	var/obj/w
	w = TIME_NOW(src, clock, 5)
	x.y = TIME_NOW(src, clock, 5)
	x.y.z = TIME_NOW(src, clock, 5)
	d = TIME_NOW(src, clock, 5) // ALLOW(sys_world_time_write): fixture keep
	// d = TIME_NOW(src, clock, 5)
	to_chat(usr, "d = TIME_NOW(src, clock, 5)")
	list_x[1] = TIME_NOW(src, clock, 5)
	e += TIME_NOW(src, clock, 5)

/obj/thing/proc/at_writes2(a)
	x = TIME_NOW(src, clock, 5)
	a = TIME_NOW(src, clock, 5)
	c = TIME_NOW(src, clock, 5)

/obj/thing/var/at_member = TIME_NOW(src, clock, 5)
	x = TIME_NOW(src, clock, 5)
