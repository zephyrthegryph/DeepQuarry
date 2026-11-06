use super::*;
#[test]
fn different_encodings_share_lexical_owner_but_never_acquisition() {
    let a = AcquiredSource::from_original_bytes(
        "/proc/p()\n    return \"€\"\n".as_bytes().to_vec(),
        1u64,
    );
    let b = AcquiredSource::from_original_bytes(b"/proc/p()\n    return \"\x80\"\n".to_vec(), 2u64);
    assert!(Arc::ptr_eq(a.prepared(), b.prepared()));
    assert!(!a.same_original_acquisition(&b));
    assert_eq!(a.encoding(), SourceEncoding::Utf8);
    assert_eq!(b.encoding(), SourceEncoding::IncompatibleOriginal);
}
#[test]
fn normal_independent_equal_reads_are_not_each_others_lease() {
    let a = AcquiredSource::from_original_bytes(b"/datum/a\n".to_vec(), 1u64);
    let b = AcquiredSource::from_original_bytes(b"/datum/a\n".to_vec(), 2u64);
    assert!(Arc::ptr_eq(a.prepared(), b.prepared()));
    assert!(!a.same_binding(&b));
    assert!(!a.same_original_acquisition(&b));
}
#[test]
fn warm_reissue_retains_original_and_changes_binding() {
    let a = AcquiredSource::from_original_bytes(b"/datum/a\n".to_vec(), 1u64);
    let b = a.reissued(2u64);
    assert!(a.same_original_acquisition(&b));
    assert!(!a.same_binding(&b));
    assert_eq!(b.receipt::<u64>(), Some(&2));
}
#[test]
fn binding_identity_matches_only_the_exact_live_lease() {
    let original = AcquiredSource::from_original_bytes(b"/datum/binding\n".to_vec(), 1u64);
    let identity = original.lease().identity();
    let alias = original.lease().clone();
    let reissued = original.reissued(2u64);
    let fresh = AcquiredSource::from_original_bytes(b"/datum/binding\n".to_vec(), 1u64);
    assert!(identity.matches(&alias));
    assert!(original.same_original_acquisition(&reissued));
    assert!(!identity.matches(reissued.lease()));
    assert!(!identity.matches(fresh.lease()));
    drop((original, alias));
    assert!(!identity.is_alive());
    assert!(!identity.matches(reissued.lease()));
    assert!(!identity.matches(fresh.lease()));
}
#[test]
fn incompatible_warm_reissue_stays_incompatible() {
    let a = AcquiredSource::from_original_bytes(b"//\x80\n".to_vec(), 1u64);
    assert_eq!(
        a.reissued(2u64).encoding(),
        SourceEncoding::IncompatibleOriginal
    );
}
#[test]
fn bom_is_positive_original_proof() {
    let a = AcquiredSource::from_original_bytes(b"\xef\xbb\xbf/datum/a\n".to_vec(), ());
    assert_eq!(a.encoding(), SourceEncoding::Utf8Bom);
    assert_eq!(a.prepared().original().as_str(), "/datum/a\n");
}
#[test]
fn authored_replacement_character_is_valid() {
    let a = AcquiredSource::from_original_bytes("//�\n".as_bytes().to_vec(), ());
    assert_eq!(a.encoding(), SourceEncoding::Utf8);
}
#[test]
fn mixed_token_stays_incompatible() {
    let a = AcquiredSource::from_original_bytes(b"//\xc3\xa9\xff\n".to_vec(), ());
    assert_eq!(a.encoding(), SourceEncoding::IncompatibleOriginal);
    assert_eq!(a.prepared().original().as_str(), "//éÿ\n");
}
#[test]
fn synthetic_contract_is_explicit() {
    let a = AcquiredSource::synthetic_utf8("/datum/a\n".into(), ());
    assert_eq!(a.encoding(), SourceEncoding::SyntheticUtf8);
}
#[test]
fn default_provider_declines() {
    struct P;
    impl crate::SourceProvider for P {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/datum/a\n".into())
        }
    }
    assert!(
        crate::SourceProvider::acquired_source(&P, std::path::Path::new("x"))
            .unwrap()
            .is_none()
    );
}
#[test]
fn receipt_type_cannot_be_reinterpreted() {
    let a = AcquiredSource::from_original_bytes(vec![], 7u64);
    assert!(a.receipt::<String>().is_none());
}
#[test]
fn clone_is_same_binding() {
    let a = AcquiredSource::from_original_bytes(vec![], ());
    assert!(a.same_binding(&a.clone()));
}
#[test]
fn no_original_buffer_retained_normally() {
    let mut bytes = Vec::with_capacity(100);
    bytes.extend_from_slice(b"/datum/uniquely_owned_normal_lease_73464\n");
    let pointer = bytes.as_ptr();
    let a = AcquiredSource::from_original_bytes(bytes, ());
    assert_eq!(a.prepared().original().as_bytes().as_ptr(), pointer);
}
#[test]
fn dropping_lease_releases_its_source() {
    let a =
        AcquiredSource::from_original_bytes(b"/datum/unique_lease_lifetime_849495\n".to_vec(), ());
    let weak = Arc::downgrade(a.prepared());
    drop(a);
    assert!(weak.upgrade().is_none());
}
#[test]
fn crlf_keeps_original_compiler_text() {
    let a = AcquiredSource::from_original_bytes(b"/datum/a\r\n".to_vec(), ());
    assert_eq!(a.encoding(), SourceEncoding::Utf8);
    assert!(a.prepared().original().as_str().contains("\r\n"));
}
#[test]
fn lone_cr_keeps_original_compiler_text() {
    let a = AcquiredSource::from_original_bytes(b"/datum/a\r".to_vec(), ());
    assert_eq!(a.encoding(), SourceEncoding::Utf8);
    assert!(a.prepared().original().as_str().ends_with('\r'));
}
#[test]
fn fresh_acquisition_cannot_inherit_reissued_authority() {
    let a = AcquiredSource::from_original_bytes(b"/datum/a\n".to_vec(), 1u64);
    let renewed = a.reissued(2u64);
    let fresh = AcquiredSource::from_original_bytes(b"/datum/a\n".to_vec(), 2u64);
    assert!(!renewed.same_binding(&fresh));
    assert!(!renewed.same_original_acquisition(&fresh));
}
#[test]
fn lightweight_lease_keeps_exact_source_and_receipt_but_releases_lexical_owner() {
    let acquired = AcquiredSource::from_original_bytes(
        b"/datum/light_only_lease_unique_38484\n".to_vec(),
        77u64,
    );
    let prepared = Arc::downgrade(acquired.prepared());
    let lease = acquired.lease().clone();
    let original = lease.source_text().downgrade();
    drop(acquired);
    assert!(
        prepared.upgrade().is_none(),
        "lease cannot pin PreparedSource"
    );
    assert_eq!(lease.receipt::<u64>(), Some(&77));
    assert!(original.upgrade().is_some());
    assert_eq!(
        lease.source_text().as_str(),
        "/datum/light_only_lease_unique_38484\n"
    );
    drop(lease);
    assert!(original.upgrade().is_none());
}

#[test]
fn original_weak_identity_survives_warm_binding_only() {
    let a = AcquiredSource::from_original_bytes(b"// a\n".to_vec(), 1u64);
    let b = a.reissued(2u64);
    let c = AcquiredSource::from_original_bytes(b"// a\n".to_vec(), 3u64);
    let id = a.lease().original_identity();
    assert!(id.same_live_original(&b.lease().original_identity()));
    assert!(!id.same_live_original(&c.lease().original_identity()));
    drop(a);
    drop(b);
    assert!(!id.same_live_original(&id)); // Weak allocation is not a live proof
}
#[test]
fn original_weak_identity_does_not_confuse_interned_encoding_aliases() {
    // The native compatibility decoder maps byte 0x80 to the euro sign.
    let a = AcquiredSource::from_original_bytes("// €\n".as_bytes().to_vec(), 1u64);
    let b = AcquiredSource::from_original_bytes(b"// \x80\n".to_vec(), 2u64);
    assert!(Arc::ptr_eq(a.prepared(), b.prepared()));
    assert!(!a
        .lease()
        .original_identity()
        .same_live_original(&b.lease().original_identity()));
}
