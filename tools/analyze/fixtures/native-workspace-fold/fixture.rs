//! Actual existing initial sources only; no answers or completion authority.
#[path="../native-tracked/fixture.rs"]mod tracked;
#[path="../native-state-schema/fixture.rs"]mod stateschema;
#[path="../native-lifecycle/fixture.rs"]mod lifecycle;
#[path="../native-sys-loot/fixture.rs"]mod loot;
#[path="../native-instance-list/fixture.rs"]mod instancelist;
#[path="../native-cache/fixture.rs"]mod cache;
#[path="../native-sys-ownership-forms/fixture.rs"]mod ownershipforms;
#[path="../native-api/fixture.rs"]mod api;
#[path="../native-sys-fields/fixture.rs"]mod fields;
#[path="../native-sys-appearance/fixture.rs"]mod appearance;
use dq_analyze::workspace_fold_policy::Policy;
pub fn cases(policy:Policy)->&'static[&'static str]{match policy{Policy::Tracked|Policy::TrackedTests=>tracked::CASES,Policy::StateSchema=>stateschema::CASES,Policy::Lifecycle=>lifecycle::CASES,Policy::Loot=>loot::CASES,Policy::InstanceList=>instancelist::CASES,Policy::Cache=>cache::CASES,Policy::OwnershipForms=>ownershipforms::CASES,Policy::Api=>api::CASES,Policy::Fields=>fields::CASES,Policy::Appearance=>appearance::CASES,}}
pub fn files(policy:Policy,case:&str)->Option<Vec<(String,Vec<u8>)>>{let mut rows:Vec<(String,Vec<u8>)>=match policy{Policy::Tracked|Policy::TrackedTests=>tracked::files(case)?,Policy::StateSchema=>stateschema::files(case)?.into_iter().map(|(path,text)|(path.to_owned(),text.as_bytes().to_vec())).collect(),Policy::Lifecycle=>lifecycle::files(case)?.into_iter().map(|(path,text)|(path.to_owned(),text.as_bytes().to_vec())).collect(),Policy::Loot=>loot::files(case)?,Policy::InstanceList=>instancelist::files(case)?,Policy::Cache=>cache::files(case)?,Policy::OwnershipForms=>ownershipforms::files(case)?,Policy::Api=>api::files(case)?.into_iter().map(|(path,bytes)|(path.to_owned(),bytes)).collect(),Policy::Fields=>fields::files(case)?.into_iter().map(|(path,bytes)|(path.to_owned(),bytes)).collect(),Policy::Appearance=>appearance::files(case)?.into_iter().map(|(path,bytes)|(path.to_owned(),bytes)).collect(),};if policy.tracked().is_none(){rows.retain(|(path,_)|!path.ends_with(".dme"));rows.push(("code/public_fold_context.dm".into(),b"/proc/public_fold_context()\n    return 1\n".to_vec()));rows.push(("deepquarry.dme".into(),b"#include \"code/public_fold_context.dm\"\n".to_vec()));}Some(rows)}
