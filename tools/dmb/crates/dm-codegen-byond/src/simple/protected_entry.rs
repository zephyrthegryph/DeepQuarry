//! Reject only parser-issued targets inside protected/iterator entry scopes.
use dm_syntax::{
    ForControl, NodeStep, Statement, StatementKind, StatementView, TypedVisitor, VisitDecision,
};
fn protected_branch(statement: &Statement, index: usize) -> bool {
    matches!(&statement.kind, StatementKind::Try { .. } if index == 0)
        || matches!(
            &statement.kind,
            StatementKind::For {
                control: ForControl::Each { .. } | ForControl::Pair { .. } | ForControl::All { .. },
                ..
            }
        )
}
pub(super) fn protected_entry_label(view: StatementView<'_>, target: &str) -> bool {
    struct Find<'a> {
        target: &'a str,
        depth: usize,
        found: bool,
    }
    impl TypedVisitor for Find<'_> {
        fn statement(&mut self, node: &Statement, _: &[NodeStep]) -> VisitDecision {
            if self.depth > 0
                && matches!(&node.kind, StatementKind::Label { name, .. } if name == self.target)
            {
                self.found = true;
                VisitDecision::Stop
            } else {
                VisitDecision::Descend
            }
        }
        fn enter_branch(&mut self, owner: &Statement, index: usize, _: &[NodeStep]) {
            self.depth += usize::from(protected_branch(owner, index));
        }
        fn leave_branch(&mut self, owner: &Statement, index: usize, _: &[NodeStep]) {
            self.depth -= usize::from(protected_branch(owner, index));
        }
    }
    let mut find = Find {
        target,
        depth: 0,
        found: false,
    };
    dm_syntax::visit_statement_view(view, &mut find);
    find.found
}

pub(super) fn protected_entry_error(statement: &str, name: &str) -> super::LowerError {
    let mut failure = super::error(statement, &format!("goto {name}: bad link"));
    failure.kind = super::LowerErrorKind::SourceError;
    failure
}
