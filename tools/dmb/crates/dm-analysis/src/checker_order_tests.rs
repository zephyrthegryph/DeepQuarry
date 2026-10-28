use super::*;
use dm_tree::frontend::build;
use std::{path::Path, sync::Arc};

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(source: &'static str) -> ColdFrontend {
    build(Path::new("p.dme"), &Source(source), &Default::default(), 1).unwrap()
}
fn names(front: &ColdFrontend) -> Vec<String> {
    bodies(front)
        .unwrap()
        .into_iter()
        .map(|(_, body)| {
            let tree = &front.snapshot.tree;
            let member = tree.member(body.member).unwrap();
            let owner = tree.type_node(member.owner).unwrap();
            format!(
                "{}/{}",
                tree.symbols().text(owner.path).unwrap(),
                tree.symbols().text(member.name).unwrap()
            )
        })
        .collect()
}

#[test]
fn path_components_not_raw_strings_define_lexical_preorder() {
    let mut paths = ["/a-b", "/a/x", "/a", "/", "/a/y"];
    paths.sort_by_key(|path| components(path));
    assert_eq!(paths, ["/", "/a", "/a/x", "/a/y", "/a-b"]);
}

#[test]
fn explicit_parent_does_not_reorder_lexical_path_children() {
    let front = frontend(concat!(
        "/datum/z/proc/probe()\n    return 1\n",
        "/datum/a\n    parent_type = /datum/z\n",
        "/datum/a/probe()\n    return 2\n",
        "/datum/a/child\n    parent_type = /datum\n",
        "/datum/a/child/proc/probe()\n    return 3\n",
    ));
    assert_eq!(
        names(&front),
        ["/datum/a/probe", "/datum/a/child/probe", "/datum/z/probe"]
    );
}

#[test]
fn interleaved_override_groups_match_independent_checker_fixture() {
    let front = frontend(include_str!(
        "../../../fixtures/unified_checks/proc_group_order.dm"
    ));
    let lines: Vec<_> = bodies(&front)
        .unwrap()
        .iter()
        .map(|(_, body)| body.source.line)
        .collect();
    assert_eq!(lines, [4, 8, 10, 12, 6]);
}

#[test]
fn bodyless_declaration_establishes_group_order() {
    let front = frontend(concat!(
        "/datum/test/proc/z()\n",
        "/datum/test/proc/a()\n    return 0\n",
        "/datum/test/z()\n    return 1\n",
    ));
    let names = names(&front);
    let a = names.iter().position(|name| name.ends_with("/a")).unwrap();
    let last_z = names.iter().rposition(|name| name.ends_with("/z")).unwrap();
    assert!(last_z < a, "{names:?}");
}

#[test]
fn late_formal_precedes_earlier_override_without_moving_group() {
    let front = frontend(concat!(
        "/datum/child/proc/beta()\n    return 0\n",
        "/datum/child/alpha()\n    return 1\n",
        "/datum/child/proc/gamma()\n    return 2\n",
        "/datum/child/proc/alpha()\n    return 3\n",
    ));
    let lines: Vec<_> = bodies(&front)
        .unwrap()
        .iter()
        .map(|(_, body)| body.source.line)
        .collect();
    assert_eq!(lines, [1, 7, 3, 5]);
}

#[test]
fn compatibility_roster_replacement_is_not_authorized_issuance() {
    let mut front = frontend("/proc/a()\n    return 1\n");
    front.bodies = Arc::from(front.bodies.to_vec());
    assert!(bodies(&front).is_err());
}
