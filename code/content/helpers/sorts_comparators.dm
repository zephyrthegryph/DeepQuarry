// The content half of code/base/helpers/sorts/comparators.dm: what names content, so the layer the engine calls cannot hold it.

// Sorts jobs by department, and then by flag within department
/proc/cmp_job_datums(datum/job/a, datum/job/b)
	. = 0
	if( LAZYLEN(a.departments) && LAZYLEN(b.departments) )
		var/list/common_departments = a.departments & b.departments // Makes a list that contains only departments that were in both.
		if(!common_departments.len)
			. = sorttext(b.departments[1], a.departments[1])

	if(. == 0) //Same department, push up if they're a head
		. = b.sorting_order - a.sorting_order

	if(. == 0) //Already in same sorting order, sort by name
		. = sorttext(b.title, a.title)

/proc/cmp_department_datums(datum/department/a, datum/department/b)
	. = b.sorting_order - a.sorting_order // First, sort by the sorting order vars.
	if(. == 0) // If they have the same var, then sort by name.
		. = sorttext(b.name, a.name)

/proc/cmp_crafting_req_priority(A, B)
	var/lhs
	var/rhs

	lhs = ispath(A, /datum/reagent) ? 0 : 1
	rhs = ispath(B, /datum/reagent) ? 0 : 1

	return lhs - rhs

///Tracks are sorted by genre then by title inside that.
/proc/cmp_media_track_asc(datum/track/A, datum/track/B)
	var/genre_sort = sorttext(B.genre || "Uncategorized", A.genre || "Uncategorized")
	return genre_sort || sorttext(B.title, A.title)

///Traits have sort they have defined on them to categorize themselves into groups. After that, alphabetical.
/proc/cmp_trait_datums_name(datum/trait/A, datum/trait/B)
	return A.sort == B.sort ? sorttext("[B.name]","[A.name]") : A.sort - B.sort

///Species have sort_hint they self-generate to hint themselves into groups. After that, alphabetical.
/proc/cmp_species(datum/species/A, datum/species/B)
	return A.sort_hint == B.sort_hint ? sorttext("[B.name]","[A.name]") : A.sort_hint - B.sort_hint

/proc/cmp_stored_item_name(datum/stored_item/A, datum/stored_item/B)
	return sorttext(B.item_name, A.item_name)

/proc/cmp_advdisease_resistance_asc(datum/affliction/contagion/engineered/A, datum/affliction/contagion/engineered/B)
	return A.resistance - B.resistance

/proc/cmp_advdisease_symptomid_asc(datum/viral_trait/A, datum/viral_trait/B)
	return sorttext(B.id, A.id)

