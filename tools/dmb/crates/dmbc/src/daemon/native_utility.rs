//! One unpublished protocol utility envelope. Each typed question owns its
//! own actual preparation and terminal; utility DATA grants no full model.
use serde::{Deserialize,Serialize};
#[derive(Debug,Deserialize,Serialize)]
pub(super)enum Request{CodemodFixture(super::native_codemod_fixture::Request),StandaloneSelftests(super::native_selftests::Request),Sem(super::native_sem_utility::Request)}
