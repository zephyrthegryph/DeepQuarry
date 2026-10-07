//! Capture procedure-shared declarations from typed bodies, before lowering.
//! Body spelling dictionaries are small local deltas, never copies of the tree.
use dm_ir::{
    InitializerValue, ProcedureIdentity, ProcedureStaticDeclaration, ProcedureStaticIdentity,
    SymbolTable,
};
use dm_syntax::{Item, Span, Statement, StatementKind};
use std::{collections::HashSet, sync::Arc};

/// Immutable lexical overlay. A miss is authoritative only for the exact
/// captured procedure inventory; other procedure contexts stay unsupported.
pub struct StaticResolver<'a, R: dm_ir::Resolver> {
    pub underlying: &'a R,
    procedures: HashSet<ProcedureIdentity>,
    declarations:
        std::collections::BTreeMap<ProcedureStaticIdentity, Arc<ProcedureStaticDeclaration>>,
}
impl<'a, R: dm_ir::Resolver> StaticResolver<'a, R> {
    pub fn new(
        underlying: &'a R,
        plans: &[(ProcedureIdentity, StaticPlan)],
    ) -> Result<Self, String> {
        Self::from_plans(
            underlying,
            plans.iter().map(|(identity, plan)| (*identity, plan)),
        )
    }
    pub fn from_plans<'p>(
        underlying: &'a R,
        plans: impl IntoIterator<Item = (ProcedureIdentity, &'p StaticPlan)>,
    ) -> Result<Self, String> {
        let mut procedures = HashSet::new();
        let mut declarations = std::collections::BTreeMap::new();
        for (procedure, plan) in plans {
            if plan.procedure != procedure {
                return Err("procedure static inventory context mismatch".into());
            }
            if !procedures.insert(procedure) {
                return Err("duplicate procedure static inventory".into());
            }
            for declaration in &plan.declarations {
                if declaration.identity.procedure != procedure {
                    return Err("static declaration belongs to another procedure".into());
                }
                if declarations
                    .insert(declaration.identity, Arc::new(declaration.clone()))
                    .is_some()
                {
                    return Err("duplicate structural static declaration".into());
                }
            }
        }
        Ok(Self {
            underlying,
            procedures,
            declarations,
        })
    }
}
impl<R: dm_ir::Resolver> dm_ir::Resolver for StaticResolver<'_, R> {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        match query {
            dm_ir::ResolveQuery::ProcedureStatic { procedure, name }
                if self.procedures.contains(&procedure) =>
            {
                self.declarations
                    .get(&ProcedureStaticIdentity { procedure, name })
                    .map(|declaration| {
                        dm_ir::ResolvedMeaning::ProcedureStatic(Arc::clone(declaration))
                    })
                    .unwrap_or(dm_ir::ResolvedMeaning::Missing)
            }
            dm_ir::ResolveQuery::ProcedureStatic { .. } => {
                dm_ir::ResolvedMeaning::Unsupported(query)
            }
            _ => self.underlying.resolve(query),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StaticOrigin {
    pub span: Span,
    pub header_span: Span,
    pub encounter: u32,
}
#[derive(Debug)]
pub struct StaticPlan {
    pub procedure: ProcedureIdentity,
    pub declarations: Vec<ProcedureStaticDeclaration>,
    pub origins: Vec<StaticOrigin>,
    pub symbols: SymbolTable,
    pub executable_body: Vec<Item>,
}
const STORED_LOCAL_QUALIFIERS: &[(&str, u32)] = &[("static", 1), ("const", 2), ("global", 8)];
fn stored_local_modifier(component: &str) -> u32 {
    STORED_LOCAL_QUALIFIERS.iter().find_map(|(name, bit)| (*name == component).then_some(*bit)).unwrap_or(0)
}
/// Negative-only eligibility check over already expanded source. The producer
/// requires one of these literal path components. Substrings in comments,
/// strings or longer identifiers deliberately remain candidates; no grammar or
/// syntax admission is performed here. Final executable parsing is mandatory.
pub fn may_contain_stored_declarations(expanded_source: &str) -> bool {
    STORED_LOCAL_QUALIFIERS.iter().any(|(name, _)| expanded_source.contains(name))
}
pub fn capture(procedure: ProcedureIdentity, body: &[Item]) -> Result<StaticPlan, String> {
    let mut plan = capture_declarations(procedure, body)?;
    let removed: HashSet<_> = plan
        .origins
        .iter()
        .map(|origin| (origin.header_span.start, origin.header_span.end))
        .collect();
    fn filter(items: &[Item], removed: &HashSet<(usize, usize)>) -> Vec<Item> {
        items
            .iter()
            .filter(|item| !removed.contains(&(item.header_span.start, item.header_span.end)))
            .map(|item| Item {
                kind: item.kind,
                header: item.header.clone(),
                span: item.span,
                header_span: item.header_span,
                indent: item.indent,
                children: filter(&item.children, removed),
            })
            .collect()
    }
    plan.executable_body = filter(body, &removed);
    Ok(plan)
}

/// Capture the same owned startup facts and source origins as [`capture`],
/// without copying executable items. `executable_body` is empty; callers that
/// need a filtered body must use `capture`. Neither path changes the input AST.
pub fn capture_declarations(
    procedure: ProcedureIdentity,
    body: &[Item],
) -> Result<StaticPlan, String> {
    let parsed = dm_syntax::parse_body_items(body);
    if !parsed.diagnostics.is_empty() {
        return Err(format!(
            "invalid procedure static body: {:?}",
            parsed.diagnostics
        ));
    }
    let mut plan = StaticPlan {
        procedure,
        declarations: Vec::new(),
        origins: Vec::new(),
        symbols: SymbolTable::default(),
        executable_body: Vec::new(),
    };
    let mut names = HashSet::new();
    walk(procedure, &parsed.statements, &mut plan, &mut names)?;
    fn captured_headers(items: &[Item], headers: &mut HashSet<(usize, usize)>) {
        for item in items {
            if item.header.trim_start().starts_with("var/") {
                headers.insert((item.header_span.start, item.header_span.end));
            }
            captured_headers(&item.children, headers);
        }
    }
    let mut headers = HashSet::new();
    captured_headers(body, &mut headers);
    if plan
        .origins
        .iter()
        .any(|origin| !headers.contains(&(origin.header_span.start, origin.header_span.end)))
    {
        return Err(
            "inline procedure static extraction requires an authoritative statement rewrite".into(),
        );
    }
    Ok(plan)
}
fn walk(
    procedure: ProcedureIdentity,
    statements: &[Statement],
    plan: &mut StaticPlan,
    names: &mut HashSet<dm_ir::SymbolId>,
) -> Result<(), String> {
    for statement in statements {
        match &statement.kind {
            StatementKind::Var { declaration, value } => {
                let path = declaration
                    .strip_prefix("var/")
                    .or_else(|| declaration.strip_prefix("var "))
                    .ok_or("unsupported variable declaration")?;
                let declaration_path = path.split('[').next().unwrap_or(path).trim();
                let components: Vec<_> = declaration_path
                    .split('/')
                    .filter(|part| !part.is_empty())
                    .collect();
                let Some((name, prefix)) = components.split_last() else {
                    return Err("missing static name".into());
                };
                let mut modifiers = 0;
                let mut types = Vec::new();
                for component in prefix {
                    match *component {
                        "tmp" => modifiers |= 4,
                        other => {
                            let storage = stored_local_modifier(other);
                            if storage != 0 { modifiers |= storage; }
                            else { types.push(other); }
                        }
                    }
                }
                if modifiers & 11 == 0 {
                    continue;
                }
                let name = plan
                    .symbols
                    .intern(name)
                    .map_err(|error| error.to_string())?;
                if !names.insert(name) {
                    return Err("same-name scoped procedure statics require a certified lexical slot policy".into());
                }
                let declared_type = if types.is_empty() {
                    None
                } else {
                    Some(
                        plan.symbols
                            .intern(&format!("/{}", types.join("/")))
                            .map_err(|error| error.to_string())?,
                    )
                };
                let array =
                    crate::procedure::parse_array(declaration, declared_type, &mut plan.symbols)?;
                let initializer = if let Some(value) = value {
                    let relative_start = value
                        .span
                        .start
                        .checked_sub(statement.header_span.start)
                        .ok_or("static expression outside header")?;
                    let relative_end = value
                        .span
                        .end
                        .checked_sub(statement.header_span.start)
                        .ok_or("static expression outside header")?;
                    let text = statement
                        .raw_header
                        .get(relative_start..relative_end)
                        .ok_or("static expression capture mismatch")?;
                    InitializerValue::Expression(crate::procedure::expression(
                        text,
                        &mut plan.symbols,
                    )?)
                } else if let Some(array) = &array {
                    InitializerValue::ArrayAllocation(Arc::clone(array))
                } else {
                    InitializerValue::NoAuthoredValue
                };
                let encounter =
                    u32::try_from(plan.origins.len()).map_err(|_| "too many procedure statics")?;
                plan.declarations.push(ProcedureStaticDeclaration {
                    identity: ProcedureStaticIdentity { procedure, name },
                    declared_type,
                    modifiers,
                    declared_array: array,
                    initializer,
                });
                plan.origins.push(StaticOrigin {
                    span: statement.span,
                    header_span: statement.header_span,
                    encounter,
                });
            }
            StatementKind::If {
                then_branch,
                else_branch,
                ..
            } => {
                walk(procedure, then_branch, plan, names)?;
                walk(procedure, else_branch, plan, names)?;
            }
            StatementKind::While { body, .. }
            | StatementKind::DoWhile { body, .. }
            | StatementKind::Spawn { body, .. }
            | StatementKind::Label { body, .. } => walk(procedure, body, plan, names)?,
            StatementKind::For { control, body } => {
                let declarations: Vec<&str> = match control {
                    dm_syntax::ForControl::All { declaration } => vec![declaration],
                    dm_syntax::ForControl::Each { binding, .. }
                    | dm_syntax::ForControl::Range { binding, .. } => vec![binding],
                    dm_syntax::ForControl::Pair {
                        key_binding,
                        value_binding,
                        ..
                    } => vec![key_binding, value_binding],
                    dm_syntax::ForControl::CStyle {
                        initializer: Some(dm_syntax::ForInitializer::Declare { declaration, .. }),
                        ..
                    } => vec![declaration],
                    _ => Vec::new(),
                };
                if declarations.iter().any(|declaration| {
                    declaration
                        .split('/')
                        .any(|part| stored_local_modifier(part) != 0)
                }) {
                    return Err("shared for-control declaration is not supported".into());
                }
                walk(procedure, body, plan, names)?;
            }
            StatementKind::Switch {
                cases, else_branch, ..
            } => {
                for case in cases {
                    walk(procedure, &case.body, plan, names)?;
                }
                walk(procedure, else_branch, plan, names)?;
            }
            StatementKind::Try {
                body, catch_body, ..
            } => {
                walk(procedure, body, plan, names)?;
                walk(procedure, catch_body, plan, names)?;
            }
            _ => (),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn identity() -> ProcedureIdentity {
        ProcedureIdentity {
            owner: dm_ir::SymbolId::of("/datum/x"),
            name: dm_ir::SymbolId::of("read"),
            verb: false,
            occurrence: 1,
        }
    }
    #[test]
    fn nested_statics_are_startup_facts_not_executable_declarations() {
        let source = "/datum/x/proc/read()\n    var/static/list/cache = list(1)\n    if(1)\n        var/static/count = 2\n    var/local = 3\n    return cache\n";
        let parsed = dm_syntax::parse(source);
        let proc = &parsed.items[0];
        let plan = capture(identity(), &proc.children).unwrap();
        assert_eq!(plan.declarations.len(), 2);
        assert_eq!(
            plan.symbols.text(plan.declarations[0].identity.name),
            Some("cache")
        );
        assert_eq!(
            plan.declarations[0].declared_type,
            Some(dm_ir::SymbolId::of("/list"))
        );
        assert_eq!(plan.origins[0].encounter, 0);
        assert_eq!(plan.origins[1].encounter, 1);
        assert_eq!(plan.executable_body.len(), 3);
        assert!(plan.executable_body[0].children.is_empty());
        assert!(plan.executable_body[1].header.contains("var/local"));
        assert!(matches!(
            plan.declarations[0].initializer,
            InitializerValue::Expression(_)
        ));
    }
    #[test]
    fn same_name_scoped_statics_fail_closed() {
        let parsed = dm_syntax::parse(
            "/proc/p()\n    var/static/x = 1\n    if(1)\n        var/static/x = 2\n",
        );
        assert!(capture(identity(), &parsed.items[0].children)
            .unwrap_err()
            .contains("same-name"));
    }
    #[test]
    fn declaration_capture_matches_full_capture_and_owns_its_facts() {
        let parsed = dm_syntax::parse(
            "/proc/p()\n    var/static/list/cache = list(1)\n    if(1)\n        var/const/count = 2\n        while(count)\n            count--\n    var/local = 3\n    return cache\n",
        );
        assert!(parsed.diagnostics.is_empty());
        let body = &parsed.items[0].children;
        let original = body.clone();
        let full = capture(identity(), body).unwrap();
        let declarations = capture_declarations(identity(), body).unwrap();
        assert_eq!(body, &original);
        assert_eq!(declarations.procedure, full.procedure);
        assert_eq!(declarations.declarations, full.declarations);
        assert_eq!(declarations.origins, full.origins);
        assert_eq!(declarations.symbols.ordered(), full.symbols.ordered());
        assert!(declarations.executable_body.is_empty());
        assert!(!full.executable_body.is_empty());
        drop(parsed);
        assert_eq!(
            declarations
                .symbols
                .text(declarations.declarations[0].identity.name),
            Some("cache")
        );
        assert_eq!(declarations.origins.len(), 2);
        assert!(matches!(
            declarations.declarations[0].initializer,
            InitializerValue::Expression(_)
        ));
    }
    #[test]
    fn declaration_capture_preserves_failure_admission() {
        for source in [
            "/proc/p()\n    var/static/x = 1\n    if(1)\n        var/static/x = 2\n",
            "/proc/p()\n    for(var/static/x = 1; x; x--)\n        return x\n",
        ] {
            let parsed = dm_syntax::parse(source);
            let body = &parsed.items[0].children;
            assert_eq!(
                capture(identity(), body).unwrap_err(),
                capture_declarations(identity(), body).unwrap_err()
            );
        }
    }
}
