// Bulk heat-body binds (doc/rewrite/init_and_turfs.md sec 4.6).
//
// create_heat_body() used to make one Rust call per body, because every caller
// uses the handle at once (keep, power, couple, set a temperature). Inside a
// bind scope -- dq_heat_bind_begin()/_end(), opened around each map-load batch
// by SSatoms.InitializeAtoms() -- it instead:
//
//   1. takes a pre-reserved handle from a pool filled by one
//      vg heat_body_reserve(n) call. The handle is a live, kept, inert Rust body
//      at once, so every write works on it immediately;
//   2. queues the real configuration (capacity, temperature, environment,
//      keep) and configures every queued body in one heat_body_configure_list()
//      call when the scope ends.
//
// Handle-validity invariants (tested in verdigris/ffi/src/heat.rs and
// code/modules/unit_tests/dq_boot_bind_tests.dm):
//   - a reserved handle resolves to a live body from the moment it is taken;
//   - the configure never undoes a write made in between (temperature set,
//     slot 0 coupled, keep changed, heat added: see heat.rs `Reserved`);
//   - a pending body is configured before anything reads it:
//     resolve_heat_body() runs at every DM read site (get_temperature(),
//     heat_capacity_changed(), heat_recouple(), watch registration);
//   - a body released while pending leaves the queue (release_heat_body()),
//     and the configure skips handles that are no longer reserved, so a stale
//     handle is never configured into someone else's body;
//   - handles left in the pool when the outermost scope ends are released.

/// Open bind scopes; create_heat_body() reserves while > 0.
GLOBAL_VAR_INIT(dq_heat_bind_depth, 0)
/// Atom -> its queued configure args (`handle, capacity, temperature, kind, target, conductance, keep`).
GLOBAL_LIST_EMPTY(dq_heat_bind_pending)
/// Reserved handles not yet handed out.
GLOBAL_LIST_EMPTY(dq_heat_body_pool)
/// Diagnostics: bodies configured by bulk flushes, and flush calls.
GLOBAL_VAR_INIT(dq_heat_bind_configured, 0)
GLOBAL_VAR_INIT(dq_heat_bind_flushes, 0)

/// How many handles one reserve call asks for.
#define DQ_HEAT_RESERVE_CHUNK 64

/// Configures `A`'s pending heat body now if it has one (every read site calls this first).
#define HEAT_BODY_RESOLVE(A) if(length(GLOB.dq_heat_bind_pending) && GLOB.dq_heat_bind_pending[A]) { dq_heat_bind_flush(list(A)) }

/proc/dq_heat_bind_begin()
	GLOB.dq_heat_bind_depth++

/// Closes a scope; the outermost one configures everything queued and returns the pool.
/proc/dq_heat_bind_end()
	GLOB.dq_heat_bind_depth = max(GLOB.dq_heat_bind_depth - 1, 0)
	if(GLOB.dq_heat_bind_depth)
		return
	dq_heat_bind_flush()
	var/list/pool = GLOB.dq_heat_body_pool
	if(length(pool))
		vg_heat_body_release_list(pool.Copy())
		pool.Cut()

/// A reserved handle from the pool (refilled in one call), or null if Rust refused.
/proc/dq_heat_body_take()
	var/list/pool = GLOB.dq_heat_body_pool
	if(!length(pool))
		var/list/fresh = vg_heat_body_reserve(DQ_HEAT_RESERVE_CHUNK)
		if(!length(fresh))
			return null
		pool += fresh
	. = pool[length(pool)]
	pool.len--

/// Queues `A`'s body configuration and returns its reserved handle (null: bind now instead).
/proc/dq_heat_body_reserve_for(atom/A, capacity, temperature, kind, target, conductance, keep)
	var/handle = dq_heat_body_take()
	if(isnull(handle))
		return null
	GLOB.dq_heat_bind_pending[A] = list(handle, capacity, temperature, kind, target, conductance, keep ? TRUE : FALSE)
	return handle

/// Configures the pending bodies of `atoms` (default: all) in one Rust call, then runs
/// each one's heat_body_created() (watch relinks, rule subscriptions).
/proc/dq_heat_bind_flush(list/atoms)
	var/list/pending = GLOB.dq_heat_bind_pending
	if(!length(pending))
		return
	var/list/which = atoms || pending.Copy()
	var/list/configure_args = list()
	var/list/done = list()
	for(var/atom/A as anything in which)
		var/list/spec = pending[A]
		if(!spec)
			continue
		pending -= A
		// Released or replaced while pending: nothing to configure.
		if(A.heat_body != spec[1])
			continue
		configure_args += spec
		done += A
	if(!length(configure_args))
		return
	GLOB.dq_heat_bind_flushes++
	GLOB.dq_heat_bind_configured += vg_heat_body_configure_list(configure_args)
	for(var/atom/A as anything in done)
		A.heat_body_created()

/// `A`'s heat body is leaving: it is no longer pending.
/proc/dq_heat_bind_forget(atom/A)
	if(length(GLOB.dq_heat_bind_pending))
		GLOB.dq_heat_bind_pending -= A
