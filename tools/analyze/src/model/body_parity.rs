//! Part of `analyze sem model-parity`: every proc body walked both ways, the converted body through `sem::ast::walk_block` (each
//! expression and its statement's line) and the typed body through `model::walk::walk_block`, compared visit by visit.

use std::collections::HashMap;

use super::expr::{literal, Form, Hop, Lit, Root};
use super::{Member, Model};
use crate::sem::Sem;

fn converted_sig(e: &dreammaker::ast::Expression) -> String {
    use dreammaker::ast::{Expression, Follow, Term};
    match e {
        Expression::Base { term, follow } => {
            let mut s = match &term.elem {
                Term::Ident(n) => format!("id:{n}"),
                Term::Call(n, a) => format!("call:{n}/{}", a.len()),
                Term::Int(_) | Term::Float(_) => "num".into(),
                Term::String(s) => format!("str:{s}"),
                Term::Resource(_) => "res".into(),
                Term::InterpString(..) => "interp".into(),
                Term::Null => "null".into(),
                Term::List(a) => format!("list/{}", a.len()),
                Term::NewPrefab { .. } => "newp".into(),
                Term::NewImplicit { .. } => "newi".into(),
                Term::NewMiniExpr { .. } => "newm".into(),
                Term::Prefab(_) => "prefab".into(),
                Term::SelfCall(a) => format!("self/{}", a.len()),
                Term::ParentCall(a) => format!("parent/{}", a.len()),
                Term::Expr(_) => "group".into(),
                Term::Input { .. } => "input".into(),
                Term::Locate { .. } => "locate".into(),
                Term::Pick(_) => "pick".into(),
                Term::DynamicCall(..) => "dyn".into(),
                Term::ExternalCall { .. } => "ext".into(),
                Term::__PROC__ => "id:__PROC__".into(),
                Term::__TYPE__ => "id:__TYPE__".into(),
                Term::__IMPLIED_TYPE__ => "id:__IMPLIED_TYPE__".into(),
                _ => "other".into(),
            };
            for f in follow.iter() {
                s.push_str(&match &f.elem {
                    Follow::Field(_, n) => format!(".{n}"),
                    Follow::Call(_, n, a) => format!(".{n}()/{}", a.len()),
                    Follow::Index(..) => "[]".into(),
                    Follow::StaticField(n) => format!("::{n}"),
                    Follow::ProcReference(n) => format!("::{n}()"),
                    Follow::Unary(_) => "u".into(),
                    _ => "?".into(),
                });
            }
            s
        }
        Expression::BinaryOp { .. } => "bin".into(),
        Expression::AssignOp { .. } => "asg".into(),
        Expression::TernaryOp { .. } => "tern".into(),
    }
}

fn native_sig(f: &Form<'_>) -> String {
    match f {
        Form::Chain(c) => {
            let mut s = match &c.root {
                Root::Ident(n) => format!("id:{n}"),
                Root::Call { name, args } => format!("call:{name}/{}", args.len()),
                Root::Literal(t) => match literal(t) {
                    Lit::Null => "null".into(),
                    Lit::Int(_) | Lit::Float(_) => "num".into(),
                    Lit::String(s) => format!("str:{s}"),
                    Lit::Resource(_) => "res".into(),
                    Lit::Interp(_) => "interp".into(),
                    Lit::Bad => "other".into(),
                },
                Root::List(a) => format!("list/{}", a.len()),
                Root::NewPrefab { .. } => "newp".into(),
                Root::NewImplicit { .. } => "newi".into(),
                Root::NewMini { .. } => "newm".into(),
                Root::Prefab { .. } => "prefab".into(),
                Root::SelfCall(a) => format!("self/{}", a.len()),
                Root::ParentCall(a) => format!("parent/{}", a.len()),
                Root::Group(_) => "group".into(),
                Root::Input { .. } => "input".into(),
                Root::Locate { .. } => "locate".into(),
                Root::Pick(_) => "pick".into(),
                Root::DynamicCall { .. } => "dyn".into(),
                Root::ExternalCall { .. } => "ext".into(),
                Root::Opaque(_) => "other".into(),
            };
            for h in &c.hops {
                s.push_str(&match h {
                    Hop::Field { name, .. } => format!(".{name}"),
                    Hop::Call { name, args, .. } => format!(".{name}()/{}", args.len()),
                    Hop::Index { .. } => "[]".into(),
                    Hop::Static { name, .. } => format!("::{name}"),
                    Hop::ProcRef { name, .. } => format!("::{name}()"),
                    Hop::Unary { .. } => "u".into(),
                });
            }
            s
        }
        Form::Binary { .. } => "bin".into(),
        Form::Assign { .. } => "asg".into(),
        Form::Ternary { .. } => "tern".into(),
    }
}

/// Returns the number of bodies whose walks differ.
pub fn run(sem: &Sem, model: &Model, examples_per: usize) -> usize {
    let mut compared = 0usize;
    let mut differ = 0usize;
    let mut examples = Vec::new();
    for ty in sem.objtree.iter_types() {
        let t = ty.get();
        let path = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
        let Some(native) = model.ty(&path) else { continue };
        let mut nprocs: HashMap<&str, Vec<Member<'_>>> = HashMap::new();
        for m in native.procs() {
            nprocs.entry(m.name()).or_default().push(m);
        }
        for (name, p) in &t.procs {
            let values: Vec<_> = p.value.iter().filter(|v| !v.location.is_builtins()).collect();
            let members = nprocs.get(name.as_str()).cloned().unwrap_or_default();
            if values.len() != members.len() {
                continue;
            }
            for (v, m) in values.iter().zip(&members) {
                let Some(code) = v.code.as_ref() else { continue };
                let mut want: Vec<(String, u32)> = Vec::new();
                crate::sem::ast::walk_block(code, &mut |e, line| want.push((converted_sig(e), line)));
                let mut got: Vec<(String, u32)> = Vec::new();
                if let Some(body) = m.body() {
                    super::walk::walk_block(body, &mut |visit, at| {
                        let line = model.line(at).map_or(0, |(_, l)| l);
                        got.push((native_sig(&visit.form), line));
                    });
                }
                compared += 1;
                if want != got {
                    differ += 1;
                    if examples.len() < examples_per {
                        let first = want.iter().zip(&got).position(|(a, b)| a != b).unwrap_or(want.len().min(got.len()));
                        examples.push(format!("{path}/{name}: at {first}: {:?} vs {:?} ({} vs {} visits)", want.get(first), got.get(first), want.len(), got.len()));
                    }
                }
            }
        }
    }
    println!("{:<22} {compared:>8} compared {differ:>7} differ", "body walks");
    for e in &examples {
        println!("    {e}");
    }
    differ
}
