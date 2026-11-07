//! Legacy untyped-policy observation order over the compiler's borrowed AST.
//!
//! This is deliberately not execution order. The independent legacy policy
//! observes every control header before any nested block. Its `if` arms are a
//! single statement, whereas native syntax retains each authored `else if` as
//! an `If` inside the else branch. No model or expression is cloned here.
//! Callers must first reject unsupported/malformed issued body syntax.

use dm_syntax::{
    for_each_expression_child, Expr, ExprKind, ForControl, ForInitializer, Span, Statement,
    StatementKind, SwitchAlternative,
};

trait Observer {
    fn if_condition_span(&mut self,_condition:&Expr,at:Span)->Result<Span,&'static str>{Ok(at)}
    fn after_variable(&mut self,_:&Statement) {}
    fn root_expression(&mut self,_:ExpressionObservation<'_>,_:Span) {}
    fn expression_chain(&mut self,e:&Expr,at:Span,_:bool){self.expression(e,at)}
    fn projected_expression_chain(&mut self,view:dm_syntax::ProjectedExprView<'_>,at:Span,root:bool,_:bool)->Result<(),&'static str>{self.projected_expression(view,at,root)}
    fn base_chain_requested(&self)->bool{false}
    fn frame_capacity(&mut self,_:usize)->Result<(),&'static str>{Ok(())}
    fn frame_overflow(&mut self)->&'static str{"original policy frame geometry overflow"}
    fn frame_allocation_failed(&mut self)->&'static str{"original policy frame allocation refused"}

    fn projected_expression(&mut self, _: dm_syntax::ProjectedExprView<'_>, _: Span, _: bool) -> Result<(), &'static str> {
        Err("projected setting RHS requires an explicit current-coordinate observer")
    }
    fn leave_projected_expression(&mut self, _: dm_syntax::ProjectedExprView<'_>) {}
    fn list_write_assignment(&mut self, _: &Expr, _: &str, _: &Expr, _: Span) {}
    fn statement(&mut self, _: &Statement) -> bool {
        true
    }
    fn stopped(&self) -> bool {
        false
    }
    fn descend_expression(&self) -> bool {
        true
    }
    fn expression(&mut self, _: &Expr, _: Span) {}
    fn implicit_list(&mut self, _: &dm_syntax::ImplicitListInitializer, _: Span) {}
    fn assignment(&mut self, _: &Expr, _: &Expr, _: Span) {}
    fn statement_assignment(&mut self, _: &Expr, _: &Expr, _: Span) {}
}
struct Assignments<'a, F>(&'a mut F);
struct CurrentAssignments<'a, F>(&'a mut F);
impl<F: FnMut(&Expr, &Expr, Span, Span)> Observer for CurrentAssignments<'_, F> {
    fn assignment(&mut self, lhs: &Expr, rhs: &Expr, at: Span) {
        self.0(lhs, rhs, at, lhs.span);
    }
    fn projected_expression(&mut self, view: dm_syntax::ProjectedExprView<'_>, at: Span, _: bool) -> Result<(), &'static str> {
        if let ExprKind::Binary { op, lhs, rhs } = &view.original().kind {
            if op == "=" {
                let target = view.current_span_of(lhs).ok_or("projected assignment target has no current span")?;
                self.0(lhs, rhs, at, target);
            }
        }
        Ok(())
    }
}
pub(crate) fn assignments_current(view:dm_syntax::StatementView<'_>,emit:&mut impl FnMut(&Expr,&Expr,Span,Span))->Result<(),&'static str>{match try_assignments_current(view,&mut(),&mut|_|Ok::<(),&'static str>(()),&mut|_,lhs,rhs,at,current|{emit(lhs,rhs,at,current);Ok(())}){Ok(())=>Ok(()),Err(PolicyVisitFailure::Callback(message))|Err(PolicyVisitFailure::Unsupported(message))=>Err(message)}}
/// Same all-assignment/current-coordinate callback order; no new traversal.
pub(crate) fn try_assignments_current<C,E>(view:dm_syntax::StatementView<'_>,control:&mut C,checkpoint:&mut impl FnMut(&mut C)->Result<(),E>,emit:&mut impl FnMut(&mut C,&Expr,&Expr,Span,Span)->Result<(),E>)->Result<(),PolicyVisitFailure<E>>{
 struct Controlled<'a,C,E,P,F>{control:&'a mut C,checkpoint:&'a mut P,emit:&'a mut F,error:Option<E>}
 impl<C,E,P:FnMut(&mut C)->Result<(),E>,F:FnMut(&mut C,&Expr,&Expr,Span,Span)->Result<(),E>> Observer for Controlled<'_,C,E,P,F>{
  fn stopped(&self)->bool{self.error.is_some()}
  fn statement(&mut self,_:&Statement)->bool{if self.error.is_some(){return false}if let Err(actual)=(self.checkpoint)(self.control){self.error=Some(actual);false}else{true}}
  fn expression(&mut self,_:&Expr,_:Span){if self.error.is_none(){if let Err(actual)=(self.checkpoint)(self.control){self.error=Some(actual)}}}
  fn assignment(&mut self,lhs:&Expr,rhs:&Expr,at:Span){if self.error.is_none(){if let Err(actual)=(self.checkpoint)(self.control).and_then(|()|(self.emit)(self.control,lhs,rhs,at,lhs.span)){self.error=Some(actual)}}}
  fn projected_expression(&mut self,view:dm_syntax::ProjectedExprView<'_>,at:Span,_:bool)->Result<(),&'static str>{if self.error.is_some(){return Ok(())}if let Err(actual)=(self.checkpoint)(self.control){self.error=Some(actual);return Ok(())}if let ExprKind::Binary{op,lhs,rhs}=&view.original().kind{if op=="="{let current=view.current_span_of(lhs).ok_or("projected assignment target has no current span")?;if let Err(actual)=(self.emit)(self.control,lhs,rhs,at,current){self.error=Some(actual)}}}Ok(())}
 }
 let mut visitor=Controlled{control,checkpoint,emit,error:None};let coverage=observe(view,&mut visitor);if let Some(actual)=visitor.error{return Err(PolicyVisitFailure::Callback(actual))}coverage.map_err(PolicyVisitFailure::Unsupported)
}
impl<F: FnMut(&Expr, &Expr, Span)> Observer for Assignments<'_, F> {
    fn assignment(&mut self, a: &Expr, b: &Expr, at: Span) {
        self.0(a, b, at);
    }
}
/// Explicit coordinate domain at policy leaf callbacks. `original()` borrows
/// shape/pointer identity only; source locations use current_span
/// or the separate current legacy statement anchor. This view does not mint
/// source authority; its caller is the already-issued native body observer.
#[derive(Clone, Copy)]
pub enum ExpressionObservation<'a> {
    Owned(&'a Expr),
    Projected(dm_syntax::ProjectedExprView<'a>),
}
impl<'a> ExpressionObservation<'a> {
    pub fn original(self) -> &'a Expr {
        match self { Self::Owned(e) => e, Self::Projected(v) => v.original() }
    }
    pub fn current_span(self) -> Span {
        match self { Self::Owned(e) => e.span, Self::Projected(v) => v.current_span() }
    }
}
struct CurrentExpressions<'a, F>(&'a mut F);
impl<F: FnMut(ExpressionObservation<'_>, Span)> Observer for CurrentExpressions<'_, F> {
    fn expression(&mut self, e: &Expr, at: Span) { self.0(ExpressionObservation::Owned(e), at); }
    fn projected_expression(&mut self, v: dm_syntax::ProjectedExprView<'_>, at: Span, _: bool) -> Result<(), &'static str> {
        self.0(ExpressionObservation::Projected(v), at);
        Ok(())
    }
}
pub(crate) fn expressions_current(view: dm_syntax::StatementView<'_>, emit: &mut impl FnMut(ExpressionObservation<'_>, Span)) -> Result<(), &'static str> {
    observe(view, &mut CurrentExpressions(emit))
}

/// Fallible consumer of the SAME original policy walk. This interface grants no
/// source authority; native callers must bind an actual issued StatementBody.
pub enum PolicyVisitFailure<E>{Unsupported(&'static str),Callback(E)}
pub fn try_policy_expressions<E>(
 view:dm_syntax::StatementView<'_>,checkpoint:&mut impl FnMut()->Result<(),E>,
 emit:&mut impl FnMut(ExpressionObservation<'_>,Span)->Result<(),E>,
)->Result<(),PolicyVisitFailure<E>>{
 struct Fallible<'a,E,P,F>{checkpoint:&'a mut P,emit:&'a mut F,error:Option<E>}
 impl<E,P:FnMut()->Result<(),E>,F:FnMut(ExpressionObservation<'_>,Span)->Result<(),E>> Observer for Fallible<'_,E,P,F>{
  fn stopped(&self)->bool{self.error.is_some()}
  fn statement(&mut self,_:&Statement)->bool{
   if self.error.is_some(){return false;}match(self.checkpoint)(){Ok(())=>true,Err(e)=>{self.error=Some(e);false}}
  }
  fn expression(&mut self,e:&Expr,at:Span){
   if self.error.is_none(){if let Err(e)=(self.checkpoint)().and_then(|()|(self.emit)(ExpressionObservation::Owned(e),at)){self.error=Some(e);}}
  }
  fn projected_expression(&mut self,v:dm_syntax::ProjectedExprView<'_>,at:Span,_:bool)->Result<(),&'static str>{
   if self.error.is_none(){if let Err(e)=(self.checkpoint)().and_then(|()|(self.emit)(ExpressionObservation::Projected(v),at)){self.error=Some(e);}}Ok(())
  }
 }
 let mut observer=Fallible{checkpoint,emit,error:None};let coverage=observe(view,&mut observer);
 if let Some(actual)=observer.error{return Err(PolicyVisitFailure::Callback(actual));}
 coverage.map_err(PolicyVisitFailure::Unsupported)
}
struct Expressions<'a, F>(&'a mut F);
impl<F: FnMut(&Expr, Span)> Observer for Expressions<'_, F> {
    fn expression(&mut self, node: &Expr, at: Span) {
        self.0(node, at);
    }
}
/// The same original statement-root assignment observer, with fallible control.
/// Traversal and projected-setting identity stay on the issued StatementView.
pub(crate) fn try_statement_assignments_current<C,E>(view:dm_syntax::StatementView<'_>,control:&mut C,checkpoint:&mut impl FnMut(&mut C)->Result<(),E>,emit:&mut impl FnMut(&mut C,&Expr,&Expr,Span,Span)->Result<(),E>)->Result<(),PolicyVisitFailure<E>>{
 struct Controlled<'a,C,E,P,F>{control:&'a mut C,checkpoint:&'a mut P,emit:&'a mut F,error:Option<E>}
 impl<C,E,P:FnMut(&mut C)->Result<(),E>,F:FnMut(&mut C,&Expr,&Expr,Span,Span)->Result<(),E>> Observer for Controlled<'_,C,E,P,F>{
  fn stopped(&self)->bool{self.error.is_some()}
  fn statement(&mut self,_:&Statement)->bool{if self.error.is_some(){return false}match(self.checkpoint)(self.control){Ok(())=>true,Err(actual)=>{self.error=Some(actual);false}}}
  fn expression(&mut self,_:&Expr,_:Span){if self.error.is_none(){if let Err(actual)=(self.checkpoint)(self.control){self.error=Some(actual)}}}
  fn statement_assignment(&mut self,lhs:&Expr,rhs:&Expr,at:Span){if self.error.is_none(){if let Err(actual)=(self.checkpoint)(self.control).and_then(|()|(self.emit)(self.control,lhs,rhs,at,lhs.span)){self.error=Some(actual)}}}
  fn projected_expression(&mut self,view:dm_syntax::ProjectedExprView<'_>,at:Span,is_root:bool)->Result<(),&'static str>{
   if self.error.is_some(){return Ok(())}if let Err(actual)=(self.checkpoint)(self.control){self.error=Some(actual);return Ok(())}
   if is_root{if let ExprKind::Binary{op,lhs,rhs}=&view.original().kind{if op=="="{let target=view.current_span_of(lhs).ok_or("projected statement target has no current span")?;if let Err(actual)=(self.emit)(self.control,lhs,rhs,at,target){self.error=Some(actual)}}}}Ok(())
  }
 }
 let mut observer=Controlled{control,checkpoint,emit,error:None};let coverage=observe(view,&mut observer);if let Some(actual)=observer.error{return Err(PolicyVisitFailure::Callback(actual))}coverage.map_err(PolicyVisitFailure::Unsupported)
}
pub(crate) fn statement_assignments_current(view:dm_syntax::StatementView<'_>,emit:&mut impl FnMut(&Expr,&Expr,Span,Span))->Result<(),&'static str>{
 match try_statement_assignments_current(view,&mut(),&mut|_|Ok::<(),&'static str>(()),&mut|_,lhs,rhs,at,target|{emit(lhs,rhs,at,target);Ok(())}){Ok(())=>Ok(()),Err(PolicyVisitFailure::Unsupported(message))|Err(PolicyVisitFailure::Callback(message))=>Err(message)}
}
struct StatementAssignments<'a, F>(&'a mut F);
impl<F: FnMut(&Expr, &Expr, Span)> Observer for StatementAssignments<'_, F> {
    fn statement_assignment(&mut self, a: &Expr, b: &Expr, at: Span) {
        self.0(a, b, at);
    }
}
pub(crate) fn statement_assignments(
    view: dm_syntax::StatementView<'_>,
    emit: &mut impl FnMut(&Expr, &Expr, Span),
) -> Result<(), &'static str> {
    observe(view, &mut StatementAssignments(emit))
}
pub(crate) fn assignments(
    view: dm_syntax::StatementView<'_>,
    emit: &mut impl FnMut(&Expr, &Expr, Span),
) -> Result<(), &'static str> {
    observe(view, &mut Assignments(emit))
}
pub(crate) fn expressions(
    view: dm_syntax::StatementView<'_>,
    emit: &mut impl FnMut(&Expr, Span),
) -> Result<(), &'static str> {
    observe(view, &mut Expressions(emit))
}
pub(crate) struct StoredEvents<'a, E, A> {
    pub expression: &'a mut E,
    pub assignment: &'a mut A,
}
impl<E: FnMut(&Expr, Span), A: FnMut(&Expr, &str, &Expr, Span)> Observer
    for StoredEvents<'_, E, A>
{
    fn expression(&mut self, node: &Expr, at: Span) {
        (self.expression)(node, at)
    }
    fn list_write_assignment(&mut self, a: &Expr, op: &str, b: &Expr, at: Span) {
        (self.assignment)(a, op, b, at)
    }
}
/// No parser or new traversal: SAME original stored-events walk, typed callbacks.
pub(crate) fn try_stored_events_current<C,E>(view:dm_syntax::StatementView<'_>,control:&mut C,checkpoint:&mut impl FnMut(&mut C)->Result<(),E>,expression:&mut impl FnMut(&mut C,ExpressionObservation<'_>,Span)->Result<(),E>,assignment:&mut impl FnMut(&mut C,&Expr,&str,&Expr,Span)->Result<(),E>)->Result<(),PolicyVisitFailure<E>>{
 struct Checked<'a,C,E,P,X,A>{control:&'a mut C,poll:&'a mut P,expression:&'a mut X,assignment:&'a mut A,error:Option<E>}
 impl<C,E,P:FnMut(&mut C)->Result<(),E>,X:FnMut(&mut C,ExpressionObservation<'_>,Span)->Result<(),E>,A:FnMut(&mut C,&Expr,&str,&Expr,Span)->Result<(),E>> Observer for Checked<'_,C,E,P,X,A>{
 fn stopped(&self)->bool{self.error.is_some()}fn statement(&mut self,_:&Statement)->bool{if self.error.is_some(){return false}match(self.poll)(self.control){Ok(())=>true,Err(e)=>{self.error=Some(e);false}}}
 fn expression(&mut self,e:&Expr,at:Span){if self.error.is_none(){if let Err(e)=(self.poll)(self.control).and_then(|()|(self.expression)(self.control,ExpressionObservation::Owned(e),at)){self.error=Some(e)}}}
 fn list_write_assignment(&mut self,lhs:&Expr,op:&str,rhs:&Expr,at:Span){if self.error.is_none(){if let Err(e)=(self.poll)(self.control).and_then(|()|(self.assignment)(self.control,lhs,op,rhs,at)){self.error=Some(e)}}}
 fn projected_expression(&mut self,v:dm_syntax::ProjectedExprView<'_>,at:Span,_:bool)->Result<(),&'static str>{if self.error.is_some(){return Ok(())}if let Err(e)=(self.poll)(self.control).and_then(|()|(self.expression)(self.control,ExpressionObservation::Projected(v),at)){self.error=Some(e);return Ok(())}if let ExprKind::Binary{op,lhs,rhs}=&v.original().kind{if matches!(op.as_str(),"="|"+="|"|="|"||="){self.list_write_assignment(lhs,op,rhs,at)}}Ok(())}
 }
 let mut checked=Checked{control,poll:checkpoint,expression,assignment,error:None};let result=observe(view,&mut checked);if let Some(actual)=checked.error{return Err(PolicyVisitFailure::Callback(actual))}result.map_err(PolicyVisitFailure::Unsupported)
}

struct CurrentStoredEvents<'a, E, A> { expression: &'a mut E, assignment: &'a mut A }
impl<E: FnMut(ExpressionObservation<'_>, Span), A: FnMut(&Expr, &str, &Expr, Span)> Observer for CurrentStoredEvents<'_, E, A> {
    fn expression(&mut self, e: &Expr, at: Span) { (self.expression)(ExpressionObservation::Owned(e), at); }
    fn list_write_assignment(&mut self, lhs: &Expr, op: &str, rhs: &Expr, at: Span) { (self.assignment)(lhs, op, rhs, at); }
    fn projected_expression(&mut self, v: dm_syntax::ProjectedExprView<'_>, at: Span, _: bool) -> Result<(), &'static str> {
        (self.expression)(ExpressionObservation::Projected(v), at);
        // Same original event order: expression callback, then supported list
        // write callback, then children. Assignment nodes remain original shape;
        // the separate `at` is the actual current legacy statement coordinate.
        if let ExprKind::Binary { op, lhs, rhs } = &v.original().kind {
            if matches!(op.as_str(), "=" | "+=" | "|=" | "||=") { (self.assignment)(lhs, op, rhs, at); }
        }
        Ok(())
    }
}
pub(crate) fn stored_events_current(
    view: dm_syntax::StatementView<'_>,
    expression: &mut impl FnMut(ExpressionObservation<'_>, Span),
    assignment: &mut impl FnMut(&Expr, &str, &Expr, Span),
) -> Result<(), &'static str> { observe(view, &mut CurrentStoredEvents { expression, assignment }) }
pub(crate) fn stored_events(
    view: dm_syntax::StatementView<'_>,
    expression: &mut impl FnMut(&Expr, Span),
    assignment: &mut impl FnMut(&Expr, &str, &Expr, Span),
) -> Result<(), &'static str> {
    observe(
        view,
        &mut StoredEvents {
            expression,
            assignment,
        },
    )
}

/// The three existing value-policy visitors use only statement/expression
/// hooks (no lexical paths or branch hooks). Preserve those exact hooks over
/// original old-policy observation order, including implicit array children.
pub(crate) fn visit_value_policy(
    view: dm_syntax::StatementView<'_>,
    visitor: &mut impl dm_syntax::TypedVisitor,
) -> Result<(), &'static str> {
    struct Adapter<'a, V> {
        visitor: &'a mut V,
        stopped: bool,
        descend: bool,
    }
    impl<V: dm_syntax::TypedVisitor> Observer for Adapter<'_, V> {
        fn projected_expression(&mut self, view: dm_syntax::ProjectedExprView<'_>, _: Span, _: bool) -> Result<(), &'static str> {
            let decision = self.visitor.projected_expression(view, &[]);
            self.stopped |= decision == dm_syntax::VisitDecision::Stop;
            self.descend = decision == dm_syntax::VisitDecision::Descend;
            Ok(())
        }
        fn leave_projected_expression(&mut self, view: dm_syntax::ProjectedExprView<'_>) {
            self.visitor.leave_projected_expression(view, &[]);
        }
        fn statement(&mut self, s: &Statement) -> bool {
            let decision = self.visitor.statement(s, &[]);
            self.stopped |= decision == dm_syntax::VisitDecision::Stop;
            decision == dm_syntax::VisitDecision::Descend
        }
        fn expression(&mut self, e: &Expr, _: Span) {
            let decision = self.visitor.expression(e, &[]);
            self.stopped |= decision == dm_syntax::VisitDecision::Stop;
            self.descend = decision == dm_syntax::VisitDecision::Descend;
        }
        fn stopped(&self) -> bool {
            self.stopped
        }
        fn descend_expression(&self) -> bool {
            self.descend
        }
    }
    observe(
        view,
        &mut Adapter {
            visitor,
            stopped: false,
            descend: true,
        },
    )
}
 struct BasePolicyAdapter<'a,V>{visitor:&'a mut V,stopped:bool,descend:bool}
 impl<V:crate::policy_body_observation::BaseChainVisitor>Observer for BasePolicyAdapter<'_,V>{
  fn base_chain_requested(&self)->bool{true}
  fn if_condition_span(&mut self,condition:&Expr,at:Span)->Result<Span,&'static str>{self.visitor.if_condition_span(condition,at)}
  fn frame_capacity(&mut self,n:usize)->Result<(),&'static str>{self.visitor.frame_capacity(n)}
  fn frame_overflow(&mut self)->&'static str{self.visitor.frame_overflow()}
  fn frame_allocation_failed(&mut self)->&'static str{self.visitor.frame_allocation_failed()}
  fn statement(&mut self,s:&Statement)->bool{let d=self.visitor.statement(s);self.stopped|=d==dm_syntax::VisitDecision::Stop;d==dm_syntax::VisitDecision::Descend}
  fn after_variable(&mut self,s:&Statement){if !self.stopped{let d=self.visitor.after_variable(s);self.stopped|=d==dm_syntax::VisitDecision::Stop;}}
  fn expression_chain(&mut self,e:&Expr,at:Span,child:bool){let d=self.visitor.expression_at(e,child,at);self.stopped|=d==dm_syntax::VisitDecision::Stop;self.descend=d==dm_syntax::VisitDecision::Descend;}
  fn projected_expression_chain(&mut self,e:dm_syntax::ProjectedExprView<'_>,at:Span,_:bool,child:bool)->Result<(),&'static str>{let d=self.visitor.projected_expression_at(e,child,at);self.stopped|=d==dm_syntax::VisitDecision::Stop;self.descend=d==dm_syntax::VisitDecision::Descend;Ok(())}
  fn stopped(&self)->bool{self.stopped}fn descend_expression(&self)->bool{self.descend}
 }
pub(crate) fn visit_base_policy(view:dm_syntax::StatementView<'_>,visitor:&mut impl crate::policy_body_observation::BaseChainVisitor)->Result<(),&'static str>{observe(view,&mut BasePolicyAdapter{visitor,stopped:false,descend:true})}
pub(crate) fn visit_base_expression(node:&Expr,at:Span,visitor:&mut impl crate::policy_body_observation::BaseChainVisitor)->Result<(),&'static str>{let mut adapter=BasePolicyAdapter{visitor,stopped:false,descend:true};expression_tree(node,at,&mut adapter);Ok(())}
pub(crate) fn visit_projected_base_expression(root:&dm_syntax::SettingExpression,at:Span,visitor:&mut impl crate::policy_body_observation::BaseChainVisitor)->Result<(),&'static str>{let mut adapter=BasePolicyAdapter{visitor,stopped:false,descend:true};visit_projected_policy(root,at,&mut adapter)}

fn base_chain_child(node:&Expr)->Option<&Expr>{match &node.kind{ExprKind::Unary{op,value}if op!="new"=>Some(value),ExprKind::Member{object,..}|ExprKind::StaticMember{object,..}|ExprKind::SafeMember{object,..}|ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>Some(object),ExprKind::Call{callee,..}=>Some(callee),_=>None}}
fn observe(
    view: dm_syntax::StatementView<'_>,
    emit: &mut impl Observer,
) -> Result<(), &'static str> {
    let ledger = view
        .local_variables()
        .ok_or("policy observation requires original local ledger")?;
    ledger.entries()?;
    let mut walk = PolicyWalk {
        ledger,
        error: None,
        engine_order:false,
    };
    walk.walk(view.statements(), emit);
    walk.error.map_or(Ok(()), Err)
}
struct PolicyWalk<'a> {
    engine_order:bool,
    ledger: &'a dm_syntax::LocalVariableLedger,
    error: Option<&'static str>,
}
impl PolicyWalk<'_> {
    fn projected(&mut self, root: &dm_syntax::SettingExpression, at: Span, emit: &mut impl Observer) {
        if let Err(error)=visit_projected_policy(root,at,emit){self.error=Some(error);}
    }
    fn walk(&mut self, statements: &[Statement], emit: &mut impl Observer) {
        for statement in statements {
            if self.error.is_some() || emit.stopped() {
                return;
            }
            self.statement_walk(statement, emit);
        }
    }
    fn implicit(&mut self, statement: &Statement, at: Span, emit: &mut impl Observer) {
        let Ok(entries) = self.ledger.in_span(statement.header_span) else {
            self.error = Some("original local ledger unavailable");
            return;
        };
        let mut facts = entries.iter();
        let Some(fact) = facts.next() else {
            self.error = Some("original implicit initializer declaration missing");
            return;
        };
        if facts.next().is_some() {
            self.error = Some("original implicit initializer declaration ambiguous");
            return;
        }
        if let Some(root) = fact.implicit_list_initializer() {
            emit.implicit_list(root, at);
            // Old stmt_exprs holds a synthetic New/list ROOT; dimensions are
            // nested arguments, never fabricated top-level assignments.
            for dimension in root.dimensions.iter() {
                emit.root_expression(ExpressionObservation::Owned(dimension),at);
                expression_tree(dimension, at, emit);
            }
        }
    }
}

// One projected expression traversal, shared by whole-body observation and
// a selected statement expression loan. No observer reparses/copies a root.
fn visit_projected_policy(root:&dm_syntax::SettingExpression,at:Span,emit:&mut impl Observer)->Result<(),&'static str>{let chains=emit.base_chain_requested().then(Vec::new);let mut projected=ProjectedPolicy{emit,at,frames:Vec::new(),chains,error:None};dm_syntax::visit_projected_expression(root,&mut projected);projected.error.map_or(Ok(()),Err)}

// Keep the OLD policy's expression order, not the executable visitor order.
// In particular proc-reference calls discard arguments, and new visits only
// arguments (not its target or its intermediate call node). All callbacks
// still receive genuine views issued by the one canonical syntax walker.
#[derive(Clone, Copy)]
enum ProjectedChildren { Ordinary, ProcReference, New, NewCall }
struct ProjectedPolicy<'a, O> {
    emit: &'a mut O,
    at: Span,
    frames: Vec<(ProjectedChildren, bool)>,
    chains:Option<Vec<Option<usize>>>,
    error: Option<&'static str>,
}
impl<O: Observer> dm_syntax::TypedVisitor for ProjectedPolicy<'_, O> {
    fn projected_expression(&mut self, view: dm_syntax::ProjectedExprView<'_>, path: &[dm_syntax::NodeStep]) -> dm_syntax::VisitDecision {
        use dm_syntax::{NodeStep, VisitDecision};
        let child = path.last().and_then(|step| match step { NodeStep::Child(i) => Some(*i), _ => None });
        let parent = self.frames.last().map(|frame| frame.0);
        let mut emitted = true;
        let mut force = None;
        let skip = match (parent, child) {
            (Some(ProjectedChildren::ProcReference), Some(i)) => i != 0,
            (Some(ProjectedChildren::New), Some(0)) => {
                if matches!(&view.original().kind, ExprKind::Call { .. }) {
                    emitted = false;
                    force = Some(ProjectedChildren::NewCall);
                    false
                } else { true }
            }
            (Some(ProjectedChildren::NewCall), Some(i)) => i == 0,
            _ => false,
        };
        let mode = force.unwrap_or_else(|| match &view.original().kind {
            ExprKind::Unary { op, .. } if op == "new" => ProjectedChildren::New,
            ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::StaticMember { .. }) => ProjectedChildren::ProcReference,
            _ => ProjectedChildren::Ordinary,
        });
        let chain_child=self.chains.as_ref().and_then(|frames|frames.last()).copied().flatten().is_some_and(|parent_child|parent_child==view.original()as *const Expr as usize);
        if let Some(chains)=&mut self.chains{
         if self.frames.len()==self.frames.capacity()||chains.len()==chains.capacity(){
          let target=self.frames.len().checked_mul(2).unwrap_or(usize::MAX).max(4);
          let bytes=self.frames.capacity().checked_add(target).and_then(|n|n.checked_mul(std::mem::size_of::<(ProjectedChildren,bool)>())).and_then(|n|chains.capacity().checked_add(target)?.checked_mul(std::mem::size_of::<Option<usize>>())?.checked_add(n));
          let Some(bytes)=bytes else{self.error=Some(self.emit.frame_overflow());return VisitDecision::Stop};
          if let Err(error)=self.emit.frame_capacity(bytes){self.error=Some(error);return VisitDecision::Stop}
          if self.frames.try_reserve_exact(target-self.frames.len()).is_err()||chains.try_reserve_exact(target-chains.len()).is_err(){self.error=Some(self.emit.frame_allocation_failed());return VisitDecision::Stop}
          if self.frames.capacity()>target||chains.capacity()>target{self.error=Some(self.emit.frame_allocation_failed());return VisitDecision::Stop}
         }
         chains.push(base_chain_child(view.original()).map(|child|child as *const Expr as usize));
        }
        self.frames.push((mode, emitted && !skip));
        if skip { return VisitDecision::Skip; }
        if emitted {
            if self.frames.len()==1{self.emit.root_expression(ExpressionObservation::Projected(view),self.at);if self.emit.stopped(){return VisitDecision::Stop;}}
            if let Err(error) = self.emit.projected_expression_chain(view, self.at, self.frames.len() == 1,chain_child) {
                self.error = Some(error);
                return VisitDecision::Stop;
            }
            if self.emit.stopped() { return VisitDecision::Stop; }
            if !self.emit.descend_expression() { return VisitDecision::Skip; }
        }
        VisitDecision::Descend
    }
    fn leave_projected_expression(&mut self, view: dm_syntax::ProjectedExprView<'_>, _: &[dm_syntax::NodeStep]) {
        if let Some(chains)=&mut self.chains{chains.pop();}
        if let Some((_, true)) = self.frames.pop() { self.emit.leave_projected_expression(view); }
    }
}

fn expression(node: &Expr, at: Span, emit: &mut impl Observer) {
    emit.root_expression(ExpressionObservation::Owned(node),at);if emit.stopped(){return;}
    if let ExprKind::Binary { op, lhs, rhs } = &node.kind {
        if op == "=" {
            emit.statement_assignment(lhs, rhs, at);
        }
    }
    expression_tree(node, at, emit);
}
fn expression_tree(node:&Expr,at:Span,emit:&mut impl Observer){expression_tree_in(node,at,false,emit)}
fn expression_tree_in(node: &Expr, at: Span, chain_child:bool,emit: &mut impl Observer) {
    if emit.stopped() {
        return;
    }
    emit.expression_chain(node, at,chain_child);
    if emit.stopped() || !emit.descend_expression() {
        return;
    }
    if let ExprKind::Binary { op, lhs, rhs } = &node.kind {
        if matches!(op.as_str(), "=" | "+=" | "|=" | "||=") {
            emit.list_write_assignment(lhs, op, rhs, at);
        }
    }
    if let ExprKind::Binary { op, lhs, rhs } = &node.kind {
        if op == "=" {
            emit.assignment(lhs, rhs, at);
        }
    }
    if let ExprKind::Call { callee, .. } = &node.kind {
        if matches!(&callee.kind, ExprKind::StaticMember { .. }) {
            // Pinned Follow::ProcReference discards its parsed argument list.
            expression_tree_in(callee, at,true, emit);
            return;
        }
    }
    if let ExprKind::Unary { op, value } = &node.kind {
        if op == "new" {
            // Legacy New* walk visits arguments, never target mini-expressions.
            if let ExprKind::Call { args, .. } = &value.kind {
                for arg in args {
                    expression_tree(arg, at, emit);
                }
            }
            return;
        }
    }
    let main=base_chain_child(node);
    for_each_expression_child(node, |_, child| expression_tree_in(child,at,main.is_some_and(|main|std::ptr::eq(main,child)),emit));
}

/// `parse_if` retains the `else` prefix in the whole span, but advances the
/// nested header past it. An ordinary `if` written inside an explicit `else`
/// block has equal starts and must remain a separate legacy statement.
fn next_arm(else_branch: &[Statement]) -> Option<&Statement> {
    let [next] = else_branch else { return None };
    (matches!(&next.kind, StatementKind::If { .. }) && next.header_span.start > next.span.start)
        .then_some(next)
}

impl PolicyWalk<'_> {
    fn statement_walk(&mut self, statement: &Statement, emit: &mut impl Observer) {
        if emit.stopped() || !emit.statement(statement) {
            return;
        }
        let at = statement.span;
        match &statement.kind {
            StatementKind::If { .. } => {
                // All conditions of one legacy If share its first statement's
                // location, including conditions authored on later else-if lines.
                let mut arm = statement;
                loop {
                    let StatementKind::If {
                        condition,
                        else_branch,
                        ..
                    } = &arm.kind
                    else {
                        unreachable!("if-arm chain is checked above")
                    };
                    let point=match emit.if_condition_span(condition,at){Ok(point)=>point,Err(error)=>{self.error=Some(error);return}};expression(condition, point, emit);
                    match next_arm(else_branch) {
                        Some(next) => arm = next,
                        None => break,
                    }
                }
                let mut arm = statement;
                loop {
                    let StatementKind::If {
                        then_branch,
                        else_branch,
                        ..
                    } = &arm.kind
                    else {
                        unreachable!("if-arm chain is checked above")
                    };
                    self.walk(then_branch, emit);
                    match next_arm(else_branch) {
                        Some(next) => arm = next,
                        None => {
                            self.walk(else_branch, emit);
                            break;
                        }
                    }
                }
            }
            StatementKind::While { condition, body }
            | StatementKind::DoWhile { condition, body } => {
                expression(condition, at, emit);
                self.walk(body, emit);
            }
            StatementKind::Spawn { delay, body } => {
                if let Some(delay) = delay {
                    expression(delay, at, emit);
                }
                self.walk(body, emit);
            }
            StatementKind::Set { value, .. } => expression(value, at, emit),
            StatementKind::ProjectedSet { value, .. } => {
                self.projected(value, at, emit);
            }
            StatementKind::For { control, body } => {
                match control {
                    ForControl::All { .. } => {}
                    ForControl::Each { iterable, .. } | ForControl::Pair { iterable, .. } => {
                        expression(iterable, at, emit);
                    }
                    ForControl::RangeImplicitArray { end, step, .. } => {
                        // Analyze's original stmt_exprs order differs from the
                        // checker evaluator: synthetic start FIRST, then end/step.
                        self.implicit(statement, at, emit);
                        expression(end, at, emit);
                        if let Some(step) = step {
                            expression(step, at, emit);
                        }
                    }
                    ForControl::Range {
                        start, end, step, ..
                    } => {
                        expression(start, at, emit);
                        expression(end, at, emit);
                        if let Some(step) = step {
                            expression(step, at, emit);
                        }
                    }
                    ForControl::CStyle {
                        initializer,
                        condition,
                        step,
                    } => {
                        if self.engine_order {
                            // Engine::Walker::block visits init then inc before stmt_exprs(test).
                            // The primary init/step nodes and implicit-array ledger stay identical.
                            match initializer {
                                Some(ForInitializer::Declare{value:Some(value),..})|Some(ForInitializer::Expr(value))=>expression(value,at,emit),
                                Some(ForInitializer::Declare{value:None,..})=>self.implicit(statement,at,emit),
                                _=>{}
                            }
                            if let Some(step)=step{expression(step,at,emit);}
                            if let Some(condition)=condition{expression(condition,at,emit);}
                        }else{
                        // Legacy stmt_exprs(ForLoop) visits test; walk_block then
                        // visits init and inc, in that order, at the For's location.
                        if let Some(condition) = condition {
                            expression(condition, at, emit);
                        }
                        match initializer {
                            Some(ForInitializer::Declare {
                                value: Some(value), ..
                            })
                            | Some(ForInitializer::Expr(value)) => expression(value, at, emit),
                            Some(ForInitializer::Declare { value: None, .. }) => {
                                self.implicit(statement, at, emit)
                            }
                            _ => {}
                        }
                        if let Some(step) = step {
                            expression(step, at, emit);
                        }
                        }
                    }
                }
                self.walk(body, emit);
            }
            StatementKind::Switch {
                selector,
                cases,
                else_branch, ..
            } => {
                expression(selector, at, emit);
                for case in cases {
                    for alternative in &case.alternatives {
                        match alternative {
                            SwitchAlternative::Exact(value) => expression(value, at, emit),
                            SwitchAlternative::Range(start, end) => {
                                expression(start, at, emit);
                                expression(end, at, emit);
                            }
                        }
                    }
                }
                for case in cases {
                    self.walk(&case.body, emit);
                }
                self.walk(else_branch, emit);
            }
            StatementKind::Try {
                body, catch_body, ..
            } => {
                self.walk(body, emit);
                self.walk(catch_body, emit);
            }
            StatementKind::Throw(value)
            | StatementKind::Call(value)
            | StatementKind::Expression(value) => expression(value, at, emit),
            StatementKind::Return(Some(value))=>expression(value,at,emit),
            StatementKind::Var{value:Some(value),..}=>{expression(value,at,emit);if !emit.stopped(){emit.after_variable(statement);}}
            StatementKind::Assign { target, op, value } => {
                emit.list_write_assignment(target, op, value, at);
                if op == "=" {
                    emit.statement_assignment(target, value, at);
                    emit.assignment(target, value, at);
                }
                emit.root_expression(ExpressionObservation::Owned(target),at);
                expression_tree(target, at, emit);
                emit.root_expression(ExpressionObservation::Owned(value),at);
                expression_tree(value, at, emit);
            }
            StatementKind::Label { body, .. } => self.walk(body, emit),
            StatementKind::Var { value: None, .. } => self.implicit(statement, at, emit),
            StatementKind::Goto(_)
            | StatementKind::Return(None)
            | StatementKind::Break
            | StatementKind::BreakLabel(_)
            | StatementKind::Continue
            | StatementKind::ContinueLabel(_)
            | StatementKind::Unsupported => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn observed(source: &str) -> Vec<(String, usize)> {
        let ast = dm_syntax::parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let body = dm_syntax::parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        let mut found = Vec::new();
        assignments(
            dm_syntax::StatementView::from_parsed(&body),
            &mut |lhs, _, at| {
                let ExprKind::Ident(name) = &lhs.kind else {
                    panic!("expected test identifier")
                };
                let line = source[..at.start]
                    .bytes()
                    .filter(|byte| *byte == b'\n')
                    .count()
                    + 1;
                found.push((name.clone(), line));
            },
        )
        .unwrap();
        found
    }

    #[test]
    fn do_while_condition_precedes_body_at_the_do_statement() {
        assert_eq!(
            observed("/proc/test()\n    do\n        body = 1\n    while(condition = 2)\n"),
            [("condition".into(), 2), ("body".into(), 3)]
        );
    }

    #[test]
    fn c_style_for_observes_test_then_init_then_step_then_body() {
        assert_eq!(
            observed("/proc/test()\n    for(init = 0; (check = 1); step = 2)\n        body = 3\n"),
            [
                ("check".into(), 2),
                ("init".into(), 2),
                ("step".into(), 2),
                ("body".into(), 3)
            ]
        );
    }

    #[test]
    fn switch_observes_every_case_condition_before_any_case_body() {
        assert_eq!(
            observed("/proc/test()\n    switch(selector = 0)\n        if(first = 1)\n            body_one = 3\n        if(second = 2)\n            body_two = 4\n"),
            [("selector".into(), 2), ("first".into(), 2), ("second".into(), 2),
             ("body_one".into(), 4), ("body_two".into(), 6)]
        );
    }

    #[test]
    fn flattened_else_if_headers_precede_bodies_but_explicit_nested_if_is_separate() {
        assert_eq!(
            observed("/proc/test()\n    if(first = 1)\n        body_one = 3\n    else if(second = 2)\n        body_two = 4\n    else\n        if(nested = 5)\n            body_three = 6\n"),
            [("first".into(), 2), ("second".into(), 2), ("body_one".into(), 3),
             ("body_two".into(), 5), ("nested".into(), 7), ("body_three".into(), 8)]
        );
    }

    #[test]
    fn iteration_bindings_and_declarations_are_not_fabricated_assignments() {
        assert_eq!(
            observed("/proc/test()\n    for(var/element in list(nested = 1))\n        var/local = (other = 2)\n    outer = (inner = 3)\n    outer += (last = 4)\n"),
            [("nested".into(), 2), ("other".into(), 3), ("outer".into(), 4),
             ("inner".into(), 4), ("last".into(), 5)]
        );
    }

    #[test]
    fn original_array_dimensions_are_nested_and_explicit_initializers_suppress_them() {
        assert_eq!(
            observed("/proc/test()\n    var/sized[first = 1]\n    var/suppressed[ignored = 2] = (written = 3)\n"),
            [("first".into(),2),("written".into(),3)]
        );
    }

    #[test]
    fn original_implicit_range_syntax_order_is_start_then_end_then_step() {
        assert_eq!(
            observed("/proc/test()\n    for(var/sized[start = 1] to (end = 2) step (step = 3))\n        body = 4\n"),
            [("start".into(),2),("end".into(),2),("step".into(),2),("body".into(),3)]
        );
    }

    #[test]
    fn original_cstyle_array_initializer_follows_test_and_precedes_increment() {
        assert_eq!(
            observed("/proc/test()\n    for(var/sized[init = 1]; (test = 2); (inc = 3))\n        body = 4\n"),
            [("test".into(),2),("init".into(),2),("inc".into(),2),("body".into(),3)]
        );
    }

    #[test]
    fn a_bare_statement_slice_cannot_silently_omit_an_array_initializer() {
        let ast = dm_syntax::parse("/proc/test()\n    before = 1\n    var/sized[hidden = 2]\n");
        let body = dm_syntax::parse_proc_body(&ast.items[0]);
        let mut calls = 0;
        assert!(assignments(
            dm_syntax::StatementView::all(&body.statements),
            &mut |_, _, _| calls += 1
        )
        .is_err());
        assert_eq!(
            calls, 0,
            "missing original ledger refuses before any callback"
        );
    }
}

#[cfg(test)]
mod statement_root_tests {
    #[test]
    fn statement_assignment_observer_excludes_nested_arguments_and_rhs_assignments() {
        let source="/proc/test()\n    outer = inner = 1\n    call(named = 2)\n    (grouped = 3)\n    if(condition = 4)\n        body = 5\n";
        let syntax = dm_syntax::parse(source);
        assert!(syntax.diagnostics.is_empty());
        let body = dm_syntax::parse_proc_body(&syntax.items[0]);
        assert!(body.diagnostics.is_empty());
        let mut found = Vec::new();
        super::statement_assignments(
            dm_syntax::StatementView::from_parsed(&body),
            &mut |target, _, _| {
                if let dm_syntax::ExprKind::Ident(n) = &target.kind {
                    found.push(n.clone());
                }
            },
        )
        .unwrap();
        assert_eq!(found, ["outer", "condition", "body"]);
    }
}


#[cfg(test)]
mod projected_policy_tests {
    use super::*;
    use std::sync::{atomic::AtomicUsize, Arc};
    struct Provider(dm_syntax::SettingExpression);
    impl dm_syntax::SettingSyntaxProvider for Provider {
        fn setting(&self, _: &dm_syntax::Item) -> Result<dm_syntax::SettingStatement, dm_syntax::Diagnostic> {
            Ok(dm_syntax::SettingStatement { attribute: "name".into(), relation: "=".into(), value: self.0.clone() })
        }
    }
    fn prepare(rhs: &str, a: &dm_syntax::SettingAdmission<'_>) -> dm_syntax::SettingExpression {
        let tokens = dm_syntax::lex_spans(rhs);
        assert!(tokens.diagnostics.is_empty());
        dm_syntax::prepare_setting_expression(rhs, &tokens.tokens, Span::new(0, rhs.len()), a).unwrap()
    }
    fn bodies(rhs: &str, prefix: &str, root: &dm_syntax::SettingExpression, a: &dm_syntax::SettingAdmission<'_>)
        -> (String, dm_syntax::ParsedBody, dm_syntax::ParsedBody) {
        let source = format!("{prefix}/proc/p()\n    set name = {rhs}\n");
        let ast = dm_syntax::parse(&source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let owned = dm_syntax::parse_body_items(&ast.items[0].children);
        let provider = Provider(root.clone().project_current(source.find(rhs).unwrap(), rhs.len()).unwrap());
        let projected = dm_syntax::parse_body_items_with_context_and_settings(
            &ast.items[0].children, &source, &|_| None, &provider, a);
        assert!(owned.diagnostics.is_empty(), "{:?}", owned.diagnostics);
        assert!(projected.diagnostics.is_empty(), "{:?}", projected.diagnostics);
        (source, owned, projected)
    }
    struct Trace<'a> {
        source: &'a str,
        rows: Vec<(String, Span, Span)>,
        original: Vec<*const Expr>,
        entered: usize,
        left: usize,
    }
    impl Observer for Trace<'_> {
        fn expression(&mut self, e: &Expr, at: Span) {
            self.rows.push((self.source[e.span.range()].into(), e.span, at));
        }
        fn projected_expression(&mut self, v: dm_syntax::ProjectedExprView<'_>, at: Span, _: bool) -> Result<(), &'static str> {
            let span = v.current_span();
            self.rows.push((self.source[span.range()].into(), span, at));
            self.original.push(v.original() as *const Expr);
            self.entered += 1;
            Ok(())
        }
        fn leave_projected_expression(&mut self, _: dm_syntax::ProjectedExprView<'_>) { self.left += 1; }
    }
    fn pointers(root: &Expr, out: &mut std::collections::HashSet<*const Expr>) {
        out.insert(root as *const Expr);
        dm_syntax::for_each_expression_child(root, |_, child| pointers(child, out));
    }
    #[test]
    fn projected_policy_matches_owned_proc_reference_and_new_observation_without_cloning_nodes() {
        let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let checkpoint = || Ok(());
        let a = dm_syntax::SettingAdmission::new(&counter, 16 * 1024 * 1024, &checkpoint);
        for rhs in ["target::handler(hidden = 1)", "new /datum/example(shown = 2)",
            "call(first = 1, nested(second = 2))", "(outer = (inner = 3))"] {
            let root = prepare(rhs, &a);
            let mut issued = std::collections::HashSet::new();
            pointers(root.original_expression(), &mut issued);
            for prefix in ["", "// current UTF8: Ã©\n\n"] {
                let (source, owned, projected) = bodies(rhs, prefix, &root, &a);
                let mut old = Trace { source: &source, rows: vec![], original: vec![], entered: 0, left: 0 };
                let mut current = Trace { source: &source, rows: vec![], original: vec![], entered: 0, left: 0 };
                observe(dm_syntax::StatementView::from_parsed(&owned), &mut old).unwrap();
                observe(dm_syntax::StatementView::from_parsed(&projected), &mut current).unwrap();
                assert_eq!(old.rows, current.rows, "exact old preorder and current spans for {rhs}");
                assert_eq!(current.entered, current.left, "balanced even suppressed intermediate new-call nodes");
                assert!(!current.original.is_empty());
                assert_eq!(current.original[0], root.original_expression() as *const Expr);
                assert!(current.original.iter().all(|p| issued.contains(p)), "all observed nodes borrow SAME canonical root");
                let mut assignments = Vec::new();
                assignments_current(dm_syntax::StatementView::from_parsed(&projected), &mut |lhs, _, at, current| {
                    if let ExprKind::Ident(name) = &lhs.kind { assignments.push((name.clone(), at, current)); }
                }).unwrap();
                let names: Vec<_> = assignments.iter().map(|r| r.0.as_str()).collect();
                match rhs {
                    "target::handler(hidden = 1)" => assert!(names.is_empty(), "old ProcReference excludes ALL arguments"),
                    "new /datum/example(shown = 2)" => {
                        assert_eq!(names, ["shown"]);
                        assert!(!current.rows.iter().any(|r| r.0 == "/datum/example" || r.0 == "/datum/example(shown = 2)"),
                            "old new walks arguments only, not target/intermediate call");
                    }
                    _ => (),
                }
            }
        }
    }
    #[test]
    fn projected_assignment_reports_current_lhs_separately_from_old_statement_anchor_after_rebase() {
        let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let checkpoint = || Ok(());
        let a = dm_syntax::SettingAdmission::new(&counter, 16 * 1024 * 1024, &checkpoint);
        let rhs = "(outer = (inner = 3))";
        let root = prepare(rhs, &a);
        let original_ptr = root.original_expression() as *const Expr;
        let mut first = None;
        for prefix in ["", "// earlier include shifts coordinates\n\n"] {
            let (source, owned, projected) = bodies(rhs, prefix, &root, &a);
            let collect = |body: &dm_syntax::ParsedBody| {
                let mut rows = Vec::new();
                assignments_current(dm_syntax::StatementView::from_parsed(body), &mut |lhs, _, at, current| {
                    let ExprKind::Ident(name) = &lhs.kind else { panic!("fixture identifier") };
                    rows.push((name.clone(), at, current));
                }).unwrap();
                rows
            };
            let rows = collect(&projected);
            assert_eq!(rows, collect(&owned));
            assert_eq!(rows.iter().map(|r| r.0.as_str()).collect::<Vec<_>>(), ["outer", "inner"]);
            for (name, statement, target) in &rows {
                assert_eq!(&source[target.range()], name);
                assert_ne!(statement, target, "statement report anchor is not assignment lhs");
                assert_eq!(*statement, projected.statements[0].span);
            }
            if let Some((statement, target)) = first {
                assert_eq!(rows[0].1.start - statement, prefix.len());
                assert_eq!(rows[0].2.start - target, prefix.len());
            } else { first = Some((rows[0].1.start, rows[0].2.start)); }
            let StatementKind::ProjectedSet { value, .. } = &projected.statements[0].kind else { panic!("projected") };
            assert!(root.same_root(value));
            assert_eq!(original_ptr, value.original_expression() as *const Expr);
        }
    }
    #[test]
    fn projected_statement_assignment_boundary_matches_owned_and_excludes_nested_writes() {
        let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let checkpoint = || Ok(());
        let a = dm_syntax::SettingAdmission::new(&counter, 16 * 1024 * 1024, &checkpoint);
        for (rhs, expected) in [("key = (ckey = 1)", vec!["key"]),
            ("call(key = 2)", vec![]), ("(key = 3)", vec![])] {
            let root = prepare(rhs, &a);
            for prefix in ["", "// moved Ã©\n\n"] {
                let (source, owned, projected) = bodies(rhs, prefix, &root, &a);
                let collect = |body: &dm_syntax::ParsedBody| {
                    let mut rows = Vec::new();
                    statement_assignments_current(dm_syntax::StatementView::from_parsed(body), &mut |lhs, _, at, target| {
                        let ExprKind::Ident(name) = &lhs.kind else { panic!("identifier target") };
                        rows.push((name.clone(), at, target));
                    }).unwrap();
                    rows
                };
                let rows = collect(&projected);
                assert_eq!(rows, collect(&owned));
                assert_eq!(rows.iter().map(|r| r.0.as_str()).collect::<Vec<_>>(), expected);
                for (name, at, target) in rows { assert_eq!(&source[target.range()], name); assert_eq!(at, projected.statements[0].span); }
            }
        }
    }

}


#[cfg(test)]
pub(crate) fn projected_body_host_for_test() -> std::sync::Arc<dyn dm_tree::frontend::BodySyntaxQueries> {
    #[derive(Debug)]
    struct Host(std::sync::Arc<dm_syntax::SettingChargeCounter>);
    impl dm_tree::frontend::BodySyntaxQueries for Host {
        fn syntax(&self, input: &std::sync::Arc<dm_tree::frontend::BodySyntaxInput>) -> Result<std::sync::Arc<dm_tree::frontend::BodySyntax>, dm_tree::frontend::Diagnostic> {
            let checkpoint = || Ok(());
            let admission = dm_syntax::SettingAdmission::new(&self.0, 16 * 1024 * 1024, &checkpoint);
            match input.parse_with_setting_admission(&admission) {
                Ok(value) => Ok(std::sync::Arc::new(value)),
                Err(dm_tree::frontend::BodySyntaxFailure::Syntax(error)) => Err(error),
                Err(dm_tree::frontend::BodySyntaxFailure::Operational(error)) => panic!("unexpected actual fixture operation: {error}"),
            }
        }
    }
    std::sync::Arc::new(Host(dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap()))
}
#[cfg(test)]
mod projected_event_parity_tests {
    use super::*;
    use std::{cell::RefCell, sync::{Arc, atomic::AtomicUsize}};
    struct Provider(dm_syntax::SettingExpression);
    impl dm_syntax::SettingSyntaxProvider for Provider {
        fn setting(&self, _: &dm_syntax::Item) -> Result<dm_syntax::SettingStatement, dm_syntax::Diagnostic> {
            Ok(dm_syntax::SettingStatement { attribute: "name".into(), relation: "=".into(), value: self.0.clone() })
        }
    }
    #[test]
    fn projected_expression_and_stored_write_streams_match_old_order_and_current_statement_anchors() {
        let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap(); let checkpoint = || Ok(());
        let admission = dm_syntax::SettingAdmission::new(&counter, 16 * 1024 * 1024, &checkpoint);
        for rhs in ["items += new /datum", "items = list(D = null)", "items.Add(D)",
            "target::handler(ignored = 1)", "new /datum/probe(visible = 2)", "nameof(holder.target)"] {
            let lexed = dm_syntax::lex_spans(rhs);
            let root = dm_syntax::prepare_setting_expression(rhs, &lexed.tokens, Span::new(0, rhs.len()), &admission).unwrap();
            for prefix in ["", "// shifted \u{e9}\n\n"] {
                let source = format!("{prefix}/proc/p()\n    set name = {rhs}\n");
                let ast = dm_syntax::parse(&source); assert!(ast.diagnostics.is_empty());
                let owned = dm_syntax::parse_body_items(&ast.items[0].children);
                let current = root.clone().project_current(source.find(rhs).unwrap(), rhs.len()).unwrap();
                let projected = dm_syntax::parse_body_items_with_context_and_settings(&ast.items[0].children, &source, &|_|None, &Provider(current), &admission);
                assert!(owned.diagnostics.is_empty()); assert!(projected.diagnostics.is_empty());
                let mut old = Vec::new(); let mut actual = Vec::new();
                expressions(dm_syntax::StatementView::from_parsed(&owned), &mut |e,at| old.push((source[e.span.range()].to_owned(),e.span,at))).unwrap();
                expressions_current(dm_syntax::StatementView::from_parsed(&projected), &mut |v,at| actual.push((source[v.current_span().range()].to_owned(),v.current_span(),at))).unwrap();
                assert_eq!(old,actual,"exact old expression stream for {rhs}");
                let old = RefCell::new(Vec::new()); let actual = RefCell::new(Vec::new());
                stored_events(dm_syntax::StatementView::from_parsed(&owned),
                    &mut |e,at|old.borrow_mut().push((format!("E:{}",source[e.span.range()].to_owned()),at)),
                    &mut |_,op,_,at|old.borrow_mut().push((format!("A:{op}"),at))).unwrap();
                stored_events_current(dm_syntax::StatementView::from_parsed(&projected),
                    &mut |v,at|actual.borrow_mut().push((format!("E:{}",source[v.current_span().range()].to_owned()),at)),
                    &mut |_,op,_,at|actual.borrow_mut().push((format!("A:{op}"),at))).unwrap();
                assert_eq!(old.into_inner(),actual.into_inner(),"root-first expression/list-write ordering for {rhs}");
                let StatementKind::ProjectedSet{value,..}=&projected.statements[0].kind else {panic!("projected")};
                assert!(root.same_root(value));
            }
        }
    }
}

/// Exact engine-layering ROOT observation, alongside the existing value-policy
/// mode. Borrowed original statements/setting projections, no parser/AST clone.
/// Callers project Term/follow chains themselves; nested structural callee nodes
/// are deliberately not misrepresented as separate legacy Expression::Base roots.
pub(crate) fn try_engine_roots<C,E>(view:dm_syntax::StatementView<'_>,control:&mut C,checkpoint:&mut impl FnMut(&mut C)->Result<(),E>,statement:&mut impl FnMut(&mut C,&Statement)->Result<(),E>,root:&mut impl FnMut(&mut C,ExpressionObservation<'_>,Span)->Result<(),E>)->Result<(),PolicyVisitFailure<E>>{
 struct Engine<'a,C,E,P,S,F>{control:&'a mut C,poll:&'a mut P,statement:&'a mut S,root:&'a mut F,error:Option<E>}
 impl<C,E,P:FnMut(&mut C)->Result<(),E>,S:FnMut(&mut C,&Statement)->Result<(),E>,F:FnMut(&mut C,ExpressionObservation<'_>,Span)->Result<(),E>> Observer for Engine<'_,C,E,P,S,F>{
  fn stopped(&self)->bool{self.error.is_some()}
  fn statement(&mut self,st:&Statement)->bool{if self.error.is_some(){return false}if let Err(e)=(self.poll)(self.control).and_then(|()|(self.statement)(self.control,st)){self.error=Some(e);false}else{true}}
  fn root_expression(&mut self,view:ExpressionObservation<'_>,at:Span){if self.error.is_none(){if let Err(e)=(self.poll)(self.control).and_then(|()|(self.root)(self.control,view,at)){self.error=Some(e)}}}
  fn expression(&mut self,_:&Expr,_:Span){if self.error.is_none(){if let Err(e)=(self.poll)(self.control){self.error=Some(e)}}}
  fn projected_expression(&mut self,_:dm_syntax::ProjectedExprView<'_>,_:Span,_:bool)->Result<(),&'static str>{if self.error.is_none(){if let Err(e)=(self.poll)(self.control){self.error=Some(e)}}Ok(())}
 }
 let ledger=view.local_variables().ok_or(PolicyVisitFailure::Unsupported("engine observation requires original local ledger"))?;ledger.entries().map_err(|_|PolicyVisitFailure::Unsupported("engine original local ledger unavailable"))?;
 let mut observer=Engine{control,poll:checkpoint,statement,root,error:None};let mut walk=PolicyWalk{ledger,error:None,engine_order:true};walk.walk(view.statements(),&mut observer);if let Some(e)=observer.error{return Err(PolicyVisitFailure::Callback(e))}walk.error.map_or(Ok(()),|s|Err(PolicyVisitFailure::Unsupported(s)))
}
