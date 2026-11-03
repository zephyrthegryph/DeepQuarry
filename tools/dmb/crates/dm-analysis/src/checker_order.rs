//! Reference checker report traversal over the issued compiler roster.
//!
//! SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0)
//! dreamchecker::run_inner walks lexical child paths in BTreeMap preorder,
//! then first-name proc groups and each group's normalized value order.
//! This does not change runtime dispatch, inheritance, or compiler body order.

use dm_tree::{
    frontend::{BodyOccurrence, ColdFrontend},
    DefinitionMode, MemberKind, SemanticTree, Target,
};
use std::collections::BTreeMap;

/// Return borrowed bodies with their original archive ordinals. Authenticate
/// issuance before consulting the publicly visible compatibility fields.
pub fn bodies(frontend: &ColdFrontend) -> Result<Vec<(usize, &BodyOccurrence)>, String> {
    frontend.callable_roster()?;
    order(&frontend.snapshot.tree, &frontend.bodies)
}

/// Same lexical checker order projected over the ORIGINAL archive roster.
pub fn archived_bodies(
    archive: &dm_tree::frontend::BodyArchive,
) -> Result<Vec<(usize, &BodyOccurrence)>, String> {
    order(archive.tree(), archive.occurrences())
}
fn components(path: &str) -> Vec<&str> {
    path.split('/').filter(|part| !part.is_empty()).collect()
}

fn order<'a>(
    tree: &'a SemanticTree,
    bodies: &'a [BodyOccurrence],
) -> Result<Vec<(usize, &'a BodyOccurrence)>, String> {
    let mut first_name = BTreeMap::new();
    // Include bodyless declarations: an earlier declaration can establish a
    // group's position even when its first executable override comes later.
    visit_callable_declarations::<String>(tree,||Ok(()),|owner,name,index|{first_name.entry((owner,name)).or_insert(index);Ok(())})?;
    let mut ordered = Vec::with_capacity(bodies.len());
    for (ordinal, body) in bodies.iter().enumerate() {
        let member = tree
            .member(body.member)
            .ok_or("checker body member absent")?;
        let owner = tree
            .type_node(member.owner)
            .ok_or("checker body owner absent")?;
        let path = tree
            .symbols()
            .text(owner.path)
            .ok_or("checker owner path absent")?;
        let first = first_name
            .get(&(member.owner, member.name))
            .copied()
            .ok_or("checker callable encounter absent")?;
        let occurrence = tree
            .member_occurrence(body.member)
            .ok_or("checker callable occurrence absent")?;
        ordered.push((
            (
                components(path),
                first,
                member.definition != DefinitionMode::Declare,
                occurrence,
                ordinal,
            ),
            body,
        ));
    }
    ordered.sort_by(|(left, _), (right, _)| left.cmp(right));
    Ok(ordered
        .into_iter()
        .map(|(key, body)| (key.4, body))
        .collect())

}

#[cfg(test)]
#[path = "checker_order_tests.rs"]
mod tests;

/// One existing original declaration traversal shared by both checked and old
/// report order. Bodyless declarations establish group rank identically.
pub(crate) fn visit_callable_declarations<E:From<String>>(tree:&SemanticTree,mut checkpoint:impl FnMut()->Result<(),E>,mut visit:impl FnMut(dm_ir::TypeId,dm_ir::SymbolId,usize)->Result<(),E>)->Result<(),E>{for(index,target)in tree.declarations().iter().enumerate(){checkpoint()?;if let Target::Member(id)=target{let member=tree.member(*id).ok_or_else(||E::from("checker declaration member absent".to_owned()))?;if matches!(member.kind,MemberKind::Proc|MemberKind::Verb){visit(member.owner,member.name,index)?;}}}Ok(())}

#[path="checker_order_checked.rs"]mod checked;
pub(crate) use checked::{ArchivedOrder,sort_report_projection};

/// Borrowed DATA view of the EXISTING checked order, with no source role.
/// The private backing projection dies before its caller's operation credit.
pub struct ArchivedOrderView<'view,'source>{order:&'view ArchivedOrder<'source>}
impl ArchivedOrderView<'_,'_>{pub fn len(&self)->usize{self.order.len()}pub fn ordinal(&self,index:usize)->Option<usize>{self.order.ordinal(index)}}
pub fn with_archived_order_using<W:crate::checker_effects::EffectReportWork,T>(archive:&dm_tree::frontend::BodyArchive,admission:&crate::checker_effects::ExecutionAdmission,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>,consume:impl FnOnce(ArchivedOrderView<'_,'_>,&mut W)->Result<T,crate::policy_body_demand::PolicyFailure>)->Result<T,crate::policy_body_demand::PolicyFailure>{
 use crate::policy_body_demand::PolicyFailure;let order=ArchivedOrder::build(archive,admission,&mut||checkpoint(),&mut|bytes|work.reserve(bytes))?;let pending=consume(ArchivedOrderView{order:&order},work);drop(order);if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;admission.reserve_external(0).map_err(PolicyFailure::Operational)?;pending
}

pub(crate) use checked::heapsort as sort_source_order;

/// Stateless DATA-only access to the SAME established fallible in-place sort.
/// It grants no source, checker or completion role and stops at the first error.
pub fn sort_policy_data<T,E>(rows:&mut[T],compare:&mut impl FnMut(&T,&T)->Result<std::cmp::Ordering,E>)->Result<(),E>{checked::heapsort(rows,compare)}
#[cfg(test)]mod policy_data_sort_tests{#[test]fn fallible_policy_data_order_stops_at_actual_io_and_quota_then_recovers(){for limit in [false,true]{let mut values=(0..10000).rev().collect::<Vec<_>>();let mut calls=0;let error=super::sort_policy_data(&mut values,&mut|a,b|{calls+=1;if calls==17{Err(if limit{std::io::ErrorKind::OutOfMemory.into()}else{std::io::Error::from_raw_os_error(1450)})}else{Ok(a.cmp(b))}}).unwrap_err();assert_eq!(calls,17,"no comparisons or callbacks continue after the first typed failure");if limit{assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory)}else{assert_eq!(error.raw_os_error(),Some(1450))}super::sort_policy_data(&mut values,&mut|a,b|Ok::<_,std::io::Error>(a.cmp(b))).unwrap();assert_eq!(values,(0..10000).collect::<Vec<_>>());}}}
