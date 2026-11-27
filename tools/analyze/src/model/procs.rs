//! Procs as the analysis resolves them: a type's definitions of one name (a builtin first when BYOND declares it there, then the code's
//! definitions, the declaring one first), the definition a name resolves to from a type (the last one of the nearest type that has
//! any), and the one it overrides.

use std::sync::Arc;

use dm_syntax::Statement;
use dm_tree::MemberKind;

use super::builtins::{self, BuiltinProc};
use super::{Member, Site, Ty};

/// One definition of a proc: a builtin's (BYOND's, no code) or a code definition.
#[derive(Clone, Copy)]
pub enum Proc<'m> {
    Builtin { owner: Ty<'m>, name: &'m str, proc: &'static BuiltinProc },
    Code(Member<'m>),
}

impl<'m> Proc<'m> {
    pub fn name(&self) -> &'m str {
        match self {
            Proc::Builtin { name, .. } => name,
            Proc::Code(m) => m.name(),
        }
    }

    pub fn owner(&self) -> Ty<'m> {
        match self {
            Proc::Builtin { owner, .. } => *owner,
            Proc::Code(m) => m.owner(),
        }
    }

    pub fn is_builtin(&self) -> bool {
        matches!(self, Proc::Builtin { .. })
    }

    pub fn member(&self) -> Option<Member<'m>> {
        match self {
            Proc::Code(m) => Some(*m),
            Proc::Builtin { .. } => None,
        }
    }

    /// Whether this definition declares the proc (`proc/x()`, `verb/x()`, or BYOND's builtin declaration).
    pub fn declares(&self) -> bool {
        match self {
            Proc::Builtin { proc, .. } => proc.declares,
            Proc::Code(m) => m.declares(),
        }
    }

    /// The parameter names, `...` for a variadic tail.
    pub fn parameter_names(&self) -> Vec<&'m str> {
        match self {
            Proc::Builtin { proc, .. } => proc.parameters.iter().map(String::as_str).collect(),
            Proc::Code(m) => m.parameter_names(),
        }
    }

    /// The parameters (a builtin's carry only their names).
    pub fn parameters(&self) -> Arc<Vec<super::Param>> {
        match self {
            Proc::Code(m) => m.parameters(),
            Proc::Builtin { proc, .. } => Arc::new(
                proc.parameters
                    .iter()
                    .map(|n| super::Param { name: n.clone(), type_path: Vec::new(), value: None, as_types: None, in_list: None, site: Site(0) })
                    .collect(),
            ),
        }
    }

    pub fn body(&self) -> Option<&'m [Statement]> {
        self.member().and_then(|m| m.body())
    }

    pub fn site(&self) -> Option<Site> {
        self.member().and_then(|m| m.site())
    }

    /// How many definitions of this name its type has, and this one's place among them (the builtin first, then the code's).
    fn place(&self) -> (usize, usize) {
        let owner = self.owner();
        let builtin = owner.builtin_proc(self.name()).is_some() as usize;
        let own = owner.own_proc_ids(self.name());
        let idx = match self {
            Proc::Builtin { .. } => 0,
            Proc::Code(m) => builtin + own.iter().position(|id| *id == m.id).unwrap_or(0),
        };
        (builtin + own.len(), idx)
    }

    /// The definition at `idx` on this definition's type.
    fn at(&self, idx: usize) -> Option<Proc<'m>> {
        self.owner().definition_at(self.name(), idx)
    }

    /// The definition this one overrides: the previous one on the same type, else the one the name resolves to from the parent.
    pub fn parent_proc(&self) -> Option<Proc<'m>> {
        let (_, idx) = self.place();
        if idx > 0 {
            return self.at(idx - 1);
        }
        self.owner().parent()?.proc(self.name())
    }

    /// Whether this is the last definition on its type (the one callers on the type reach).
    pub fn is_last(&self) -> bool {
        let (len, idx) = self.place();
        idx + 1 == len
    }

    /// The index among the type's definitions of this name.
    pub fn index(&self) -> usize {
        self.place().1
    }

    /// The declaration's kind along the override chain: `Some(true)` verb, `Some(false)` proc, `None` when nothing declares it.
    pub fn declared_verb(&self) -> Option<bool> {
        let mut cur = Some(*self);
        while let Some(p) = cur {
            match p {
                Proc::Builtin { proc, .. } if proc.declares => return Some(proc.verb),
                Proc::Code(m) if m.declares() => return Some(m.kind() == MemberKind::Verb),
                _ => {}
            }
            cur = p.parent_proc();
        }
        None
    }

    /// A stable identity across revisions: owner path, name and definition index.
    pub fn key(&self) -> (Arc<str>, Arc<str>, usize) {
        (Arc::from(self.owner().path()), Arc::from(self.name()), self.index())
    }
}

impl<'m> Ty<'m> {
    /// This type's definitions of `name`, in the order they override one another.
    pub fn proc_definitions(&self, name: &str) -> Vec<Proc<'m>> {
        super::reads::note(|| super::reads::Read::Lookup { owner: Arc::from(self.path()), name: Arc::from(name), kind: super::reads::LookupKind::Proc });
        super::profile::time(super::profile::PROC_DEFS, || self.proc_definitions_uncounted(name))
    }

    fn proc_definitions_uncounted(&self, name: &str) -> Vec<Proc<'m>> {
        let mut out = Vec::new();
        if let Some(b) = self.builtin_proc(name) {
            out.push(b);
        }
        out.extend(self.own_procs_named(name).map(Proc::Code));
        out
    }

    /// BYOND's builtin definition of `name` on this type, when it has one.
    fn builtin_proc(&self, name: &str) -> Option<Proc<'m>> {
        let (n, p) = builtins::get().procs.get(self.path())?.iter().find(|(n, _)| n == name)?;
        Some(Proc::Builtin { owner: *self, name: n.as_str(), proc: p })
    }

    /// The definition at `idx` among this type's definitions of `name`.
    fn definition_at(&self, name: &str, idx: usize) -> Option<Proc<'m>> {
        let builtin = self.builtin_proc(name);
        match (builtin, idx) {
            (Some(b), 0) => Some(b),
            (Some(_), i) => self.own_proc_ids(name).get(i - 1).map(|&id| Proc::Code(self.member(id))),
            (None, i) => self.own_proc_ids(name).get(i).map(|&id| Proc::Code(self.member(id))),
        }
    }

    /// The last definition of `name` on this type.
    fn last_definition(&self, name: &str) -> Option<Proc<'m>> {
        match self.own_proc_ids(name).last() {
            Some(&id) => Some(Proc::Code(self.member(id))),
            None => self.builtin_proc(name),
        }
    }

    /// Every proc name with definitions on this type, builtins first (table order), then by first definition.
    pub fn proc_names(&self) -> Vec<&'m str> {
        let mut out: Vec<&'m str> = Vec::new();
        if let Some(l) = builtins::get().procs.get(self.path()) {
            out.extend(l.iter().map(|(n, _)| n.as_str()));
        }
        for m in self.procs() {
            if !out.contains(&m.name()) {
                out.push(m.name());
            }
        }
        out
    }

    /// What `name` resolves to from this type: the last definition on the nearest type (this one first) that has any.
    pub fn proc(&self, name: &str) -> Option<Proc<'m>> {
        super::reads::note(|| super::reads::Read::Lookup { owner: Arc::from(self.path()), name: Arc::from(name), kind: super::reads::LookupKind::Proc });
        super::profile::count(super::profile::PROC_RESOLVE);
        let mut cur = Some(*self);
        while let Some(t) = cur {
            if let Some(p) = t.last_definition(name) {
                return Some(p);
            }
            cur = t.parent();
        }
        None
    }
}
