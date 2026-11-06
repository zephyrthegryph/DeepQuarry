//! Body-local observations for the original image_dir_after_build policy.
//! No callable resolution, inferred runtime type, source report or model grant.
use crate::policy_body_demand::WorkspaceWork;
use crate::policy_body_observation::{self, BaseChainVisitor};
use dm_syntax::{Expr, ExprKind, ProjectedExprView, Span, Statement, StatementKind, VisitDecision};
use dm_tree::frontend::ArchivedBody;

#[derive(Clone, Copy, Eq, PartialEq)]
pub enum Phase {
    Initializers,
    Assignments,
}

pub enum Event<'a> {
    /// Only ordinary Var/Vars initializers. No C-style, range or catch binding.
    Initializer(&'a Statement),
    /// The target is for shape only. Use statement for the legacy source line,
    /// especially when a projected setting borrows a different backing root.
    Assignment { target: &'a Expr, operator: &'a str, statement: Span },
}

struct Observer<'a, W: WorkspaceWork, F> {
    phase: Phase,
    work: &'a mut W,
    emit: F,
    error: Option<W::Error>,
}

impl<W: WorkspaceWork, F: FnMut(&mut W, Event<'_>) -> Result<(), W::Error>> Observer<'_, W, F> {
    fn checked(&mut self, event: Option<Event<'_>>, decision: VisitDecision) -> VisitDecision {
        if self.error.is_some() {
            return VisitDecision::Stop;
        }
        if let Err(error) = self.work.checkpoint().and_then(|()| {
            event.map_or(Ok(()), |event| (self.emit)(self.work, event))
        }) {
            self.error = Some(error);
            return VisitDecision::Stop;
        }
        decision
    }

    fn expr(&mut self, node: &Expr, chain_child: bool, statement: Span) -> VisitDecision {
        if self.phase == Phase::Initializers {
            return VisitDecision::Skip;
        }
        let event = match &node.kind {
            ExprKind::Binary { op, lhs, .. }
                if !chain_child && crate::checker_original_expression_debug::original_assignment_operator(op) =>
                Some(Event::Assignment { target: lhs, operator: op, statement }),
            _ => None,
        };
        self.checked(event, VisitDecision::Descend)
    }
}

impl<W: WorkspaceWork, F: FnMut(&mut W, Event<'_>) -> Result<(), W::Error>> BaseChainVisitor for Observer<'_, W, F> {
    fn statement(&mut self, node: &Statement) -> VisitDecision {
        // A direct Assign is not represented by a Binary expression callback.
        // The existing walk separately exposes only its target/RHS children.
        let event = match &node.kind {
            StatementKind::Assign { target, op, .. } if self.phase == Phase::Assignments =>
                Some(Event::Assignment { target, operator: op, statement: node.span }),
            _ => None,
        };
        self.checked(event, VisitDecision::Descend)
    }

    fn after_variable(&mut self, node: &Statement) -> VisitDecision {
        if self.phase == Phase::Initializers {
            self.checked(Some(Event::Initializer(node)), VisitDecision::Descend)
        } else {
            VisitDecision::Descend
        }
    }

    fn expression(&mut self, _: &Expr, _: bool) -> VisitDecision {
        unreachable!("base policy emits the existing statement anchor")
    }

    fn projected_expression(&mut self, _: ProjectedExprView<'_>, _: bool) -> VisitDecision {
        unreachable!("base policy emits the existing projected statement anchor")
    }

    fn expression_at(&mut self, node: &Expr, chain_child: bool, statement: Span) -> VisitDecision {
        self.expr(node, chain_child, statement)
    }

    fn projected_expression_at(&mut self, node: ProjectedExprView<'_>, chain_child: bool, statement: Span) -> VisitDecision {
        self.expr(node.original(), chain_child, statement)
    }

    fn frame_capacity(&mut self, bytes: usize) -> Result<(), &'static str> {
        if let Err(error) = self.work.temporary(bytes) {
            self.error = Some(error);
            return Err("image dir projected body work refused");
        }
        Ok(())
    }

    fn frame_overflow(&mut self) -> &'static str {
        self.error = Some(self.work.overflow());
        "image dir projected body frame overflow"
    }

    fn frame_allocation_failed(&mut self) -> &'static str {
        self.error = Some(self.work.allocation_failed());
        "image dir projected body frame allocation refused"
    }
}

fn observe_view<W: WorkspaceWork>(
    view: dm_syntax::StatementView<'_>,
    phase: Phase,
    work: &mut W,
    emit: impl FnMut(&mut W, Event<'_>) -> Result<(), W::Error>,
) -> Result<(), W::Error> {
    work.checkpoint()?;
    let mut observer = Observer { phase, work, emit, error: None };
    let coverage = policy_body_observation::observe_base_chains(view, &mut observer);
    if let Some(error) = observer.error {
        return Err(error);
    }
    coverage?;
    observer.work.checkpoint()
}

fn require_body<W: WorkspaceWork>(body: &ArchivedBody<'_>, work: &mut W) -> Result<(), W::Error> {
    work.checkpoint()?;
    if !body.belongs_to(body.archive_owner())
        || body.archive_owner().source_mapping().initial_environment()
            != dm_preprocess::InitialEnvironment::OriginalChecker0290
        || !body.statement_body().original_literal_syntax_complete()
    {
        return Err("image dir requires a complete issued Original body".into());
    }
    Ok(())
}

/// Run first with Initializers to extend the complete seed scope, then with
/// Assignments after that scope settles. Both passes borrow the same body.
pub fn observe<W: WorkspaceWork>(
    body: &ArchivedBody<'_>,
    phase: Phase,
    work: &mut W,
    emit: impl FnMut(&mut W, Event<'_>) -> Result<(), W::Error>,
) -> Result<(), W::Error> {
    require_body(body, work)?;
    observe_view(body.statement_body().view(), phase, work, emit)
}

fn return_prefab<'a, E>(
    statements: &'a [Statement],
    mut checkpoint: impl FnMut() -> Result<(), E>,
) -> Result<Option<&'a str>, E> {
    for statement in statements {
        checkpoint()?;
        let (name, value) = match &statement.kind {
            StatementKind::Set { attribute, value, .. } => (attribute, value),
            StatementKind::ProjectedSet { attribute, value, .. } => (attribute, value.original_expression()),
            _ => continue,
        };
        if name != "SpacemanDMM_return_type" {
            continue;
        }
        let kind = match &value.kind {
            ExprKind::ObjectInitializer { object, .. } => &object.kind,
            kind => kind,
        };
        if let ExprKind::TypePath(path) = kind {
            return Ok(Some(path));
        }
    }
    Ok(None)
}

/// First matching direct statement on the already selected callable value.
/// This yields authored prefab spelling DATA, never declaration selection,
/// inherited lookup or a normalized type path.
pub fn first_return_prefab<'a, W: WorkspaceWork>(
    body: &'a ArchivedBody<'_>,
    work: &mut W,
) -> Result<Option<&'a str>, W::Error> {
    require_body(body, work)?;
    return_prefab(&body.statement_body().parsed().statements, || work.checkpoint())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::policy_body_demand::PolicyFailure;
    use std::{cell::Cell, io};

    struct Work;
    impl WorkspaceWork for Work {
        type Error = PolicyFailure;
        const CHECKED: bool = true;
        fn checkpoint(&mut self) -> Result<(), Self::Error> { Ok(()) }
        fn retain(&mut self, _: usize) -> Result<(), Self::Error> { Ok(()) }
        fn temporary(&mut self, _: usize) -> Result<(), Self::Error> { Ok(()) }
        fn overflow(&mut self) -> Self::Error { PolicyFailure::Operational(io::ErrorKind::OutOfMemory.into()) }
        fn allocation_failed(&mut self) -> Self::Error { self.overflow() }
        fn body<'a>(&mut self, _: &'a dm_tree::frontend::BodyArchive, _: usize)
            -> Result<ArchivedBody<'a>, Self::Error> { unreachable!("test exercises only AST observation") }
    }

    #[test]
    fn image_dir_body_preserves_ordinary_initializers_and_nested_assignment_anchors() {
        let text = concat!(
            "/proc/p(image/I)\n",
            "    I.dir *= 2\n",
            "    if (1)\n",
            "        var/first = image()\n",
            "    else if (call_me(I.dir -= 1))\n",
            "        var/second = first\n",
            "    for (var/skip = 1; skip; skip--)\n",
            "        var/third = second\n",
        );
        let ast = dm_syntax::parse(text);
        assert!(ast.diagnostics.is_empty());
        let body = dm_syntax::parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        let view = dm_syntax::StatementView::from_parsed(&body);
        let mut initializers = Vec::new();
        observe_view(view, Phase::Initializers, &mut Work, |_, event| {
            let Event::Initializer(node) = event else { panic!("initializer mode") };
            let StatementKind::Var { declaration, .. } = &node.kind else { panic!("ordinary Var") };
            initializers.push(declaration.clone());
            Ok(())
        }).unwrap();
        assert_eq!(initializers, ["var/first", "var/second", "var/third"]);

        let mut assignments = Vec::new();
        observe_view(dm_syntax::StatementView::from_parsed(&body), Phase::Assignments, &mut Work, |_, event| {
            let Event::Assignment { target, operator, statement } = event else { panic!("assignment mode") };
            assert!(matches!(&target.kind, ExprKind::Member { selector, .. } if selector == "dir"));
            let line = text[..statement.start].bytes().filter(|byte| *byte == b'\n').count() + 1;
            assignments.push((operator.to_owned(), line));
            Ok(())
        }).unwrap();
        assert_eq!(assignments, [("*=".to_owned(), 2), ("-=".to_owned(), 3)]);

        let calls = Cell::new(0);
        let failed = observe_view(dm_syntax::StatementView::from_parsed(&body), Phase::Assignments, &mut Work, |_, _| {
            calls.set(calls.get()+1);
            Err(PolicyFailure::Operational(io::Error::from_raw_os_error(1450)))
        });
        assert!(matches!(failed,Err(crate::policy_body_demand::PolicyFailure::Operational(error)) if error.raw_os_error()==Some(1450)));
        assert_eq!(calls.get(),1);
    }

    #[test]
    fn image_dir_return_prefab_uses_first_qualifying_direct_statement_after_prefix() {
        let text = concat!(
            "/proc/p()\n",
            "    set SpacemanDMM_return_type = (/turf)\n",
            "    if (1)\n",
            "        set SpacemanDMM_return_type = /atom\n",
            "    set SpacemanDMM_return_type = /image\n",
            "    set SpacemanDMM_return_type = /mutable_appearance\n",
        );
        let ast = dm_syntax::parse(text);
        assert!(ast.diagnostics.is_empty());
        let body = dm_syntax::parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert_eq!(return_prefab(&body.statements, || Ok::<(), ()>(())).unwrap(), Some("/image"));
    }
}
