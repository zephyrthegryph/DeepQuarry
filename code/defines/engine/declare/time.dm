// The time engine's record layouts (code/engine/time/).

/// Stride of rec.timers: id, due (timer-clock ds), proc, args, handle positions, flags.
/// Ids only grow and entries are only appended or cut, so the list is sorted by id
/// (timer_index() binary-searches it).
#define OM_TIMER_STRIDE 6
/// Timer flags (the record's 6th field): the proc is a global proc.
#define OM_TIMER_GLOBAL (1<<0)
/// A deleted captured argument is passed as null (after()) instead of dropping the call.
#define OM_TIMER_NULLS_FOR_GONE (1<<1)
/// A global proc that takes the timer's owner as its first argument (the keyed after() trampoline): the owner is
/// prepended when it fires, so it is never captured (and resolved) as one of its own timer's arguments.
#define OM_TIMER_OWNER_FIRST (1<<2)
/// Stride of rec.timer_heap: due, id.
#define OM_TIMER_HEAP_STRIDE 2
/// A heap compacts (is rebuilt from the live timers) when it holds more than this many entries beyond the live timers' share.
#define OM_TIMER_HEAP_SLACK 32
