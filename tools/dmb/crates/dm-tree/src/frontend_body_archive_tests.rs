use super::*;
use std::path::Path;

struct Files;
impl dm_preprocess::SourceProvider for Files {
    fn read(&self, path: &Path) -> Result<String, String> {
        Ok(match path.file_name().and_then(|name| name.to_str()) {
            Some("p.dme") => "#include \"decl.dm\"\n#include \"body.dm\"\n",
            Some("decl.dm") => "/datum/example\n    var/saved\n/datum/example\n    var/other = 1\n",
            Some("body.dm") => "/datum/example/proc/test(datum/value)\n    saved = value\n/datum/example\n    other = 2\n",
            _ => return Err(format!("unexpected fixture source {}", path.display())),
        }
        .to_owned())
    }
}
#[test]
fn archive_apis_borrow_semantic_and_body_roster_owners() {
    let frontend = build(Path::new("p.dme"), &Files, &Default::default(), 1).unwrap();
    let archive = frontend.body_archive().unwrap();
    let separate = frontend.body_archive().unwrap();
    assert!(std::ptr::eq(
        archive.tree(),
        frontend.snapshot.tree.as_ref()
    ));
    assert!(std::ptr::eq(
        archive.occurrences().as_ptr(),
        frontend.bodies.as_ptr()
    ));
    assert_eq!(archive.occurrences().len(), frontend.bodies.len());
    let body = archive.parse(0).unwrap();
    assert!(body.belongs_to(&archive));
    assert!(
        !body.belongs_to(&separate),
        "equal source/owners do not reissue an archive body"
    );
    assert!(std::ptr::eq(body.tree(), archive.tree()));
}
#[test]
fn archived_member_origins_survive_frontend_release() {
    let (archive, member, body_start, expected_member, expected_body) = {
        let frontend = build(Path::new("p.dme"), &Files, &Default::default(), 1).unwrap();
        let archive = frontend.body_archive().unwrap();
        let tree = frontend.snapshot.tree.as_ref();
        let owner = tree
            .lookup_type(dm_ir::SymbolId::of("/datum/example"))
            .unwrap();
        let member = tree
            .resolve(owner, dm_ir::SymbolId::of("saved"), crate::MemberKind::Var)
            .unwrap();
        let ordinal = frontend
            .snapshot
            .occurrences
            .for_target(crate::Target::Member(member))[0];
        let expected_member = frontend
            .source_export_mapping()
            .unwrap()
            .location_of(ordinal)
            .unwrap();
        let body_start = archive.occurrences()[0].expanded_span.start;
        let expected_body = frontend.location(body_start).unwrap();
        (archive, member, body_start, expected_member, expected_body)
    };
    assert_eq!(archive.member_location(member), Some(expected_member));
    assert_eq!(archive.location(body_start), Some(expected_body));
    let member = archive.member_location(member).unwrap();
    assert!(member.path.ends_with("decl.dm"));
    assert_eq!(member.line, 2);
    assert!(archive.parse(0).unwrap().belongs_to(&archive));
}

#[test]
fn archived_member_origins_match_existing_target_index_with_repeated_declarations() {
    let (archive, expected) = {
        let frontend = build(Path::new("p.dme"), &Files, &Default::default(), 1).unwrap();
        let expected: Vec<_> = frontend
            .snapshot
            .tree
            .declarations()
            .iter()
            .filter_map(|target| {
                let crate::Target::Member(member) = *target else {
                    return None;
                };
                let origin = frontend
                    .snapshot
                    .occurrences
                    .for_target(*target)
                    .first()
                    .and_then(|ordinal| {
                        frontend
                            .source_export_mapping()
                            .unwrap()
                            .location_of(*ordinal)
                    });
                Some((member, origin))
            })
            .collect();
        (frontend.body_archive().unwrap(), expected)
    };
    assert!(expected.len() >= 4);
    for (member, location) in expected {
        assert_eq!(
            archive.member_location(member),
            location,
            "member {member:?}"
        );
    }
}
