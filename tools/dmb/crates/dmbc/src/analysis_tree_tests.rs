//! Locations of the converted tree: a term, a follow and a call sit where dreammaker's parser places them.
use dreammaker::ast::{Expression, Follow, Statement, Term};
use std::fmt::Write as _;

fn fixture(name: &str, source: &str) -> dq_analyze::sem::model_store::Parsed {
    let dir = crate::test_scratch::dir(name);
    std::fs::write(dir.join("fixture.dm"), source).unwrap();
    std::fs::write(dir.join("test.dme"), "#include \"fixture.dm\"\n").unwrap();
    super::parse_for_analysis(&dir.join("test.dme"), true).expect("fixture parses")
}

fn walk_expr(e: &Expression, out: &mut String) {
    match e {
        Expression::Base { term, follow } => {
            let _ = write!(out, "term {}:{} ", term.location.line, term.location.column);
            term_children(&term.elem, out);
            for f in follow.iter() {
                let what = match &f.elem {
                    Follow::Call(_, n, args) => {
                        for a in args.iter() {
                            walk_expr(a, out);
                        }
                        format!("call {n}")
                    }
                    Follow::Field(_, n) => format!("field {n}"),
                    Follow::Index(_, i) => {
                        walk_expr(i, out);
                        "index".into()
                    }
                    Follow::Unary(u) => format!("unary {u:?}"),
                    other => format!("{other:?}"),
                };
                let _ = write!(out, "[{what} {}:{}] ", f.location.line, f.location.column);
            }
        }
        Expression::BinaryOp { lhs, rhs, .. } | Expression::AssignOp { lhs, rhs, .. } => {
            walk_expr(lhs, out);
            walk_expr(rhs, out);
        }
        Expression::TernaryOp { cond, if_, else_ } => {
            walk_expr(cond, out);
            walk_expr(if_, out);
            walk_expr(else_, out);
        }
    }
}

fn term_children(t: &Term, out: &mut String) {
    match t {
        Term::Call(_, args) | Term::List(args) => args.iter().for_each(|a| walk_expr(a, out)),
        Term::Expr(e) => walk_expr(e, out),
        Term::InterpString(_, parts) => parts.iter().for_each(|(e, _)| {
            if let Some(e) = e {
                walk_expr(e, out)
            }
        }),
        _ => {}
    }
}

fn body_locations(parsed: &dq_analyze::sem::model_store::Parsed, ty: &str, name: &str) -> String {
    let t = parsed.objtree.find(ty).expect("type");
    let p = t.get_proc(name).expect("proc");
    let mut out = String::new();
    let _ = write!(out, "proc {}:{} | ", p.get().location.line, p.get().location.column);
    for s in p.get().code.as_ref().expect("body").iter() {
        let _ = write!(out, "stmt {}:{} ", s.location.line, s.location.column);
        if let Statement::Expr(e) = &s.elem {
            walk_expr(e, &mut out);
        }
        out.push_str("| ");
    }
    out
}

#[test]
fn follows_sit_at_their_operator() {
    let parsed = fixture(
        "analysis-tree-follows",
        "/datum/x/proc/f(datum/a, datum/b)\n\ta.f().g()\n\tb.c++\n\ta.l[1]\n\tvar/s = \"[a.f().type]\"\n",
    );
    let got = body_locations(&parsed, "/datum/x", "f");
    // dreammaker: the proc at its `(`, a call or field at its `.`, an index at its `[`, a postfix operator at the operator.
    assert!(got.starts_with("proc 1:16 |"), "{got}");
    assert!(got.contains("stmt 2:2 term 2:2 [call f 2:3] [call g 2:7]"), "{got}");
    assert!(got.contains("term 3:2 [field c 3:3] [unary PostIncr 3:5]"), "{got}");
    assert!(got.contains("term 4:2 [field l 4:3] term 4:6 [index 4:5]"), "{got}");
}

#[test]
fn named_arguments_over_lines_keep_their_place() {
    let parsed = fixture(
        "analysis-tree-named",
        "#define LIFE(x) (x * 2)\n/datum/x/proc/f(atom/a, n)\n\tanimate(\n\t\ta,\n\t\tpixel_y = 1,\n\t\ttime = LIFE(n),\n\t\teasing = 1 | 2,\n\t)\n",
    );
    let got = body_locations(&parsed, "/datum/x", "f");
    assert!(got.contains("term 4:3 term 5:3"), "{got}");
    assert!(got.contains("term 6:3"), "{got}");
    assert!(got.contains("term 7:3"), "{got}");
}

#[test]
fn bare_word_line_keeps_its_siblings_on_the_type() {
    let parsed = fixture("analysis-tree-bare", "/obj/clown\n\tclown\n\tname = \"clown\"\n\tdesc = \"x\"\n");
    let t = parsed.objtree.find("/obj/clown").expect("type");
    assert!(t.get().vars.contains_key("desc"), "{:?}", t.get().vars.keys().collect::<Vec<_>>());
}

#[test]
fn rejected_new_form_is_a_parse_error() {
    let parsed = fixture("analysis-tree-new-index", "/datum/x/proc/f(list/row, at)\n\tat = new row[1](at)\n");
    let raw = parsed.raw.as_ref().expect("checker diagnostics");
    let got: Vec<String> = raw.stream.iter().map(|e| format!("{}:{} {}", e.location().line, e.location().column, e.description())).collect();
    assert_eq!(got, vec!["2:17 got '(', expected one of: operator, field access, ';'".to_string()], "{got:?}");
    assert_eq!(raw.summary.as_deref(), Some("parsed 0/1 proc bodies (0%)"));
}

#[test]
fn macro_redefinition_and_stray_undef_warn() {
    let parsed = fixture("analysis-tree-macros", "#define A 1\n#define A 2\n#undef B\n/datum/x\n");
    let raw = parsed.raw.as_ref().expect("checker diagnostics");
    let got: Vec<String> = raw.stream.iter().map(|e| format!("{}:{} {}", e.location().line, e.location().column, e.description())).collect();
    assert_eq!(got, vec!["2:9 macro redefined: A".to_string(), "3:8 macro undefined while not defined: B".to_string()], "{got:?}");
}

#[test]
fn macro_arguments_sit_at_the_invocation() {
    let parsed = fixture(
        "analysis-tree-macro-args",
        "#define CHECK(a, b) if(a != b) { world.log << \"x\" }\n/datum/x/proc/f(datum/d)\n\tCHECK(d.type, 1)\n\tCHECK(\n\t\td.type, 2)\n",
    );
    let got = body_locations(&parsed, "/datum/x", "f");
    // dreammaker places every token of an expansion, the arguments' among them, at the invocation.
    assert!(!got.contains("3:9") && !got.contains("3:10") && !got.contains("5:"), "{got}");
}
