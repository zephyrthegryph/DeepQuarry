p='code/engine/change/interest.dm'
s=open(p,encoding='utf-8',newline='').read()
def rep(old,new,cnt=1):
    global s
    assert old in s, old
    s=s.replace(old,new,cnt)
rep("""	var/list/owed = GLOB.interest_owed[key]
	if(!owed)
		owed = list()
		GLOB.interest_owed[key] = owed
	owed[handle] = TRUE""","""	var/alist/owed = GLOB.interest_owed[key]
	if(!owed)
		owed = alist()
		GLOB.interest_owed[key] = owed
	owed[handle] = TRUE""")
rep("""	var/list/owed = GLOB.interest_owed[key]
	if(!owed)
		return
	var/handle
""","""	var/alist/owed = GLOB.interest_owed[key]
	if(!owed)
		return
	var/handle
""")
rep("""	var/list/owed = GLOB.interest_owed[key]
	if(!length(owed))
		GLOB.interest_scan_empty++""","""	var/alist/owed = GLOB.interest_owed[key]
	if(!length(owed))
		GLOB.interest_scan_empty++""")
rep("""	var/list/rank = list() // handle -> squared distance of its turf from the point (a turf's own entry just before what stands on it)
	var/list/stale""","""	var/list/rank = list() // atom -> squared distance of its turf from the point, doubled, a turf's own entry just before what stands on it (a local list of the scan)
	var/list/stale""")
rep("""		rank[handle] = ((T.x - mid_x) ** 2 + (T.y - mid_y) ** 2) * 2 + (isturf(A) ? 0 : 1)
	if(stale)
		owed -= stale
""","""		rank[A] = ((T.x - mid_x) ** 2 + (T.y - mid_y) ** 2) * 2 + (isturf(A) ? 0 : 1)
	if(stale)
		for(var/handle in stale)
			owed -= handle
""")
rep("""	for(var/handle in rank)
		into += (handle < 0 ? handle_of(interest_owed_atom(handle)) : handle)
		.++""","""	for(var/atom/A as anything in rank)
		into += handle_of(A)
		.++""")
open(p,'w',encoding='utf-8',newline='').write(s)

p='code/tests/unit_tests/dq_chunk_interest.dm'
s=open(p,encoding='utf-8',newline='').read()
rep("""	var/list/set = GLOB.interest_owed[INTEREST_KEY(z, cx, cy)]
	TEST_ASSERT(!(set && set[gone_handle])""","""	var/alist/set = GLOB.interest_owed[INTEREST_KEY(z, cx, cy)]
	TEST_ASSERT(!(set && set[gone_handle])""")
rep("""				var/list/set = GLOB.interest_owed[INTEREST_KEY(z, cx, cy)]
				for(var/atom/A as anything in walked)""","""				var/alist/set = GLOB.interest_owed[INTEREST_KEY(z, cx, cy)]
				for(var/atom/A as anything in walked)""")
open(p,'w',encoding='utf-8',newline='').write(s)
