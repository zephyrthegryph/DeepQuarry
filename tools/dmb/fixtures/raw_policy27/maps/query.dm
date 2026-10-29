/proc/query_test(q)
    q.Execute()
    q.Execute() // ALLOW(sys_sync_sql): this is an intentional annotation fixture
