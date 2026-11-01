//! Metadata moved from the actual sys_sync_sql registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "sync_sql",
        hint: "open a /datum/io/sql request (code/engine/io/db.dm) and read the rows in its handler, or start the read with sql_ask() and carry on in its callback (sql_answer_rows())",
    },
    RuleMeta {
        name: "legacy_db_api",
        hint: "the /datum/db_query API is deleted: a read is a /datum/io/sql request (or sql_ask() with a callback), a write is sql_write(), and only BYOND's own waits use db_query_now()",
    },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
