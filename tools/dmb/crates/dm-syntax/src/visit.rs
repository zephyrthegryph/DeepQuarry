//! Borrowed, deterministic traversal of the shared typed statement model.
use crate::{
    Expr, ExprKind, ForControl, ForInitializer, Statement, StatementKind, StatementMask,
    StatementView, SwitchAlternative,
};
#[cfg(test)]
#[path = "visit_tests.rs"]
mod tests;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NodeStep {
    Statement(usize),
    Branch(usize),
    Expression(usize),
    Child(usize),
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum VisitDecision {
    Descend,
    Skip,
    Stop,
}
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct VisitReport {
    pub statements: usize,
    pub expressions: usize,
    pub unsupported_statements: usize,
    pub stopped: bool,
}
/// Paths are coordinates within this particular typed tree, not persistent IDs.
/// Callbacks borrow the original nodes. No nodes or source strings are cloned.
pub trait TypedVisitor {
    fn statement(&mut self, _node: &Statement, _path: &[NodeStep]) -> VisitDecision {
        VisitDecision::Descend
    }
    fn expression(&mut self, _node: &Expr, _path: &[NodeStep]) -> VisitDecision {
        VisitDecision::Descend
    }
    /// Balanced for every corresponding enter callback, including Skip/Stop.
    fn leave_statement(&mut self, _node: &Statement, _path: &[NodeStep]) {}
    fn leave_expression(&mut self, _node: &Expr, _path: &[NodeStep]) {}
    fn enter_branch(&mut self, _owner: &Statement, _index: usize, _path: &[NodeStep]) {}
    fn leave_branch(&mut self, _owner: &Statement, _index: usize, _path: &[NodeStep]) {}
}
pub fn visit_statements(statements: &[Statement], visitor: &mut impl TypedVisitor) -> VisitReport {
    visit_statement_view(StatementView::all(statements), visitor)
}
pub fn visit_statement_view(
    view: StatementView<'_>,
    visitor: &mut impl TypedVisitor,
) -> VisitReport {
    let mut walk = Walk {
        visitor,
        mask: view.mask(),
        path: Vec::new(),
        report: VisitReport::default(),
    };
    walk.statements(view.statements());
    walk.report
}
pub fn visit_expression(expression: &Expr, visitor: &mut impl TypedVisitor) -> VisitReport {
    let mut walk = Walk {
        visitor,
        mask: None,
        path: Vec::new(),
        report: VisitReport::default(),
    };
    walk.expression(expression);
    walk.report
}
/// One authoritative child-index convention for visitors and typed-node recipes.
pub fn for_each_expression_child<'a>(node: &'a Expr, mut visit: impl FnMut(usize, &'a Expr)) {
    match &node.kind {
        ExprKind::Ident(_) | ExprKind::Literal(_) | ExprKind::TypePath(_) => {}
        ExprKind::Unary { value, .. }
        | ExprKind::TypeFilter { value, .. }
        | ExprKind::Group(value) => visit(0, value),
        ExprKind::Member { object, .. }
        | ExprKind::StaticMember { object, .. }
        | ExprKind::SafeMember { object, .. } => visit(0, object),
        ExprKind::Binary { lhs, rhs, .. } => {
            visit(0, lhs);
            visit(1, rhs);
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            visit(0, object);
            visit(1, index);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            visit(0, condition);
            visit(1, then_value);
            visit(2, else_value);
        }
        ExprKind::Call { callee, args } => {
            visit(0, callee);
            for (index, arg) in args.iter().enumerate() {
                visit(index + 1, arg);
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            visit(0, object);
            for (index, (_, value)) in fields.iter().enumerate() {
                visit(index + 1, value);
            }
        }
    }
}
struct Walk<'a, V> {
    visitor: &'a mut V,
    mask: Option<&'a StatementMask>,
    path: Vec<NodeStep>,
    report: VisitReport,
}
impl<V: TypedVisitor> Walk<'_, V> {
    fn statements(&mut self, statements: &[Statement]) {
        for (index, statement) in statements.iter().enumerate() {
            if self.report.stopped {
                break;
            }
            if self.mask.is_some_and(|mask| !mask.visible(statement)) {
                continue;
            }
            self.path.push(NodeStep::Statement(index));
            self.statement(statement);
            self.path.pop();
        }
    }
    fn branch(&mut self, index: usize, statements: &[Statement], owner: &Statement) {
        if self.report.stopped {
            return;
        }
        self.path.push(NodeStep::Branch(index));
        self.visitor.enter_branch(owner, index, &self.path);
        self.statements(statements);
        self.visitor.leave_branch(owner, index, &self.path);
        self.path.pop();
    }
    fn root_expression(&mut self, index: usize, expression: &Expr) {
        self.path.push(NodeStep::Expression(index));
        self.expression(expression);
        self.path.pop();
    }
    fn expression(&mut self, expression: &Expr) {
        if self.report.stopped {
            return;
        }
        self.report.expressions += 1;
        match self.visitor.expression(expression, &self.path) {
            VisitDecision::Stop => {
                self.report.stopped = true;
                self.visitor.leave_expression(expression, &self.path);
                return;
            }
            VisitDecision::Skip => {
                self.visitor.leave_expression(expression, &self.path);
                return;
            }
            VisitDecision::Descend => {}
        }
        for_each_expression_child(expression, |index, child| {
            self.path.push(NodeStep::Child(index));
            self.expression(child);
            self.path.pop();
        });
        self.visitor.leave_expression(expression, &self.path);
    }
    fn statement(&mut self, statement: &Statement) {
        if self.report.stopped {
            return;
        }
        self.report.statements += 1;
        if matches!(&statement.kind, StatementKind::Unsupported) {
            self.report.unsupported_statements += 1;
        }
        match self.visitor.statement(statement, &self.path) {
            VisitDecision::Stop => {
                self.report.stopped = true;
                self.visitor.leave_statement(statement, &self.path);
                return;
            }
            VisitDecision::Skip => {
                self.visitor.leave_statement(statement, &self.path);
                return;
            }
            VisitDecision::Descend => {}
        }
        match &statement.kind {
            StatementKind::If {
                condition,
                then_branch,
                else_branch,
            } => {
                self.root_expression(0, condition);
                self.branch(0, then_branch, statement);
                self.branch(1, else_branch, statement);
            }
            StatementKind::While { condition, body } => {
                self.root_expression(0, condition);
                self.branch(0, body, statement);
            }
            StatementKind::DoWhile { body, condition } => {
                self.branch(0, body, statement);
                self.root_expression(0, condition);
            }
            StatementKind::Spawn { delay, body } => {
                if let Some(delay) = delay {
                    self.root_expression(0, delay);
                }
                self.branch(0, body, statement);
            }
            StatementKind::Set { value, .. } => self.root_expression(0, value),
            StatementKind::For { control, body } => {
                match control {
                    ForControl::All { .. } => {}
                    ForControl::Each { iterable, .. } | ForControl::Pair { iterable, .. } => {
                        self.root_expression(0, iterable)
                    }
                    ForControl::Range {
                        start, end, step, ..
                    } => {
                        self.root_expression(0, start);
                        self.root_expression(1, end);
                        if let Some(step) = step {
                            self.root_expression(2, step);
                        }
                    }
                    ForControl::CStyle {
                        initializer,
                        condition,
                        step,
                    } => {
                        match initializer {
                            Some(ForInitializer::Declare {
                                value: Some(value), ..
                            })
                            | Some(ForInitializer::Expr(value)) => self.root_expression(0, value),
                            _ => {}
                        }
                        if let Some(condition) = condition {
                            self.root_expression(1, condition);
                        }
                        if let Some(step) = step {
                            self.root_expression(2, step);
                        }
                    }
                }
                self.branch(0, body, statement);
            }
            StatementKind::Switch {
                selector,
                cases,
                else_branch,
            } => {
                self.root_expression(0, selector);
                for (index, case) in cases.iter().enumerate() {
                    if self.report.stopped {
                        break;
                    }
                    self.path.push(NodeStep::Branch(index));
                    self.visitor.enter_branch(statement, index, &self.path);
                    let mut expression = 0;
                    for alternative in &case.alternatives {
                        match alternative {
                            SwitchAlternative::Exact(value) => {
                                self.root_expression(expression, value);
                                expression += 1;
                            }
                            SwitchAlternative::Range(start, end) => {
                                self.root_expression(expression, start);
                                self.root_expression(expression + 1, end);
                                expression += 2;
                            }
                        }
                    }
                    self.statements(&case.body);
                    self.visitor.leave_branch(statement, index, &self.path);
                    self.path.pop();
                }
                self.branch(cases.len(), else_branch, statement);
            }
            StatementKind::Try {
                body, catch_body, ..
            } => {
                self.branch(0, body, statement);
                self.branch(1, catch_body, statement);
            }
            StatementKind::Label { body, .. } => self.branch(0, body, statement),
            StatementKind::Throw(value)
            | StatementKind::Call(value)
            | StatementKind::Expression(value) => self.root_expression(0, value),
            StatementKind::Return(value) | StatementKind::Var { value, .. } => {
                if let Some(value) = value {
                    self.root_expression(0, value);
                }
            }
            StatementKind::Assign { target, value, .. } => {
                self.root_expression(0, target);
                self.root_expression(1, value);
            }
            StatementKind::Goto(_)
            | StatementKind::Break
            | StatementKind::BreakLabel(_)
            | StatementKind::Continue
            | StatementKind::ContinueLabel(_)
            | StatementKind::Unsupported => {}
        }
        self.visitor.leave_statement(statement, &self.path);
    }
}
