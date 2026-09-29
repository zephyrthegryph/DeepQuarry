// Runtime half of TYPE_TABLE / COW_LIST (code/__defines/sys_tables.dm).

/// A private copy of a shared table; an empty list for a null table.
/proc/type_table_copy(list/table)
	return table ? table.Copy() : list()
