//! Same header artifact cores, with request-local pending key claims.
use super::*;
impl HeaderRecipes {
    pub(crate) fn evict_cached_claims(&self) {
        self.values.evict_all_claims();
        self.defaults.evict_all_claims();
    }

    pub(crate) fn for_request(&self, publishable: bool) -> Arc<Self> {
        Arc::new(Self {
            values: self.values.for_request(publishable),
            defaults: self.defaults.for_request(publishable),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        })
    }
    pub(crate) fn publish_successful(&self) -> bool {
        let values = self.values.publish_successful();
        let defaults = self.defaults.publish_successful();
        values && defaults
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn failed_header_pruning_preserves_published_selector_owner() {
        let owner = HeaderRecipes::default();
        let first = owner.for_request(true);
        let (_, original) = first.defaults(b"/obj", &[b"name".to_vec()], &[]);
        assert!(first.publish_successful());
        let failed = owner.for_request(true);
        failed.clear();
        drop(failed);
        let build = owner.for_request(true);
        let (_, replay) = build.defaults(b"/obj", &[b"name".to_vec()], &[]);
        assert!(Arc::ptr_eq(&original, &replay));
        let analysis = owner.for_request(false);
        analysis.clear();
        assert!(!analysis.publish_successful());
        assert!(build.publish_successful());
        let changed = owner.for_request(true);
        let (_, replacement) = changed.defaults(b"/obj", &[b"name".to_vec()], &[b"name".to_vec()]);
        assert!(!Arc::ptr_eq(&original, &replacement));
        assert_eq!(replacement.len(), 1);
        assert!(!replacement[0].from_parent);
        assert_eq!(replacement[0].ordinal, 0);
        assert_eq!(replacement[0].name, b"name");
        assert!(changed.publish_successful());
    }
}
