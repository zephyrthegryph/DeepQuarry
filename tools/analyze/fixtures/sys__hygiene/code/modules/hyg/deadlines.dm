/obj/machinery/poller/process()
	if(world.time >= next_fire)
		fire()
		next_fire = world.time + 5 SECONDS
	if(close_at <= world.time)
		close()
		close_at = world.time + 1
	if(world.time > thing.deadline[1])
		go()
	if(world.time - last_run > 5)
		go()
	if(world.time > 100)
		go()
	if(REALTIMEOFDAY > cooldown_end)
		go()
	if(src.deadline_at < world.time + 3)
		go()
	// if(world.time > commented_deadline)
	if(world.time > trailing_deadline) // if(world.time > other_commented)
		go()
	to_chat(world, "world.time > in_string")
	if(xworld.time > nothing)
		go()
	if(foo.world.time > nothing2)
		go()

/obj/machinery/poller/proc/periodic_step(dt)
	if(world.time < wake_at?[1])
		return
	wake_at = world.time + 2

/obj/machinery/poller/proc/machine_step(dt)
	if(world.time >= allowed_deadline) // ALLOW(sys_deadline_poll): rate gate
		go()
	allowed_deadline = world.time + 5
	// ALLOW(sys_deadline_poll): slides every step
	if(world.time >= other_allowed)
		go()
	other_allowed = world.time + 5

/obj/machinery/poller/proc/service_step(dt)
	if(world.time >= svc_deadline)
		go()
	svc_deadline += world.time
	svc_deadline = world.time + 9
	svc_deadline == world.time
	svc_deadline = something + world.time
	svc_deadline = 5 // world.time

/obj/machinery/poller/proc/not_periodic()
	if(world.time >= not_periodic_deadline)
		go()
	not_periodic_deadline = world.time + 5

/obj/machinery/poller/proc/tick()
	if(world.time >= plain_tick_deadline)
		go()

/datum/om/behaviour/ticker/proc/tick(E, dt)
	if(world.time >= behaviour_deadline)
		go()

/datum/om/behaviour/ticker2
	proc/tick(E, dt)
		if(world.time >= nested_behaviour_deadline)
			go()
	proc/other()
		if(world.time >= nested_other)
			go()

/obj/machinery/nested_block
	process()
		if(world.time >= nested_block_deadline)
			go()
	proc/process()
		if(world.time >= nested_block_deadline2)
			go()
		var/x = 1
	var/after = 1

/obj/machinery/blank_lines/process()

	if(world.time >= blank_deadline)
		go()

	go_again()
/obj/machinery/after_body
	var/x = 1

#define SOMETHING 1
/obj/machinery/after_define/process()
	if(world.time >= define_deadline)
		go()

// comment at column zero ends the type context
	/obj/machinery/indented_not_header/process()
		if(world.time >= indented_deadline)
			go()

/obj/machinery/store_only
	var/stored_deadline = 0

/obj/machinery/store_only/proc/set_it()
	stored_deadline = world.time + 5
	next_fire = world.time + 7
