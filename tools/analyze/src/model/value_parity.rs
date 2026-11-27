//! Part of `analyze sem model-parity`: var values (whether a var has an initializer, and what it folds to) and proc resolution (what a
//! name resolves to from every type, and the definition each one overrides), the view against the converted tree.

use super::builtins::Const;
use super::Model;
use crate::sem::Sem;

fn converted_const(c: &Option<dreammaker::constants::Constant>) -> Option<Const> {
    use dreammaker::constants::Constant;
    c.as_ref().map(|c| match c {
        Constant::Null(_) => Const::Null,
        Constant::Float(f) => Const::Float(*f),
        Constant::String(s) => Const::String(s.to_string()),
        Constant::Resource(s) => Const::Resource(s.to_string()),
        _ => Const::Other,
    })
}

fn same(a: &Option<Const>, b: &Option<Const>) -> bool {
    match (a, b) {
        (Some(Const::Float(x)), Some(Const::Float(y))) => x == y || (x.is_nan() && y.is_nan()),
        _ => a == b,
    }
}

pub fn run(sem: &Sem, model: &Model, examples_per: usize) -> usize {
    let mut total = 0;
    let mut report = |label: &str, compared: usize, examples: Vec<String>, differ: usize| {
        println!("{label:<22} {compared:>8} compared {differ:>7} differ");
        for e in examples.iter().take(examples_per) {
            println!("    {e}");
        }
        total += differ;
    };
    let folded = model.folded();
    let (mut c_init, mut d_init, mut e_init) = (0, 0, Vec::new());
    let (mut c_const, mut d_const, mut e_const) = (0, 0, Vec::new());
    let (mut c_res, mut d_res, mut e_res) = (0, 0, Vec::new());
    let (mut c_par, mut d_par, mut e_par) = (0, 0, Vec::new());
    for ty in sem.objtree.iter_types() {
        let t = ty.get();
        let path = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
        let Some(native) = model.ty(&path) else { continue };
        for (name, v) in &t.vars {
            if v.value.location.is_builtins() || name == "parent_type" {
                continue;
            }
            let last = native.vars().filter(|m| m.name() == name).last();
            let has = last.is_some_and(|m| m.has_value());
            c_init += 1;
            if has != v.value.expression.is_some() {
                d_init += 1;
                e_init.push(format!("{path}/{name}: converted {} native {has}", v.value.expression.is_some()));
            }
            let want = converted_const(&v.value.constant);
            let got = folded.values.get(&(native.id, name.to_string())).cloned().flatten().map(|v| v.kind());
            c_const += 1;
            if !same(&want, &got) {
                d_const += 1;
                e_const.push(format!("{path}/{name}: {want:?} vs {got:?}"));
            }
        }
        for name in t.procs.keys() {
            let want = ty.get_proc(name).map(|p| (p.ty().get().path.clone(), p.is_builtin(), sem.rel(p.get().location).to_string(), p.get().location.line));
            let got = native.proc(name).map(|p| {
                // A builtin sits on line 1 of dreammaker's builtins file.
                let (file, line) = if p.is_builtin() { (String::new(), 1) } else { p.site().and_then(|s| model.line(s)).unwrap_or_default() };
                let owner = p.owner().path();
                (if owner == "/" { String::new() } else { owner.to_string() }, p.is_builtin(), file, line)
            });
            c_res += 1;
            if want != got {
                d_res += 1;
                e_res.push(format!("{path}/{name}: {want:?} vs {got:?}"));
            }
            let (Some(p), Some(q)) = (ty.get_proc(name), native.proc(name)) else { continue };
            let want = p.parent_proc().map(|x| (x.ty().get().path.clone(), x.is_builtin(), x.get().location.line));
            let got = q.parent_proc().map(|x| {
                let owner = x.owner().path();
                (if owner == "/" { String::new() } else { owner.to_string() }, x.is_builtin(), if x.is_builtin() { 1 } else { x.site().and_then(|s| model.line(s)).map_or(0, |l| l.1) })
            });
            c_par += 1;
            if want != got {
                d_par += 1;
                e_par.push(format!("{path}/{name}: {want:?} vs {got:?}"));
            }
        }
    }
    report("var initializer", c_init, e_init, d_init);
    report("var constant", c_const, e_const, d_const);
    report("proc resolution", c_res, e_res, d_res);
    report("proc parent", c_par, e_par, d_par);
    total
}
