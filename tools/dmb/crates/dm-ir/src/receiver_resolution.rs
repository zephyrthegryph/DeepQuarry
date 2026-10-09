//! Shared receiver inference over the authored typed model and current query host.
//! None conveys no usable receiver contract, not proof of a missing declaration.
use crate::{ResolveQuery, SymbolId};
use dm_syntax::{Expr, ExprKind};

#[cfg(test)]
#[path = "receiver_resolution_tests.rs"]
mod tests;

pub trait ReceiverTypeContext {
    type Error;
    fn current_type_path(&self) -> Option<&str>;
    fn semantic_queries_available(&self) -> bool;
    fn local_type(&self, name: &str) -> Option<Option<&str>>;
    fn argument_type(&self, name: &str) -> Option<Option<&str>>;
    /// Outer Some certifies a nearer procedure-static binding, even if untyped.
    fn procedure_static_type(&self, name: &str) -> Result<Option<Option<String>>, Self::Error>;
    fn has_member_field(&self, owner: &str, name: &str) -> Result<bool, Self::Error>;
    fn field_type(&self, name: &str) -> Result<Option<String>, Self::Error>;
    fn global_type(&self, name: &str) -> Result<Option<String>, Self::Error>;
    fn member_type(&self, owner: &str, name: &str) -> Result<Option<String>, Self::Error>;
    fn is_intrinsic(&self, name: &str) -> bool;
    fn has_member_proc(&self, owner: &str, name: &str) -> Result<bool, Self::Error>;
    fn procedure_return_type(&self, query: ResolveQuery) -> Result<Option<String>, Self::Error>;
    fn normalize_type(&self, path: &str) -> Result<String, Self::Error>;
}
fn declaration_runtime_path(path: &str) -> String {
    format!(
        "/{}",
        dm_syntax::project_declaration_type(path)
            .runtime_path
            .trim_start_matches('/')
    )
}
pub fn infer_receiver_type<C: ReceiverTypeContext>(
    context: &C,
    expr: &Expr,
) -> Result<Option<String>, C::Error> {
    let inferred = match &expr.kind {
        ExprKind::TypePath(path) => Some(path.clone()),
        ExprKind::Ident(name) => {
            // Preserve existing compiler context-value ordering, including src/usr
            // before lexical bindings. This extraction does not change semantics.
            if name == "src" {
                return context
                    .current_type_path()
                    .map(|path| context.normalize_type(path))
                    .transpose();
            }
            if name == "usr" {
                return context.normalize_type("/mob").map(Some);
            }
            if let Some(path) = context.local_type(name) {
                return path
                    .map(|path| context.normalize_type(&declaration_runtime_path(path)))
                    .transpose();
            }
            if let Some(path) = context.argument_type(name) {
                return path
                    .map(|path| context.normalize_type(&declaration_runtime_path(path)))
                    .transpose();
            }
            if let Some(path) = context.procedure_static_type(name)? {
                return Ok(path);
            }
            match name.as_str() {
                "world" => return context.normalize_type("/world").map(Some),
                "args" => return context.normalize_type("/list").map(Some),
                "caller" | "callee" => return context.normalize_type("/callee").map(Some),
                "." => return Ok(None),
                _ => (),
            }
            if context.semantic_queries_available() {
                if let Some(owner) = context.current_type_path() {
                    return if context.has_member_field(owner, name)? {
                        context
                            .field_type(name)?
                            .map(|path| context.normalize_type(&path))
                            .transpose()
                    } else {
                        context
                            .global_type(name)?
                            .map(|path| context.normalize_type(&path))
                            .transpose()
                    };
                }
            }
            match context.field_type(name)? {
                Some(path) => Some(path),
                None => context.global_type(name)?,
            }
        }
        ExprKind::Group(inner) => infer_receiver_type(context, inner)?,
        ExprKind::Member {
            object,
            selector,
            via_colon,
        } => {
            if *via_colon {
                return Ok(None);
            }
            if matches!(&object.kind,ExprKind::Ident(name) if name=="global") {
                return context
                    .global_type(selector)?
                    .map(|path| context.normalize_type(&path))
                    .transpose();
            }
            if matches!(&object.kind,ExprKind::Ident(name) if name=="src") {
                return context
                    .field_type(selector)?
                    .map(|path| context.normalize_type(&path))
                    .transpose();
            }
            match infer_receiver_type(context, object)? {
                Some(owner) => context.member_type(&owner, selector)?,
                None => None,
            }
        }
        ExprKind::SafeMember { object, selector } => match infer_receiver_type(context, object)? {
            Some(owner) => context.member_type(&owner, selector)?,
            None => None,
        },
        ExprKind::Call { callee, .. } if context.semantic_queries_available() => match &callee.kind
        {
            ExprKind::Ident(name) => {
                if context.is_intrinsic(name) {
                    return Ok(None);
                }
                if let Some(owner) = context.current_type_path() {
                    if context.has_member_proc(owner, name)? {
                        return context.procedure_return_type(ResolveQuery::Proc {
                            owner: SymbolId::of(owner),
                            name: SymbolId::of(name),
                            verb: false,
                        });
                    }
                }
                context.procedure_return_type(ResolveQuery::GlobalProc(SymbolId::of(name)))?
            }
            ExprKind::Member {
                object,
                selector,
                via_colon: false,
            }
            | ExprKind::SafeMember { object, selector } => {
                match infer_receiver_type(context, object)? {
                    Some(owner) => context.procedure_return_type(ResolveQuery::Proc {
                        owner: SymbolId::of(&owner),
                        name: SymbolId::of(selector),
                        verb: false,
                    })?,
                    None => None,
                }
            }
            _ => None,
        },
        _ => None,
    };
    // Repeated normalization on group/member/call paths is intentional: it
    // preserves the compiler's existing query and error observation sequence.
    inferred
        .map(|path| context.normalize_type(&path))
        .transpose()
}
