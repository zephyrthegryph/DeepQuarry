/datum/system/dbcore/proc/configure_query_concurrency(limit)
	max_concurrent_queries = limit

/datum/system/dbcore/proc/query_concurrency_limit()
	return max_concurrent_queries
