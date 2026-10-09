//! Explicit one-shot ownership transition; revision and analysis APIs stay full.
use super::FrontendRevision;
use std::sync::Arc;
impl FrontendRevision {
    /// Release preprocessing execution inputs after nontext capture finishes.
    /// Shared or previously issued revisions remain completely unchanged.
    pub fn try_into_compile_only(self) -> Result<Self, Self> {
        if Arc::strong_count(&self.0) != 1 || Arc::weak_count(&self.0) != 0 {
            return Err(self);
        }
        match Arc::try_unwrap(self.0) {
            Ok(mut frontend) => {
                for region in &mut frontend.plan.regions {
                    region.segments = Vec::new();
                    region.effects = Vec::new();
                }
                Ok(Self::new(frontend))
            }
            Err(frontend) => Err(Self(frontend)),
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::{collections::BTreeMap, path::Path};
    struct Memory;
    impl dm_preprocess::SourceProvider for Memory {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("#define ANSWER 7\n/proc/probe()\n    return ANSWER\n".into())
        }
    }
    fn frontend() -> super::super::ColdFrontend {
        super::super::build(Path::new("project.dme"), &Memory, &BTreeMap::new(), 1).unwrap()
    }
    #[test]
    fn one_shot_releases_execution_inputs_preserving_source_authority() {
        let original = frontend();
        let full = original.clone();
        let body = original.bodies[0].clone();
        let location = original.location(body.expanded_span.start).unwrap();
        let bytes = original.body_input(&body).unwrap().source().to_owned();
        let tree = original.snapshot.tree.identity();
        let compact = FrontendRevision::new(original)
            .try_into_compile_only()
            .unwrap();
        assert!(compact
            .plan
            .regions
            .iter()
            .all(|r| r.segments.is_empty() && r.effects.is_empty()));
        assert_eq!(compact.snapshot.tree.identity(), tree);
        assert_eq!(compact.body_input(&body).unwrap().source(), bytes);
        let after = compact.location(body.expanded_span.start).unwrap();
        assert_eq!(after.span, location.span);
        assert_eq!(after.semantic_path, location.semantic_path);
        assert_eq!(after.include_chain, location.include_chain);
        assert_eq!(after.encounter_ordinal, location.encounter_ordinal);
        assert_eq!(after.line, location.line);
        assert!(full.plan.regions.iter().any(|r| !r.segments.is_empty()));
        let expanded = dm_preprocess::regions::expand_regions_text(&full.plan, 1);
        assert_eq!(expanded.text, full.expanded.text);
        let issuance = compact.issuance();
        let rejected = compact.try_into_compile_only().unwrap_err();
        assert!(issuance.matches(&rejected));
    }
    #[test]
    fn shared_revision_returns_original_without_rewriting_plan() {
        let revision = FrontendRevision::new(frontend());
        let shared = revision.clone();
        let rejected = revision.try_into_compile_only().unwrap_err();
        assert!(Arc::ptr_eq(&rejected.0, &shared.0));
        assert!(rejected.plan.regions.iter().any(|r| !r.segments.is_empty()));
    }
}
