use super::*;
use dm_tree::frontend::{
    BodyArchive, BodySyntax, BodySyntaxInput, BodySyntaxQueries, ColdFrontend, FrontendConfig,
};
use std::{path::Path, sync::Arc};
#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
#[derive(Debug)]
struct OriginalSyntax;
impl BodySyntaxQueries for OriginalSyntax {
    fn syntax(
        &self,
        input: &Arc<BodySyntaxInput>,
    ) -> Result<Arc<BodySyntax>, dm_tree::frontend::Diagnostic> {
        input.parse().map(Arc::new)
    }
}
fn build(source: &str) -> (ColdFrontend, Arc<BodyArchive>) {
    let seed = reference_hierarchy::seed();
    let front = dm_tree::frontend::build_with_config(
        Path::new("purity-settings.dme"),
        &Source(source.into()),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
    .with_body_queries(Arc::new(OriginalSyntax));
    let archive = front.body_archive().unwrap();
    (front, archive)
}
fn identity(archive: &BodyArchive, name: &str, occurrence: u32) -> dm_ir::ProcedureIdentity {
    for body in archive.occurrences() {
        let member = archive.tree().member(body.member).unwrap();
        if member.name == SymbolId::of(name)
            && archive.tree().member_occurrence(body.member) == Some(occurrence)
        {
            return dm_ir::ProcedureIdentity {
                owner: archive.tree().type_node(member.owner).unwrap().path,
                name: member.name,
                verb: member.kind == dm_tree::MemberKind::Verb,
                occurrence,
            };
        }
    }
    panic!("issued identity missing {name}/{occurrence}")
}
#[test]
fn purity_setting_permit_admits_true_primary_prefix_and_preserves_strict_defaults() {
    for value in ["1", "TRUE"] {
        let source=format!("/datum/target\n/proc/p() as /datum/target\n    set SpacemanDMM_should_be_pure = {value}\n    return null\n");
        let (_, archive) = build(&source);
        let tree = archive.tree();
        let profile = tree.checker_builtin_profile().unwrap();
        let id = identity(&archive, "p", 0);
        let permit = PuritySettingsPermit::issue(&archive, profile, id).unwrap();
        let span = permit.own_pure().unwrap();
        assert_eq!(&source[span.start..span.end], "set");
        assert_eq!(permit.identity(), id);
        assert!(validate_source_directives(tree, Some(&archive), id).is_err());
        assert!(
            return_hint_with_prefix(tree, tree, profile, id.owner, id.name, Some(&archive))
                .is_err()
        );
        validate_source_directives_for_purity(tree, Some(&archive), id, &permit).unwrap();
        assert_eq!(
            return_hint_with_prefix_for_purity(
                tree,
                tree,
                profile,
                id.owner,
                id.name,
                Some(&archive),
                &permit
            )
            .unwrap(),
            ReturnHint::direct("/datum/target")
        );
        assert_eq!(
            return_fix_hint_for_purity(
                tree,
                tree,
                profile,
                id.owner,
                id.name,
                Some(&archive),
                &permit
            )
            .unwrap(),
            ReturnFixHint::None
        );
    }
}
#[test]
fn purity_setting_permit_preserves_return_directive_order_without_metadata_rewrite() {
    for prefix in [
        "    set SpacemanDMM_should_be_pure=1\n    set SpacemanDMM_return_type=/datum/target\n",
        "    set SpacemanDMM_return_type=/datum/target\n    set SpacemanDMM_should_be_pure=1\n",
    ] {
        let (_, archive) = build(&format!(
            "/datum/target\n/proc/p()\n{prefix}    return null\n"
        ));
        let tree = archive.tree();
        let profile = tree.checker_builtin_profile().unwrap();
        let id = identity(&archive, "p", 0);
        let before = Resolver::resolve(
            tree,
            Q::SourceDeclarationChain {
                owner: id.owner,
                name: id.name,
                verb: id.verb,
            },
        );
        let permit = PuritySettingsPermit::issue(&archive, profile, id).unwrap();
        assert_eq!(
            return_hint_with_prefix_for_purity(
                tree,
                tree,
                profile,
                id.owner,
                id.name,
                Some(&archive),
                &permit
            )
            .unwrap(),
            ReturnHint::direct("/datum/target")
        );
        assert_eq!(
            before,
            Resolver::resolve(
                tree,
                Q::SourceDeclarationChain {
                    owner: id.owner,
                    name: id.name,
                    verb: id.verb
                }
            )
        );
    }
}
#[test]
fn purity_setting_permit_declines_false_invalid_duplicate_and_other_directive_policies() {
    for prefix in [
        "    set SpacemanDMM_should_be_pure=0\n",
        "    set SpacemanDMM_should_be_pure=FALSE\n",
        "    set SpacemanDMM_should_be_pure=2\n",
        "    set SpacemanDMM_should_be_pure=(1)\n",
        "    set SpacemanDMM_should_be_pure=1\n    set SpacemanDMM_should_be_pure=1\n",
        "    set SpacemanDMM_should_be_pure=1\n    set SpacemanDMM_other=1\n",
        "    set SpacemanDMM_should_be_pure=1\n    set SpacemanDMM_return_type=unknown_call()\n",
    ] {
        let (_, archive) = build(&format!("/proc/p()\n{prefix}    return null\n"));
        let profile = archive.tree().checker_builtin_profile().unwrap();
        assert!(
            PuritySettingsPermit::issue(&archive, profile, identity(&archive, "p", 0)).is_err(),
            "{prefix}"
        );
    }
}
#[test]
fn purity_setting_permit_ignores_late_and_nested_settings_after_initial_prefix() {
    for body in [
        "    return 1\n    set SpacemanDMM_should_be_pure=1\n",
        "    var/x=1\n    set SpacemanDMM_should_be_pure=1\n    return x\n",
        "    if(1)\n        set SpacemanDMM_should_be_pure=1\n    return null\n",
    ] {
        let (_, archive) = build(&format!("/proc/p()\n{body}"));
        let profile = archive.tree().checker_builtin_profile().unwrap();
        assert!(
            PuritySettingsPermit::issue(&archive, profile, identity(&archive, "p", 0))
                .unwrap()
                .own_pure()
                .is_none()
        );
    }
}
#[test]
fn purity_setting_permit_cannot_cross_original_archive_profile_or_callable() {
    let source="/proc/p()\n    set SpacemanDMM_should_be_pure=1\n    return null\n/proc/q()\n    return null\n";
    let (_, archive) = build(source);
    let (_, foreign) = build(source);
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().unwrap();
    let id = identity(&archive, "p", 0);
    let permit = PuritySettingsPermit::issue(&archive, profile, id).unwrap();
    assert!(PuritySettingsPermit::issue(&archive, PackedU128::new(profile.get() ^ 1), id).is_err());
    assert!(validate_source_directives_for_purity(tree, Some(&foreign), id, &permit).is_err());
    assert!(
        validate_source_directives_for_purity(foreign.tree(), Some(&foreign), id, &permit).is_err()
    );
    assert!(validate_source_directives_for_purity(
        tree,
        Some(&archive),
        identity(&archive, "q", 0),
        &permit
    )
    .is_err());
    assert!(return_hint_with_prefix_for_purity(
        tree,
        tree,
        profile,
        SymbolId::of("/"),
        SymbolId::of("abs"),
        Some(&archive),
        &permit
    )
    .is_err());
}

#[test]
fn purity_setting_permit_declines_override_annotations_but_does_not_copy_parent_flags() {
    let (_,archive)=build("/datum/base/proc/p()\n    set SpacemanDMM_should_be_pure=1\n    return null\n/datum/base/child/p()\n    return null\n");
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let parent = dm_ir::ProcedureIdentity {
        owner: SymbolId::of("/datum/base"),
        name: SymbolId::of("p"),
        verb: false,
        occurrence: 0,
    };
    let child = dm_ir::ProcedureIdentity {
        owner: SymbolId::of("/datum/base/child"),
        ..parent
    };
    assert!(PuritySettingsPermit::issue(&archive, profile, parent)
        .unwrap()
        .own_pure()
        .is_some());
    assert!(
        PuritySettingsPermit::issue(&archive, profile, child)
            .unwrap()
            .own_pure()
            .is_none(),
        "inheritance belongs to the effect consumer's actual source chain"
    );
    let (_,overridden)=build("/datum/base/proc/p()\n    return null\n/datum/base/child/p()\n    set SpacemanDMM_should_be_pure=1\n    return null\n");
    assert!(PuritySettingsPermit::issue(
        &overridden,
        overridden.tree().checker_builtin_profile().unwrap(),
        child
    )
    .is_err());
}
