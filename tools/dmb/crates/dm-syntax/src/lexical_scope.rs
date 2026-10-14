//! Shared lexical environment mechanics; semantic/global fallback belongs to the
//! resolver. IDs are request-local and must never be used as persistent keys.
use crate::{ScopeCheckpoint, ScopeMap};
use std::sync::Arc;

/// The compiler's declaration-name projection, shared without reparsing a body.
/// Stored declarations are handled by their issued static inventory instead.
pub fn local_name(declaration: &str) -> Option<&str> {
    let raw = declaration
        .strip_prefix("var/")
        .or_else(|| {
            declaration
                .strip_prefix("var")
                .filter(|tail| tail.chars().next().is_some_and(char::is_whitespace))
        })?
        .trim_start();
    if raw.starts_with("static/") || raw.starts_with("global/") {
        return None;
    }
    let raw_name = raw.rsplit('/').next()?;
    let name = raw_name.split_once('[').map_or(raw_name, |(name, _)| name);
    (!name.is_empty() && name.chars().all(|ch| ch.is_alphanumeric() || ch == '_')).then_some(name)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct BindingId(pub usize);

#[derive(Debug)]
pub enum BindingValue<T> {
    Parameter { ordinal: usize },
    Local(T),
}
#[derive(Debug)]
pub struct Binding<T> {
    pub name: Arc<str>,
    pub value: BindingValue<T>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ScopeError {
    DuplicateLocal(BindingId),
    NoEnclosingScope,
}

/// The journal restores visibility without cloning the complete environment at
/// every branch. Binding payloads remain in declaration order after scope exit,
/// so frame allocation and analysis can share declaration IDs and their origin.
pub struct LexicalScopes<T> {
    bindings: Vec<Binding<T>>,
    visible: ScopeMap<BindingId>,
    scopes: Vec<ScopeCheckpoint>,
}
impl<T> LexicalScopes<T> {
    pub fn new<N: Into<Arc<str>>>(parameters: impl IntoIterator<Item = N>) -> Self {
        let mut result = Self {
            bindings: Vec::new(),
            visible: ScopeMap::default(),
            scopes: Vec::new(),
        };
        for (ordinal, name) in parameters.into_iter().enumerate() {
            let name = name.into();
            let id = BindingId(result.bindings.len());
            if !result.visible.contains_key(name.as_ref()) {
                result.visible.insert(name.to_string(), id);
            }
            result.bindings.push(Binding {
                name,
                value: BindingValue::Parameter { ordinal },
            });
        }
        result
    }
    pub fn enter_scope(&mut self) {
        self.scopes.push(self.visible.checkpoint());
    }
    pub fn leave_scope(&mut self) -> Result<(), ScopeError> {
        let mark = self.scopes.pop().ok_or(ScopeError::NoEnclosingScope)?;
        self.visible.restore(mark);
        Ok(())
    }
    /// Existing active locals cannot be redeclared. A local may shadow an
    /// argument; the argument's original position is restored after scope exit.
    pub fn declare(
        &mut self,
        name: impl Into<Arc<str>>,
        value: T,
    ) -> Result<BindingId, ScopeError> {
        let name = name.into();
        let previous = self.visible.get(name.as_ref()).copied();
        if let Some(previous) = previous {
            if matches!(&self.bindings[previous.0].value, BindingValue::Local(_)) {
                return Err(ScopeError::DuplicateLocal(previous));
            }
        }
        let id = BindingId(self.bindings.len());
        self.visible.insert(name.to_string(), id);
        self.bindings.push(Binding {
            name,
            value: BindingValue::Local(value),
        });
        Ok(id)
    }
    pub fn resolve(&self, name: &str) -> Option<BindingId> {
        self.visible.get(name).copied()
    }
    pub fn binding(&self, id: BindingId) -> Option<&Binding<T>> {
        self.bindings.get(id.0)
    }
    pub fn declarations(&self) -> &[Binding<T>] {
        &self.bindings
    }
    pub fn scope_depth(&self) -> usize {
        self.scopes.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn argument_shadowing_branch_redeclarations_and_frame_order_match_lowering() {
        let mut scopes = LexicalScopes::new(["x", "other", "x"]);
        let parameter = scopes.resolve("x").unwrap();
        assert!(matches!(
            scopes.binding(parameter).unwrap().value,
            BindingValue::Parameter { ordinal: 0 }
        ));
        scopes.enter_scope();
        let first = scopes.declare("x", 0u32).unwrap();
        assert_eq!(scopes.resolve("x"), Some(first));
        scopes.enter_scope();
        assert_eq!(
            scopes.declare("x", 1),
            Err(ScopeError::DuplicateLocal(first))
        );
        let inner = scopes.declare("inner", 1).unwrap();
        scopes.leave_scope().unwrap();
        assert_eq!(scopes.resolve("inner"), None);
        assert!(matches!(
            scopes.binding(inner).unwrap().value,
            BindingValue::Local(1)
        ));
        scopes.leave_scope().unwrap();
        assert_eq!(scopes.resolve("x"), Some(parameter));
        scopes.enter_scope();
        let second = scopes.declare("x", 2).unwrap();
        assert_ne!(first, second);
        assert_eq!(scopes.declarations().len(), 6);
        scopes.leave_scope().unwrap();
        assert_eq!(scopes.leave_scope(), Err(ScopeError::NoEnclosingScope));
        assert_eq!(scopes.resolve("x"), Some(parameter));
    }
}
