use super::*;
#[test]
fn forced_equal_hash_never_authorizes_different_configuration_or_missing_fact() {
    let old = ConfigData {
        config: Arc::new(Config::capture(Configuration::Captured(b"# old\n")).unwrap()),
        hash: 17,
        original: Some(dm_resources::SharedBytes::from(b"# old\n".to_vec())),
    };
    let foreign = ConfigData {
        config: Arc::new(Config::capture(Configuration::Captured(b"# new\n")).unwrap()),
        hash: 17,
        original: Some(dm_resources::SharedBytes::from(b"# new\n".to_vec())),
    };
    assert_eq!(old.hash, foreign.hash);
    assert!(old
        .require_original(foreign.original.as_ref().map(|b| b.as_slice()))
        .is_err());
    assert!(old.require_original(None).is_err());
    assert!(old.require_original(Some(b"# old\n")).is_ok());
    let missing = ConfigData {
        config: Arc::new(Config::capture(Configuration::ProvenMissing).unwrap()),
        hash: 17,
        original: None,
    };
    assert!(missing.require_original(Some(b"")).is_err());
    assert!(missing.require_original(None).is_ok());
}
