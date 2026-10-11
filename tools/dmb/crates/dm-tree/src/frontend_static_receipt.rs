//! Stored declarations certified by the exact issued parse, shared by consumers.
use super::{BodyOccurrence, ColdFrontend, ParsedBody};
use crate::{procedure_statics::StaticPlan, MemberKind};
use dm_ir::ProcedureIdentity;
use std::sync::{Arc, OnceLock};

#[derive(Debug)]
pub struct IssuedStaticPlan {
    plan: StaticPlan,
    body_span: dm_syntax::Span,
    source: Arc<str>,
    reusable: OnceLock<Arc<RelativeStaticPlan>>,
}

/// Producer-owned syntax with checked body-relative coordinates. It carries
/// neither a frontend issuance nor absolute source coordinates.
#[derive(Debug)]
pub struct RelativeStaticPlan {
    plan: StaticPlan,
    source: Arc<str>,
    declarations: Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]>,
}
impl RelativeStaticPlan {
    pub fn canonical_declarations(&self) -> &Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]> {
        &self.declarations
    }
    pub fn plan(&self) -> &StaticPlan {
        &self.plan
    }
    pub fn source(&self) -> &Arc<str> {
        &self.source
    }
    pub fn bind(
        self: &Arc<Self>,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
    ) -> Result<Arc<IssuedStaticPlan>, String> {
        frontend
            .compact_body(body)
            .map_err(|e| format!("static body issuance: {e:?}"))?;
        let source = frontend
            .expanded
            .text
            .get(body.expanded_span.range())
            .ok_or("static body source outside capture")?;
        if source != self.source.as_ref() || identity(frontend, body)? != self.plan.procedure {
            return Err("relative static syntax differs from current issued body".into());
        }
        let mut plan = clone_semantics(&self.plan)?;
        for origin in &mut plan.origins {
            origin.span = shift(origin.span, body.expanded_span.start, self.source.len())?;
            origin.header_span = shift(
                origin.header_span,
                body.expanded_span.start,
                self.source.len(),
            )?;
        }
        let reusable = OnceLock::new();
        let _ = reusable.set(Arc::clone(self));
        Ok(Arc::new(IssuedStaticPlan {
            plan,
            body_span: body.expanded_span,
            source: Arc::clone(&self.source),
            reusable,
        }))
    }
}
impl IssuedStaticPlan {
    /// The current issued source is already validated before this owner is used.
    pub fn canonical_declarations(
        &self,
    ) -> Result<Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]>, String> {
        Ok(Arc::clone(
            self.relative_payload()?.canonical_declarations(),
        ))
    }
    pub fn plan(&self) -> &StaticPlan {
        &self.plan
    }
    pub fn source(&self) -> &Arc<str> {
        &self.source
    }
    pub fn retained_relative_payload(&self) -> Option<&Arc<RelativeStaticPlan>> {
        self.reusable.get()
    }
    pub fn relative_payload(&self) -> Result<Arc<RelativeStaticPlan>, String> {
        if let Some(payload) = self.reusable.get() {
            return Ok(Arc::clone(payload));
        }
        let mut plan = clone_semantics(&self.plan)?;
        for origin in &mut plan.origins {
            origin.span = relative(origin.span, self.body_span)?;
            origin.header_span = relative(origin.header_span, self.body_span)?;
        }
        let mut declarations: Vec<_> = plan.declarations.iter().cloned().map(Arc::new).collect();
        declarations.sort_by_key(|declaration| declaration.identity);
        let payload = Arc::new(RelativeStaticPlan {
            plan,
            source: Arc::clone(&self.source),
            declarations: declarations.into(),
        });
        let _ = self.reusable.set(payload);
        Ok(Arc::clone(
            self.reusable
                .get()
                .expect("relative static payload initialized"),
        ))
    }
}
fn clone_semantics(plan: &StaticPlan) -> Result<StaticPlan, String> {
    if !plan.executable_body.is_empty() {
        return Err("reusable static syntax cannot retain executable ASTs".into());
    }
    Ok(StaticPlan {
        procedure: plan.procedure,
        declarations: plan.declarations.clone(),
        origins: plan.origins.clone(),
        symbols: plan.symbols.clone(),
        executable_body: Vec::new(),
    })
}
fn relative(span: dm_syntax::Span, body: dm_syntax::Span) -> Result<dm_syntax::Span, String> {
    if span.start < body.start || span.start > span.end || span.end > body.end {
        return Err("static origin outside issued body".into());
    }
    Ok(dm_syntax::Span::new(
        span.start - body.start,
        span.end - body.start,
    ))
}
fn shift(span: dm_syntax::Span, start: usize, len: usize) -> Result<dm_syntax::Span, String> {
    if span.start > span.end || span.end > len {
        return Err("relative static origin outside current body".into());
    }
    Ok(dm_syntax::Span::new(
        start
            .checked_add(span.start)
            .ok_or("static origin offset overflow")?,
        start
            .checked_add(span.end)
            .ok_or("static origin offset overflow")?,
    ))
}
fn identity(frontend: &ColdFrontend, body: &BodyOccurrence) -> Result<ProcedureIdentity, String> {
    let tree = &frontend.snapshot.tree;
    let member = tree
        .member(body.member)
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
    Ok(ProcedureIdentity {
        owner,
        name: member.name,
        verb,
        occurrence: tree
            .member_occurrence(body.member)
            .ok_or("static procedure chain empty")?,
    })
}
impl ParsedBody<'_> {
    pub fn capture_stored_declarations(
        &self,
        identity: ProcedureIdentity,
    ) -> Result<Arc<IssuedStaticPlan>, String> {
        self.issuer
            .validate_parsed_body(self, self.occurrence)
            .map_err(|e| format!("static body issuance: {e:?}"))?;
        if identity != self::identity(self.issuer, self.occurrence)? {
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
                self.issuer
                    .compact_body(self.occurrence)
                    .map_err(|e| format!("static body issuance: {e:?}"))?;
                let source = self
                    .issuer
                    .expanded
                    .text
                    .get(self.occurrence.expanded_span.range())
                    .ok_or("static body source outside capture")?;
                Ok(Arc::new(IssuedStaticPlan {
                    plan,
                    body_span: self.occurrence.expanded_span,
                    source: Arc::from(source),
                    reusable: OnceLock::new(),
                }))
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
