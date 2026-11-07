//! Report allocation/checkpoint contract shared by issuer and thin client.
use std::io;

/// A scoped loan from the actual hosting operation. Production issuers must
/// reserve before allocation and retain credit until the physical payload drops.
pub trait Work{fn temporary(&self,_slot:usize,bytes:usize)->io::Result<()>{self.reserve(bytes)}fn checkpoint(&self)->io::Result<()>;fn reserve(&self,bytes:usize)->io::Result<()>;fn overflow(&self)->io::Error;}
