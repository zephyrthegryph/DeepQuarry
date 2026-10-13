// What the handle path is made of, one primitive at a time (microseconds per operation, one pass over RELPRIM_N). Read with dq_rel_perf_handles.

#define RELPRIM_N 20000

/proc/relprim_done(label, start)
	log_test("REL PRIM [label]: [round(((REALTIMEOFDAY - start) * 100000) / RELPRIM_N, 0.01)] us/op")

/datum/unit_test/dq_rel_perf_primitives
	tier = TEST_TIER_EXHAUSTIVE // a measurement, run by name or with --tier=all

/datum/unit_test/dq_rel_perf_primitives/Run()
	var/list/made = list()
	for(var/i in 1 to RELPRIM_N)
		made += new /datum/relperf_member
	var/sink = null
	var/t = REALTIMEOFDAY
	for(var/datum/relperf_member/M as anything in made)
		sink = M
	relprim_done("empty loop", t)
	t = REALTIMEOFDAY
	for(var/datum/relperf_member/M as anything in made)
		sink = "\ref[M]"
	relprim_done("ref text", t)
	t = REALTIMEOFDAY
	for(var/datum/relperf_member/M as anything in made)
		sink = ref(M)
	relprim_done("ref() proc", t)
	t = REALTIMEOFDAY
	for(var/datum/relperf_member/M as anything in made)
		M.own_key_text = null
		sink = own_key(M)
	relprim_done("own_key first call", t)
	t = REALTIMEOFDAY
	for(var/datum/relperf_member/M as anything in made)
		sink = OWN_KEY(M)
	relprim_done("own_key cached", t)
	var/list/keys = list()
	for(var/datum/relperf_member/M as anything in made)
		keys += OWN_KEY(M)
	t = REALTIMEOFDAY
	for(var/key in keys)
		sink = own_locate(key)
	relprim_done("own_locate(key)", t)
	var/list/refs = list()
	for(var/datum/relperf_member/M as anything in made)
		refs += "\ref[M]"
	t = REALTIMEOFDAY
	for(var/r in refs)
		sink = locate(r)
	relprim_done("locate(ref text) with the text in hand", t)
	t = REALTIMEOFDAY
	for(var/i in 1 to RELPRIM_N)
		sink = locate("\[0x[num2text(2097152, 1, 16)][num2text(i, 6, 16)]\]")
	relprim_done("locate of a ref built from two numbers", t)
	var/alist/by_number = alist()
	var/alist/by_text = alist()
	var/list/texts = list()
	for(var/i in 1 to RELPRIM_N)
		by_number[i] = i
		var/text = "[i]:0"
		texts += text
		by_text[text] = i
	t = REALTIMEOFDAY
	for(var/i in 1 to RELPRIM_N)
		sink = by_number[i]
	relprim_done("alist read by number", t)
	t = REALTIMEOFDAY
	for(var/text in texts)
		sink = by_text[text]
	relprim_done("alist read by text", t)
	var/list/plain = list()
	plain.len = RELPRIM_N
	t = REALTIMEOFDAY
	for(var/i in 1 to RELPRIM_N)
		sink = plain[i]
	relprim_done("list read by index", t)
	t = REALTIMEOFDAY
	for(var/i in 1 to RELPRIM_N)
		sink = "[i]:7"
	relprim_done("new text id:gen", t)
	t = REALTIMEOFDAY
	for(var/text in texts)
		sink = text2num(copytext(text, 1, 3))
	relprim_done("text2num of copytext", t)
	t = REALTIMEOFDAY
	for(var/text in texts)
		sink = findtext(text, ":")
	relprim_done("findtext", t)
	t = REALTIMEOFDAY
	for(var/datum/relperf_member/M as anything in made)
		sink = entity_handle(M)
	relprim_done("entity_handle first call", t)
	t = REALTIMEOFDAY
	for(var/datum/relperf_member/M as anything in made)
		sink = entity_handle(M)
	relprim_done("entity_handle repeat", t)
	var/list/handles = list()
	for(var/datum/relperf_member/M as anything in made)
		handles += entity_handle(M)
	t = REALTIMEOFDAY
	for(var/h in handles)
		sink = resolve_handle(h)
	relprim_done("resolve_handle", t)
	t = REALTIMEOFDAY
	for(var/datum/relperf_member/M as anything in made)
		qdel(M)
	relprim_done("qdel of a datum with a handle", t)
	if(sink)
		sink = null
