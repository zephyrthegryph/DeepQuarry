//! Current source admission followed by the issued source-neutral callable index.
use super::*;
pub fn source_unit_identity(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
) -> Result<SourceUnitIdentity, String> {
    let issued = frontend.body_input(body).map_err(|error| error.message)?;
    from_issued(frontend, &issued)
}
pub(crate) fn from_issued(
    frontend: &ColdFrontend,
    issued: &dm_tree::frontend::IssuedBodyInput<'_>,
) -> Result<SourceUnitIdentity, String> {
    from_current_body(frontend, issued.occurrence())
}
pub(crate) fn from_current_body(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
) -> Result<SourceUnitIdentity, String> {
    let tree = &frontend.snapshot.tree;
    let node = tree
        .member(body.member)
        .ok_or("body member missing from immutable tree")?;
    tree.type_node(node.owner)
        .ok_or("body owner missing from immutable tree")?;
    if node.kind == MemberKind::Var {
        return Err("variable cannot own a procedure body".into());
    }
    let issued = frontend
        .callable_roster()?
        .identity_for_member(body.member)
        .ok_or("body missing from issued callable roster")?;
    Ok(SourceUnitIdentity {
        identity: UnitIdentity {
            owner: issued.owner,
            name: issued.name,
            namespace: if issued.verb {
                Namespace::Verb
            } else {
                Namespace::Proc
            },
            occurrence: issued.occurrence,
        },
        effective: frontend
            .callable_roster()?
            .effective(
                frontend
                    .callable_roster()?
                    .ordinal(body.member)
                    .ok_or("body ordinal missing")?,
            )
            .ok_or("body effective selection missing")?,
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    #[test]
    fn issued_index_matches_independent_override_chain_and_rejects_foreign_body() {
        let source="/datum/a/proc/p()\n    return 1\n/datum/a/p()\n    return 2\n/datum/a/verb/v()\n    return 3\n/datum/a/b/p()\n    return 4\n/datum/a/b/p()\n    return 5\n";
        let build = |source| {
            dm_tree::frontend::build(
                Path::new("project.dme"),
                &Source(source),
                &Default::default(),
                1,
            )
            .unwrap()
        };
        let frontend = build(source);
        for body in frontend.bodies.iter() {
            let tree = &frontend.snapshot.tree;
            let node = tree.member(body.member).unwrap();
            let occurrence = tree
                .override_chain(body.member)
                .into_iter()
                .filter(|id| {
                    let prior = tree.member(*id).unwrap();
                    prior.owner == node.owner && prior.kind == node.kind && prior.name == node.name
                })
                .count()
                - 1;
            let actual = source_unit_identity(&frontend, body).unwrap();
            assert_eq!(
                actual.identity,
                UnitIdentity {
                    owner: tree.type_node(node.owner).unwrap().path,
                    name: node.name,
                    namespace: if node.kind == MemberKind::Verb {
                        Namespace::Verb
                    } else {
                        Namespace::Proc
                    },
                    occurrence: occurrence as u32
                }
            );
            assert_eq!(
                actual.effective,
                tree.resolve(node.owner, node.name, node.kind) == Some(body.member)
            );
        }
        // Descriptors are admitted by exact declaration/member/path/span value,
        // then body_input returns this frontend's private issued row.
        let identical = build(source);
        let rebound = frontend.body_input(&identical.bodies[0]).unwrap();
        assert!(std::ptr::eq(rebound.occurrence(), &frontend.bodies[0]));
        let admitted = source_unit_identity(&frontend, &identical.bodies[0]).unwrap();
        let current = source_unit_identity(&frontend, &frontend.bodies[0]).unwrap();
        assert_eq!(admitted.identity, current.identity);
        assert_eq!(admitted.effective, current.effective);
        let foreign = build("/datum/a/proc/p()\n    return 1000\n");
        assert!(source_unit_identity(&frontend, &foreign.bodies[0]).is_err());
    }
}
