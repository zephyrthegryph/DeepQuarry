//! Read receipts (`dq_analyze::model::reads`): a judgement's receipt names what it read under the front end delta's stable keys, a miss
//! included, and `Receipt::holds` keeps it only while the delta names none of it.

mod common;

use std::path::PathBuf;
use std::sync::Arc;

use dm_tree::frontend::{Change, DeclarationKey, FrontendDelta};
use dm_tree::MemberKind;
use dq_analyze::model::reads::{self, LookupKind, Read};
use dq_analyze::run::{Engine, Options};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

fn delta(declarations: Vec<(DeclarationKey, Change)>, bodies: Vec<(DeclarationKey, Change)>) -> FrontendDelta {
    FrontendDelta { base: 1, revision: 2, files: vec![Arc::from("code/a.dm")], declarations, bodies }
}

#[test]
fn a_receipt_names_what_was_read_and_holds_until_it_changes() {
    common::dmbc_parse();
    let base = std::env::temp_dir().join(format!("dq-model-reads-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    std::fs::create_dir_all(base.join("code")).unwrap();
    std::fs::write(base.join("code/a.dm"), "/obj/thing\n\tvar/x = 1\n/obj/thing/proc/poke()\n\treturn x\n").unwrap();
    let opts = Options { root: base.clone(), lints: vec!["sem/keys".to_string()], no_cache: true, raw: true, scopes_from: Some(repo_root()), ..Default::default() };
    let engine = Engine::new(dq_analyze::run::registry(), opts).expect("engine");
    let sem = dq_analyze::sem::sem_for(&engine.tree).expect("model");
    let ty = sem.ty("/obj/thing").expect("type");

    // Nothing is recorded outside a recording.
    assert!(!reads::active());
    let ((declared, missing, body), receipt) = reads::recording(|| {
        let declared = ty.var_declaration("x").map(|d| d.declared.clone());
        let missing = ty.var_declaration("nope").is_none();
        let body = ty.proc("poke").and_then(|p| p.body()).map(|b| b.len());
        (declared, missing, body)
    });
    assert_eq!(declared.as_deref(), Some(""));
    assert!(missing);
    assert_eq!(body, Some(1));
    let lookup = |name: &str, kind| Read::Lookup { owner: Arc::from("/obj/thing"), name: Arc::from(name), kind };
    assert!(receipt.reads.contains(&lookup("x", LookupKind::Var)), "{:?}", receipt.reads);
    assert!(receipt.reads.contains(&lookup("nope", LookupKind::Var)), "a miss is a read: {:?}", receipt.reads);
    let poke = receipt.reads.iter().find_map(|r| match r {
        Read::Body(k) => Some(k.clone()),
        _ => None,
    });
    let poke = poke.expect("the body read");
    assert_eq!(poke.owner.as_ref(), "/obj/thing");
    assert_eq!(poke.member.as_ref().map(|(n, k)| (n.as_ref(), *k)), Some(("poke", MemberKind::Proc)));

    // An empty delta keeps it; an unrelated change keeps it; the body it read, or a new declaration of a name it missed, does not.
    assert!(receipt.holds(&FrontendDelta::default()));
    let other = DeclarationKey { file: Arc::from("code/b.dm"), owner: Arc::from("/obj/other"), member: Some((Arc::from("y"), MemberKind::Var)), ordinal: 0 };
    assert!(receipt.holds(&delta(vec![(other, Change::Changed)], vec![])));
    assert!(!receipt.holds(&delta(vec![], vec![(poke.clone(), Change::Changed)])));
    let appeared = DeclarationKey { file: Arc::from("code/c.dm"), owner: Arc::from("/obj"), member: Some((Arc::from("nope"), MemberKind::Var)), ordinal: 0 };
    assert!(!receipt.holds(&delta(vec![(appeared, Change::Added)], vec![])));
    // A body that only moved keeps a judgement that read it but not its site.
    assert!(receipt.holds(&delta(vec![], vec![(poke, Change::Moved)])));
    let _ = std::fs::remove_dir_all(&base);
}
