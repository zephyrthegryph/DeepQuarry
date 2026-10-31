use std::collections::{HashMap,HashSet,BTreeSet};
use dreammaker::ast::{Block,Expression,Follow,Term,VarType};
use dreammaker::objtree::ProcRef;
use super::Sem;
#[derive(Default, serde::Serialize, serde::Deserialize)]
pub struct WriteIndex {
    /// Every written var name, typed or not.
    written: HashSet<String>,
    /// var -> the types that declare a var of that name some typed write reaches.
    typed: HashMap<String, BTreeSet<String>>,
    /// var names some write reaches through a receiver that could not be typed.
    untyped: BTreeSet<String>,
}

/// The receiver of a write that could not be typed.
pub const UNTYPED_WRITE: &str = "?";

impl WriteIndex {
    /// A digest of the written vars (`walk_cache`).
    pub fn digest(&self) -> u128 {
        let mut v: Vec<&String> = self.written.iter().collect();
        v.sort();
        let mut h = blake3::Hasher::new();
        for x in v {
            h.update(x.as_bytes());
            h.update(b"\n");
        }
        let mut t: Vec<(&String, &BTreeSet<String>)> = self.typed.iter().collect();
        t.sort();
        for (var, owners) in t {
            h.update(var.as_bytes());
            for o in owners {
                h.update(b"@");
                h.update(o.as_bytes());
            }
            h.update(b"\n");
        }
        for u in &self.untyped {
            h.update(b"?");
            h.update(u.as_bytes());
        }
        u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
    }

    /// Whether some write names `var`, on whatever type: a name test for callers that have no owner.
    pub fn is_written(&self, var: &str) -> bool {
        self.written.contains(var)
    }

    /// Whether `var`, as `owner` sees it, is written: by a write through a receiver typed as a type that declares it (`owner`'s declaring type,
    /// or one related to it), or by any write whose receiver could not be typed.
    pub fn is_written_on(&self, sem: &Sem, owner: &str, var: &str) -> bool {
        if !self.written.contains(var) {
            return false;
        }
        if self.untyped.contains(var) {
            return true;
        }
        let Some(decls) = self.typed.get(var) else { return false };
        let at = sem.var_owner(owner, var).unwrap_or_else(|| owner.to_string());
        decls.iter().any(|d| *d == at || sem.is_subtype(d, &at) || sem.is_subtype(&at, d))
    }

    /// The var names written through a receiver that could not be typed.
    pub fn untyped(&self) -> &BTreeSet<String> {
        &self.untyped
    }

    /// The index of the typed writes `sets` hold (`(declaring type or UNTYPED_WRITE, var)` per proc).
    pub fn from_facts(sets: Vec<Vec<(String, String)>>) -> WriteIndex {
        let mut w = WriteIndex::default();
        for (owner, var) in sets.into_iter().flatten() {
            w.written.insert(var.clone());
            if owner == UNTYPED_WRITE {
                w.untyped.insert(var);
            } else {
                w.typed.entry(var).or_default().insert(owner);
            }
        }
        w
    }

    pub fn build(sem: &Sem) -> WriteIndex {
        let procs: Vec<ProcRef> = sem.objtree.iter_types().flat_map(|t| t.iter_self_procs().collect::<Vec<_>>()).filter(|p| !p.is_builtin()).collect();
        // The facts depend on the declared types of vars, so the structure is the context.
        super::body_facts::indexed(sem, "writes-typed", sem.structure_digest(), &procs, |p| typed_writes(sem, p), WriteIndex::from_facts)
    }
}

/// The `(declaring type, var)` pairs one proc's body writes (a constructor's writes are init and do not count); the type is [`UNTYPED_WRITE`]
/// when the receiver has no static type. Sorted.
pub fn typed_writes(sem: &Sem, p: ProcRef) -> Vec<(String, String)> {
    let mut out: BTreeSet<(String, String)> = BTreeSet::new();
    let ctor = matches!(p.name(), "New" | "Initialize" | "initialize" | "Init");
    let Some(code) = &*p.get().code else { return Vec::new() };
    if ctor {
        return Vec::new();
    }
    let owner = if p.ty().get().path.is_empty() { "/".to_string() } else { p.ty().get().path.clone() };
    // Every local and parameter of the proc: a write of one is no write of a var. Name -> static type.
    let mut locals: HashMap<String, Option<String>> = HashMap::new();
    for prm in p.get().parameters.iter() {
        locals.insert(prm.name.clone(), type_str(&prm.var_type));
    }
    collect_locals(code, &mut locals);
    let mut record = |term: &dreammaker::ast::Spanned<Term>, follow: &[dreammaker::ast::Spanned<Follow>]| {
        let Some((recv, var)) = write_target(sem, &owner, &locals, term, follow) else { return };
        out.insert(match recv {
            Receiver::Local => return,
            Receiver::Typed(t) => (t, var),
            Receiver::Unknown => (UNTYPED_WRITE.to_string(), var),
        });
    };
    super::ast::walk_block(code, &mut |e, _| {
        if let Expression::AssignOp { lhs, .. } = e {
            if let Expression::Base { term, follow } = &**lhs {
                record(term, follow);
            }
        }
        if let Expression::Base { term, follow } = e {
            if let Some(Follow::Unary(op)) = follow.last().map(|f| &f.elem) {
                if matches!(op, dreammaker::ast::UnaryOp::PreIncr | dreammaker::ast::UnaryOp::PostIncr | dreammaker::ast::UnaryOp::PreDecr | dreammaker::ast::UnaryOp::PostDecr) {
                    record(term, &follow[..follow.len() - 1]);
                }
            }
        }
    });
    out.into_iter().collect()
}

enum Receiver {
    /// The write is of a local or a parameter.
    Local,
    /// The type that declares the var.
    Typed(String),
    Unknown,
}

fn collect_locals(b: &Block, out: &mut HashMap<String, Option<String>>) {
    use dreammaker::ast::Statement;
    for st in b.iter() {
        match &st.elem {
            Statement::Var(vs) => {
                out.insert(vs.name.clone(), type_str(&vs.var_type));
            }
            Statement::Vars(list) => {
                for vs in list.iter() {
                    out.insert(vs.name.clone(), type_str(&vs.var_type));
                }
            }
            Statement::ForList(fl) => {
                out.insert(fl.name.as_str().to_string(), fl.var_type.as_ref().and_then(type_str));
            }
            _ => {}
        }
        for nb in super::ast::stmt_blocks(&st.elem) {
            collect_locals(nb, out);
        }
    }
}

/// What a write to the lvalue `term` `follow` reaches: the var name and where it lives.
fn write_target(sem: &Sem, owner: &str, locals: &HashMap<String, Option<String>>, term: &dreammaker::ast::Spanned<Term>, follow: &[dreammaker::ast::Spanned<Follow>]) -> Option<(Receiver, String)> {
    match follow.last().map(|f| &f.elem) {
        Some(Follow::Index(..)) => write_target(sem, owner, locals, term, &follow[..follow.len() - 1]),
        Some(Follow::Field(_, n)) => {
            let var = n.as_str().to_string();
            let recv = receiver_type(sem, owner, locals, term, &follow[..follow.len() - 1]);
            Some((declaring(sem, recv, &var), var))
        }
        None => match &term.elem {
            Term::Ident(n) => {
                if locals.contains_key(n.as_str()) {
                    return Some((Receiver::Local, n.clone()));
                }
                // A bare name is a var of the proc's own type, or a global.
                Some((declaring(sem, Some(owner.to_string()), n), n.clone()))
            }
            _ => None,
        },
        _ => None,
    }
}

fn declaring(sem: &Sem, recv: Option<String>, var: &str) -> Receiver {
    match recv {
        Some(t) => match sem.var_owner(&t, var) {
            Some(d) => Receiver::Typed(d),
            // The receiver's static type has no such var (declared on a subtype, a global, a built-in): it stays conservative.
            None => Receiver::Unknown,
        },
        None => Receiver::Unknown,
    }
}

/// The static type of `term` `follow` (`src`, a typed local or parameter, a typed var of the proc's type, a field chain of those).
fn receiver_type(sem: &Sem, owner: &str, locals: &HashMap<String, Option<String>>, term: &dreammaker::ast::Spanned<Term>, follow: &[dreammaker::ast::Spanned<Follow>]) -> Option<String> {
    let mut cur: Option<String> = match &term.elem {
        Term::Ident(n) if n.as_str() == "src" => Some(owner.to_string()),
        Term::Ident(n) if n.as_str() == "usr" => None,
        Term::Ident(n) => match locals.get(n.as_str()) {
            Some(t) => t.clone(),
            None => sem.var_decl(owner, n).map(|v| v.declared).filter(|d| !d.is_empty()),
        },
        _ => None,
    };
    for fo in follow {
        match &fo.elem {
            Follow::Field(_, n) => cur = cur.and_then(|c| sem.var_decl(&c, n.as_str())).map(|v| v.declared).filter(|d| !d.is_empty()),
            _ => cur = None,
        }
    }
    cur
}

/// The var names one proc's body writes (a constructor's writes are init and do not count).
pub fn proc_writes(p: ProcRef) -> HashSet<String> {
    let mut s = HashSet::new();
    let name = p.name();
    let ctor = matches!(name, "New" | "Initialize" | "initialize" | "Init");
    if let Some(code) = &*p.get().code {
        collect_writes(code, ctor, &mut s);
    }
    s
}

pub fn collect_writes_pub(code: &Block, out: &mut HashSet<String>) {
    collect_writes(code, false, out)
}

fn collect_writes(code: &Block, ctor: bool, out: &mut HashSet<String>) {
    super::ast::walk_block(code, &mut |e, _| {
        if let Expression::AssignOp { lhs, .. } = e {
            if let Some(n) = lvalue_name(lhs) {
                // A constructor's writes are init; a var only assigned there stays constant.
                if !ctor {
                    out.insert(n);
                }
            }
        }
        // `x++` / `--x` and list mutators are follows/unary; approximate: a `++`/`--` is an AssignOp in DM's AST for postfix? it is a Unary follow.
        if let Expression::Base { term, follow } = e {
            if let Some(Follow::Unary(op)) = follow.last().map(|f| &f.elem) {
                if matches!(op, dreammaker::ast::UnaryOp::PreIncr | dreammaker::ast::UnaryOp::PostIncr | dreammaker::ast::UnaryOp::PreDecr | dreammaker::ast::UnaryOp::PostDecr) && !ctor {
                    if let Some(n) = lvalue_name_of(term, &follow[..follow.len() - 1]) {
                        out.insert(n);
                    }
                }
            }
        }
    });
}

/// The var name an lvalue assigns (`x`, `a.b.x` -> "x").
pub fn lvalue_name(e: &Expression) -> Option<String> {
    match e {
        Expression::Base { term, follow } => lvalue_name_of(term, follow),
        _ => None,
    }
}

pub(super) fn lvalue_name_of(term: &dreammaker::ast::Spanned<Term>, follow: &[dreammaker::ast::Spanned<Follow>]) -> Option<String> {
    match follow.last().map(|f| &f.elem) {
        Some(Follow::Field(_, n)) => Some(n.as_str().to_string()),
        Some(Follow::Index(..)) => lvalue_name_of(term, &follow[..follow.len() - 1]),
        None => match &term.elem {
            Term::Ident(n) => Some(n.clone()),
            _ => None,
        },
        _ => None,
    }
}

fn type_str(vt: &VarType) -> Option<String> {
    if vt.type_path.is_empty() {
        None
    } else {
        Some(format!("/{}", vt.type_path.join("/")))
    }
}

