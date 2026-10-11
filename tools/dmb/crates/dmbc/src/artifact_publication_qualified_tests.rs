use super::*;
use std::sync::Mutex;
type Values = Store<Vec<u8>, u8, Option<u8>, u8>;
struct Host {
    version: u128,
    certified: Option<u8>,
    opaque: Option<u8>,
    observable: bool,
    queries: Mutex<Vec<u8>>,
}
impl ObservationHost<u8, Option<u8>, u8> for Host {
    fn observes_answers(&self) -> bool {
        self.observable
    }
    fn answer(&self, query: &u8) -> Option<u8> {
        self.queries.lock().unwrap().push(*query);
        match query {
            1 => self.certified,
            2 => self.opaque,
            _ => panic!("unexpected query"),
        }
    }
    fn version(&self, domain: &u8) -> Option<u128> {
        match domain {
            1 => Some(self.version),
            2 => None,
            _ => panic!("unexpected domain"),
        }
    }
}
fn host(version: u128, certified: Option<u8>, opaque: Option<u8>, observable: bool) -> Host {
    Host {
        version,
        certified,
        opaque,
        observable,
        queries: Mutex::new(Vec::new()),
    }
}
fn populate(store: &Values) -> Arc<Vec<u8>> {
    store
        .insert_current_qualified_with(
            Arc::from(b"key".as_slice()),
            vec![
                Observation {
                    domain: 1,
                    query: 1,
                    answer: None,
                },
                Observation {
                    domain: 2,
                    query: 2,
                    answer: None,
                },
            ]
            .into(),
            Arc::from([(1, 7)]),
            2,
            || vec![1, 2],
        )
        .unwrap()
}
#[test]
fn mixed_certified_negative_and_opaque_reads_preserve_exact_fallbacks() {
    let owner = Values::current_revision();
    let first = owner.for_request(true);
    let original = populate(&first);
    assert!(first.publish_successful());
    let current = host(7, None, None, false);
    let request = owner.for_request(true);
    let (hit, changed) = request.visit_current_qualified(b"key", &current, &mut |_| true);
    assert!(Arc::ptr_eq(&hit.unwrap(), &original));
    assert!(changed.is_none());
    assert_eq!(*current.queries.lock().unwrap(), vec![2]);
    // A matching negative certificate never licenses another opaque answer.
    let opaque_changed = host(7, None, Some(9), false);
    let (hit, changed) = request.visit_current_qualified(b"key", &opaque_changed, &mut |_| true);
    assert!(hit.is_none());
    assert_eq!(changed, Some(2));
    assert_eq!(*opaque_changed.queries.lock().unwrap(), vec![2]);
    // Different provider token, same domain/query labels: replay the absent name.
    let certified_changed = host(8, Some(4), None, false);
    let (hit, changed) = request.visit_current_qualified(b"key", &certified_changed, &mut |_| true);
    assert!(hit.is_none());
    assert_eq!(changed, Some(1));
    assert_eq!(*certified_changed.queries.lock().unwrap(), vec![1]);
}
#[test]
fn observable_and_ordinary_visits_never_skip_certified_callbacks() {
    let owner = Values::current_revision();
    let first = owner.for_request(true);
    populate(&first);
    assert!(first.publish_successful());
    let request = owner.for_request(true);
    let observable = host(7, None, None, true);
    assert!(request
        .visit_current_qualified(b"key", &observable, &mut |_| true)
        .0
        .is_some());
    assert_eq!(*observable.queries.lock().unwrap(), vec![1, 2]);
    let ordinary = host(7, None, None, false);
    assert!(request
        .visit_explained(b"key", &ordinary, &mut |_| true)
        .0
        .is_some());
    assert_eq!(*ordinary.queries.lock().unwrap(), vec![1, 2]);
    let cross_host = host(7, Some(8), None, true);
    let (hit, changed) = request.visit_current_qualified(b"key", &cross_host, &mut |_| true);
    assert!(hit.is_none());
    assert_eq!(changed, Some(1));
}
#[test]
fn current_input_decline_and_failed_request_keep_published_owner_live() {
    let owner = Values::current_revision();
    let first = owner.for_request(true);
    let original = populate(&first);
    assert!(first.publish_successful());
    let current = host(7, None, None, false);
    let failed = owner.for_request(true);
    assert!(failed
        .visit_current_qualified(b"key", &current, &mut |_| false)
        .0
        .is_none());
    assert!(failed
        .visit_current_qualified(b"different-key", &current, &mut |_| true)
        .0
        .is_none());
    drop(failed);
    let next = owner.for_request(true);
    let hit = next
        .visit_current_qualified(b"key", &current, &mut |_| true)
        .0
        .unwrap();
    assert!(Arc::ptr_eq(&original, &hit));
    assert!(next.publish_successful());
}
