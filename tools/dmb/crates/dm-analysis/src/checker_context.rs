//! Borrowed policy context over the ORIGINAL compiled owner and query host.
//! No SemanticTree clone, new symbol inventory, body parse, or private QueryDb.
use crate::{
    checks::{BodyView, Diagnostic, Severity},
    checks_parent_call,
};
use dm_ir::{PackedU128, Resolver};
use dm_tree::{
    frontend::{ArchivedBody, BodyArchive, BodySyntaxQueries, ColdFrontend, ParsedBody},
    SemanticTree,
};

#[derive(Clone, Copy)]
enum Owner<'a> {
    Live(&'a ColdFrontend),
    Archive(&'a BodyArchive),
}
pub struct CheckerContext<'a, R: Resolver + ?Sized> {
    owner: Owner<'a>,
    resolver: &'a R,
    profile: PackedU128,
}
impl<'a, R: Resolver + ?Sized> CheckerContext<'a, R> {
    pub fn live(
        frontend: &'a ColdFrontend,
        resolver: &'a R,
        profile: PackedU128,
    ) -> Result<Self, String> {
        require_source_owner(frontend.snapshot.tree.as_ref(), resolver)?;
        frontend
            .snapshot
            .tree
            .validate_checker_builtin_profile(profile)
            .map_err(|e| format!("checker profile cannot use compiled owner: {e:?}"))?;
        Ok(Self {
            owner: Owner::Live(frontend),
            resolver,
            profile,
        })
    }
    /// `host` MUST be the compiler session's existing body-query graph. Passing
    /// a second QueryDb, even with identical source bytes, cannot rebind archive.
    pub fn archived(
        archive: &'a BodyArchive,
        host: &dyn BodySyntaxQueries,
        resolver: &'a R,
        profile: PackedU128,
    ) -> Result<Self, String> {
        if !archive.uses_body_queries(host) {
            return Err("checker archive belongs to another compiler query graph".into());
        }
        require_source_owner(archive.tree(), resolver)?;
        archive
            .tree()
            .validate_checker_builtin_profile(profile)
            .map_err(|e| format!("checker profile cannot use compiled owner: {e:?}"))?;
        Ok(Self {
            owner: Owner::Archive(archive),
            resolver,
            profile,
        })
    }
    pub fn tree(&self) -> &SemanticTree {
        match self.owner {
            Owner::Live(frontend) => &frontend.snapshot.tree,
            Owner::Archive(archive) => archive.tree(),
        }
    }
    pub fn resolver(&self) -> &R {
        self.resolver
    }
    pub fn profile(&self) -> PackedU128 {
        self.profile
    }
    pub fn parent_live(
        &self,
        frontend: &ColdFrontend,
        body: &ParsedBody<'_>,
        severity: Severity,
    ) -> Result<Vec<Diagnostic>, String> {
        let Owner::Live(issued) = self.owner else {
            return Err("checker context is archive-owned".into());
        };
        if !std::ptr::eq(issued, frontend) {
            return Err("checker body belongs to another compiler frontend".into());
        }
        let view = BodyView::new(issued, body)?;
        checks_parent_call::check_issued_statement_body(
            self.tree(),
            body.occurrence().member,
            view.syntax(),
            self.resolver,
            Some(self.profile),
            severity,
        )
    }
    pub fn parent_archived(
        &self,
        body: &ArchivedBody<'_>,
        severity: Severity,
    ) -> Result<Vec<Diagnostic>, String> {
        let Owner::Archive(archive) = self.owner else {
            return Err("checker context is frontend-owned".into());
        };
        if !body.belongs_to(archive) {
            return Err("checker body belongs to another compiler archive".into());
        }
        checks_parent_call::check_issued_statement_body(
            self.tree(),
            body.occurrence().member,
            body.statement_body(),
            self.resolver,
            Some(self.profile),
            severity,
        )
    }
    pub fn variable_visibility_archived(
        &self,
        policy: &crate::check_policy::CheckerPolicy,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<crate::checks_variable_visibility::Configured>, String> {
        let Owner::Archive(archive) = self.owner else {
            return Err("visibility context is not archive-owned".into());
        };
        crate::checks_variable_visibility::scan_with_checkpoint(
            archive,
            self.resolver,
            self.profile,
            policy,
            checkpoint,
        )
    }
    pub fn variable_visibility_archived_checked(
        &self,
        policy: &crate::check_policy::CheckerPolicy,
        checkpoint: impl FnMut() -> std::io::Result<()>,
    ) -> Result<
        Vec<crate::checks_variable_visibility::Configured>,
        crate::policy_body_demand::PolicyFailure,
    > {
        let Owner::Archive(archive) = self.owner else {
            return Err("visibility context is not archive-owned".into());
        };
        crate::checks_variable_visibility::scan_checked(
            archive,
            self.resolver,
            self.profile,
            policy,
            checkpoint,
        )
    }
    pub fn fields_archived(
        &self,
        body: &ArchivedBody<'_>,
        severity: Severity,
    ) -> Result<Vec<Diagnostic>, String> {
        let Owner::Archive(archive) = self.owner else {
            return Err("checker context is frontend-owned".into());
        };
        if !body.belongs_to(archive) {
            return Err("checker body belongs to another compiler archive".into());
        }
        crate::checks_field_static::archived(archive, body, self.resolver, self.profile, severity)
    }
    pub fn implicit_new_live(
        &self,
        frontend: &ColdFrontend,
        body: &ParsedBody<'_>,
        severity: Severity,
    ) -> Result<Vec<Diagnostic>, String> {
        let Owner::Live(issued) = self.owner else {
            return Err("checker context is archive-owned".into());
        };
        if !std::ptr::eq(issued, frontend) {
            return Err("checker body belongs to another compiler frontend".into());
        }
        crate::checks_implicit_new::check(issued, body, self.resolver, self.profile, severity)
    }
    pub fn implicit_new_archived(
        &self,
        body: &ArchivedBody<'_>,
        severity: Severity,
    ) -> Result<Vec<Diagnostic>, String> {
        let Owner::Archive(archive) = self.owner else {
            return Err("checker context is frontend-owned".into());
        };
        if !body.belongs_to(archive) {
            return Err("checker body belongs to another compiler archive".into());
        }
        crate::checks_implicit_new::archived(archive, body, self.resolver, self.profile, severity)
    }
    pub fn proc_static_archived(
        &self,
        body: &ArchivedBody<'_>,
        severity: Severity,
    ) -> Result<Vec<Diagnostic>, String> {
        let Owner::Archive(archive) = self.owner else {
            return Err("checker context is frontend-owned".into());
        };
        if !body.belongs_to(archive) {
            return Err("checker body belongs to another compiler archive".into());
        }
        crate::checks_proc_static::archived(archive, body, self.resolver, self.profile, severity)
    }
    pub fn variables_archived(
        &self,
        body: &ArchivedBody<'_>,
        enabled: bool,
    ) -> Result<Vec<Diagnostic>, String> {
        let Owner::Archive(archive) = self.owner else {
            return Err("checker context is frontend-owned".into());
        };
        if !body.belongs_to(archive) {
            return Err("checker body belongs to another compiler archive".into());
        }
        crate::checks_undefined_variable::archived(
            archive,
            body,
            self.resolver,
            self.profile,
            enabled,
        )
    }
    pub fn undefined_archived(
        &self,
        body: &ArchivedBody<'_>,
        enabled: bool,
    ) -> Result<Vec<Diagnostic>, String> {
        let Owner::Archive(archive) = self.owner else {
            return Err("checker context is frontend-owned".into());
        };
        if !body.belongs_to(archive) {
            return Err("checker body belongs to another compiler archive".into());
        }
        crate::checks_undefined_proc::archived(archive, body, self.resolver, self.profile, enabled)
    }
}

fn require_source_owner(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
) -> Result<(), String> {
    // This is exact issuance, never equal answers, equal source bytes or a
    // shared answer-world hash. Compare only during both immutable borrows;
    // never persist or dereference the opaque compiler-owner address.
    if resolver.source_owner() != Some(std::ptr::from_ref(tree).cast()) {
        return Err("checker resolver lacks this exact compiled source owner provenance".into());
    }
    Ok(())
}
