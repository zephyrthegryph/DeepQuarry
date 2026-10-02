/proc/test()
	if(!query.Execute())
	query.Execute(async = FALSE)
	if(!query_admin_in_db.warn_execute())
	query.Execute(SSsqlite.sqlite_db)
	query.Execute(SQLITE_DB)
	query.warn_execute(my_sqlite_thing)
	Execute(found)
	// query.Execute()
	var/x = "query.Execute()"
	SSdbcore.NewQuery("SELECT 1").Execute()
	arr[1].Execute()
	query .Execute()
	query. Execute()
	query . Execute()
	a.Execute(sqlite_x) && b.Execute()
	a.Execute() && b.Execute(sqlite_x)
	query.Execute("sqlite")
	query.Execute("[sqlite_thing]")
	query.Execute(list(1, 2), SQLITE)
	query.Execute(
		SQLITE)
	query.Execute(
		async = FALSE)
	x.y.Execute()
	my_warn_execute.Execute()
	query.warn_execute_all()
	query.Executed()
	query.Execute
	query.Execute.foo()
	query.execute()
	query.EXECUTE()
	/* query.Execute() */
	query.Execute() // trailing comment
	query.Execute() /* block */ query2.Execute()
	{"
	query.Execute()
	"}
	@"query.Execute()"
	if(query.Execute() && other.Execute())
	return query.Execute()
	query?.Execute()
	query:Execute()
	(query).Execute()
	query.Execute() // ALLOW(sys_sync_sql): the fixture keeps this boot-only call on the line
	// ALLOW(sys_sync_sql): the fixture keeps the next call from the comment line above
	query.Execute()
	query.Execute() // ALLOW(sync_sql): the rule name without sys_ keeps nothing
	query.Execute() // ALLOW(sys_sync_sql)
	query.Execute() // ALLOW(sys_usr_outside_verb): another module's name keeps nothing
	query.Execute() // ALLOW(init, sys_sync_sql): two names, one of them ours
/datum/SDQL2_query/proc/Execute(list/found)
	return 1
/datum/thing/proc/warn_execute(x)
	return x.Execute()
