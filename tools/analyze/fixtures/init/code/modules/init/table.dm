/obj/tbl
	init_from_table = TRUE
/obj/tbl/Initialize(mapload)
/obj/tbl/child/Initialize(mapload) // INIT: a reason keeps the initialize rule, not the table rule
/obj/tbl/child/LateInitialize()
/obj/tbl/off
	init_from_table = FALSE
/obj/tbl/off/Initialize(mapload) // INIT: the fixture sets it back to FALSE
/obj/tbl/off/deeper/Initialize(mapload) // INIT: the nearest flagged ancestor is FALSE
/obj/tbl/other/Initialize(mapload) // ALLOW(init): kept, so it is not a header of the table pass either
/obj/tbl/ownerkeep
/obj/tbl2 // a trailing comment still makes a type block
	init_from_table = 1
/obj/tbl2/sub/Initialize() // INIT: the fixture
/obj/tbl3(x)
	init_from_table = TRUE
/obj/tbl3/sub/Initialize() // INIT: the fixture
/obj/tbl4
	var/x = 1
	init_from_table = TRUE
/obj/tbl4/sub/Initialize() // INIT: the fixture
/obj/tbl5
	init_from_table = 0
/obj/tbl5/sub/Initialize() // INIT: the fixture
/obj/tbl6
	init_from_tablex = TRUE
	init_from_table = TRUEISH
	init_from_table  =  TRUE
/obj/tbl6/sub/Initialize() // INIT: the fixture
/obj/tbl7
init_from_table = TRUE
/obj/tbl7/sub/Initialize() // INIT: flag at column 0 needs leading whitespace
/obj/tbl8
	init_from_table = TRUE
	init_from_table = FALSE
/obj/tbl8/sub/Initialize() // INIT: the last flag in the block wins
/obj/tbl9
	init_from_table = FALSE
	init_from_table = TRUE
/obj/tbl9/sub/Initialize() // INIT: the last flag in the block wins
/obj/tbl9/sub/deeper/LateInitialize() // INIT: the fixture
/datum/tbl10
	init_from_table = TRUE
/datum/tbl10/sub
	init_from_table = FALSE
/datum/tbl10/sub/deeper/Initialize() // INIT: the nearest flag is FALSE
/obj/tbl/proc/Initialize(mapload) // INIT: path ends in proc, the ancestor is /obj/tbl/proc
/obj/tbl/child/sub/Initialize(mapload) // INIT: two levels below the flagged type
	init_from_table = TRUE
