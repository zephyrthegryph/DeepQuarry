/datum/foo
	parent_type = /datum/pooled
/datum/bar
	var/x
	  parent_type = /datum/pooled/sub
/datum/baz
	parent_type = /datum/other
/datum/qux/child
POOL_DECLARE(/datum/decl)
// POOL_DECLARE(/datum/commented)
/datum/foo2 // comment
	parent_type = /datum/pooled
parent_type = /datum/pooled
/datum/notype
	parent_type = /datum/pooledish
/datum/unrelated_before
