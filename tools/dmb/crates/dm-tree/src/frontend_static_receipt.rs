//! Stored declarations certified by the exact issued parse, shared by consumers.
use super::ParsedBody;
use crate::{procedure_statics::StaticPlan, MemberKind};
use dm_ir::ProcedureIdentity;
use std::sync::Arc;

#[derive(Debug)]
pub struct IssuedStaticPlan {
    plan: StaticPlan,
}
impl IssuedStaticPlan {
    pub fn plan(&self) -> &StaticPlan {
        &self.plan
    }
}
impl ParsedBody<'_> {
    pub fn capture_stored_declarations(
        &self,
        identity: ProcedureIdentity,
    ) -> Result<Arc<IssuedStaticPlan>, String> {
        self.issuer
            .validate_parsed_body(self, self.occurrence)
            .map_err(|e| format!("static body issuance: {e:?}"))?;
        let tree = &self.issuer.snapshot.tree;
        let member = tree
            .member(self.occurrence.member)
            .ok_or("static procedure member absent")?;
        let owner = tree
            .type_node(member.owner)
            .ok_or("static procedure owner absent")?
            .path;
        let verb = match member.kind {
            MemberKind::Proc => false,
            MemberKind::Verb => true,
            MemberKind::Var => return Err("static body is not a procedure".into()),
        };
        let occurrence = tree
            .member_occurrence(self.occurrence.member)
            .ok_or("static procedure chain empty")?;
        if identity
            != (ProcedureIdentity {
                owner,
                name: member.name,
                verb,
                occurrence,
            })
        {
            return Err("static procedure identity differs from issued body".into());
        }
        self.static_receipt
            .get_or_init(|| {
                let plan = match self.statement_body() {
                    Some(body) => {
                        crate::procedure_statics::capture_issued_statements(identity, body)
                    }
                    None => crate::procedure_statics::capture_declarations(
                        identity,
                        &self.item().children,
                    ),
                }?;
                Ok(Arc::new(IssuedStaticPlan { plan }))
            })
            .clone()
    }
    pub fn stored_declaration_receipt(&self) -> Option<Arc<IssuedStaticPlan>> {
        self.static_receipt
            .get()
            .and_then(|result| result.as_ref().ok())
            .map(Arc::clone)
    }
}
