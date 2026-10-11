use super::*;
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn revision(source: &'static str) -> FrontendRevision {
    FrontendRevision::new(
        crate::frontend::build(
            Path::new("delta.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap(),
    )
}
#[test]
fn procedure_delta_tracks_exact_source_and_declines_foreign_owners() {
    let old = revision("/proc/p()\n    return missing_name\n");
    let shifted = revision("\n/proc/p()\n    return missing_name\n");
    let delta = ProcedureInputDelta::issue(&old, &shifted).unwrap();
    assert!(delta.inputs().changed().is_empty());
    assert!(delta.authenticates(&old, &shifted));
    assert!(!delta.authenticates(&shifted, &old));
    assert!(!delta.authenticates(&old, &revision("\n/proc/p()\n    return missing_name\n")));
    let body = revision("/proc/p()\n    return another_missing_name\n");
    assert_eq!(
        ProcedureInputDelta::issue(&old, &body)
            .unwrap()
            .inputs()
            .changed()
            .len(),
        1
    );
}
#[test]
fn procedure_delta_never_certifies_negative_parent_signature_or_resource_reads() {
    let old = revision("/datum/a/proc/p(x)\n    return missing_name\n");
    for source in [
        "/datum/a/proc/p(x)\n    return missing_name\n/proc/missing_name()\n    return 1\n",
        "/datum/base\n/datum/a\n    parent_type = /datum/base\n/datum/a/proc/p(x)\n    return missing_name\n",
        "/datum/a/proc/p(x, y)\n    return missing_name\n",
    ] {
        let current = revision(source);
        let delta = ProcedureInputDelta::issue(&old, &current).unwrap();
        assert!(!delta.inputs().changed().is_empty());
        assert_eq!(delta.dependency_coverage(), DependencyCoverage::UncoveredAll);
    }
    let same = revision("/datum/a/proc/p(x)\n    return missing_name\n");
    let delta = ProcedureInputDelta::issue(&old, &same).unwrap();
    // Resource/config bytes can change outside these frontend inputs. Even
    // exact unchanged source and ABI therefore provide no read-domain proof.
    assert!(delta.inputs().changed().is_empty());
    assert_eq!(
        delta.dependency_coverage(),
        DependencyCoverage::UncoveredAll
    );
    let added =
        revision("/datum/a/proc/p(x)\n    return missing_name\n/proc/new_proc()\n    return 1\n");
    assert_eq!(
        ProcedureInputDelta::issue(&old, &added)
            .unwrap()
            .inputs()
            .added()
            .len(),
        1
    );
    assert_eq!(
        ProcedureInputDelta::issue(&added, &old)
            .unwrap()
            .inputs()
            .removed()
            .len(),
        1
    );
}
