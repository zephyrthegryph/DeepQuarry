//! Caller-issued stage-map interpretation; no compiler-specific domain roster.
use super::{CpuDomain, CpuSelector, ProfileGuard, Report};
use std::collections::{BTreeMap, BTreeSet};

pub type StageMap = BTreeMap<String, Vec<String>>;

fn prepare(map: &StageMap) -> Result<Vec<Vec<CpuSelector<'_>>>, String> {
    if map.is_empty() {
        return Err("profile stage map is empty".into());
    }
    let mut seen = BTreeSet::new();
    map.iter()
        .map(|(domain, names)| {
            if domain.trim().is_empty() || names.is_empty() {
                return Err(format!(
                    "profile domain {domain:?} has no name or selectors"
                ));
            }
            names
                .iter()
                .map(|name| {
                    let (stage, exclusive) = name
                        .strip_prefix("exclusive:")
                        .map_or((name.as_str(), false), |stage| (stage, true));
                    if stage.trim().is_empty() || stage.starts_with("exclusive:") {
                        return Err(format!("invalid profile selector {name:?}"));
                    }
                    if !seen.insert(name.as_str()) {
                        return Err(format!("duplicate profile selector {name:?}"));
                    }
                    Ok(if exclusive {
                        CpuSelector::Exclusive(stage)
                    } else {
                        CpuSelector::Inclusive(stage)
                    })
                })
                .collect()
        })
        .collect()
}

impl ProfileGuard {
    /// Export additive domain evidence using exactly the caller's stage mapping.
    /// Missing measured stages remain explicit unproved bounds, never zero CPU.
    pub fn finish_with_stage_map(
        self,
        sequential_stages: &[&str],
        map: &StageMap,
    ) -> Result<Report, String> {
        let selected = prepare(map)?;
        let domains: Vec<_> = map
            .keys()
            .zip(&selected)
            .map(|(name, selectors)| CpuDomain { name, selectors })
            .collect();
        self.finish_with_domains(sequential_stages, &domains)
    }
}

pub(super) fn selectors(domains: &[CpuDomain<'_>]) -> StageMap {
    domains
        .iter()
        .map(|domain| {
            (
                domain.name.to_owned(),
                domain
                    .selectors
                    .iter()
                    .map(|selector| match selector {
                        CpuSelector::Inclusive(name) => (*name).to_owned(),
                        CpuSelector::Exclusive(name) => format!("exclusive:{name}"),
                    })
                    .collect(),
            )
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn caller_mapping_preserves_order_and_exclusive_semantics() {
        let map = StageMap::from([
            (
                "body".into(),
                vec!["lower".into(), "exclusive:build".into()],
            ),
            ("input".into(), vec!["scan".into()]),
        ]);
        let selected = prepare(&map).unwrap();
        let domains: Vec<_> = map
            .keys()
            .zip(&selected)
            .map(|(name, selectors)| CpuDomain { name, selectors })
            .collect();
        assert_eq!(selectors(&domains), map);
        assert!(matches!(selected[0][1], CpuSelector::Exclusive("build")));
    }
    #[test]
    fn invalid_maps_fail_instead_of_exporting_silent_bounds() {
        for map in [
            StageMap::new(),
            StageMap::from([("body".into(), vec![])]),
            StageMap::from([("body".into(), vec!["exclusive:".into()])]),
            StageMap::from([("body".into(), vec!["exclusive:exclusive:x".into()])]),
            StageMap::from([
                ("body".into(), vec!["scan".into()]),
                ("input".into(), vec!["scan".into()]),
            ]),
        ] {
            assert!(prepare(&map).is_err());
        }
    }
}
