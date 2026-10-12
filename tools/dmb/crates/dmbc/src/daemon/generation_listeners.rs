//! Compiler-specific listeners own active connections independently of discovery.
use super::transport;
use std::{
    io,
    time::{Duration, Instant},
};

pub(super) struct Listeners {
    generation: Option<transport::Listener>,
    discovery: Option<transport::Listener>,
    discovery_endpoint: transport::Endpoint,
    next_discovery: Instant,
    discovery_first: bool,
}
pub(super) struct Incoming {
    pub(super) stream: transport::Stream,
    pub(super) discovery: bool,
}
impl Listeners {
    pub(super) fn new(compiler: u128) -> io::Result<Self> {
        Self::bind(
            transport::Endpoint::generation(compiler)?,
            transport::Endpoint::discovery()?,
        )
    }
    fn bind(
        generation: transport::Endpoint,
        discovery_endpoint: transport::Endpoint,
    ) -> io::Result<Self> {
        let generation = transport::listener(&generation)?;
        let mut listeners = Self {
            generation: Some(generation),
            discovery: None,
            discovery_endpoint,
            next_discovery: Instant::now(),
            discovery_first: false,
        };
        listeners.claim_discovery(Instant::now())?;
        Ok(listeners)
    }
    fn claim_discovery(&mut self, now: Instant) -> io::Result<()> {
        if self.discovery.is_some() || now < self.next_discovery {
            return Ok(());
        }
        self.next_discovery = now + Duration::from_secs(1);
        match transport::listener(&self.discovery_endpoint) {
            Ok(listener) => self.discovery = Some(listener),
            Err(error) if error.kind() == io::ErrorKind::AddrInUse => {}
            Err(error) => return Err(error),
        }
        Ok(())
    }
    pub(super) fn poll(&mut self, retiring: bool, now: Instant) -> io::Result<Option<Incoming>> {
        if retiring {
            // Accepted request streams own their handles. Dropping listeners
            // releases discovery while those requests continue to completion.
            self.discovery = None;
            self.generation = None;
            return Ok(None);
        }
        self.claim_discovery(now)?;
        self.discovery_first = !self.discovery_first;
        let order = if self.discovery_first {
            [
                (self.discovery.as_ref(), true),
                (self.generation.as_ref(), false),
            ]
        } else {
            [
                (self.generation.as_ref(), false),
                (self.discovery.as_ref(), true),
            ]
        };
        for (listener, discovery) in order {
            if let Some(stream) = listener
                .map(transport::Listener::try_accept)
                .transpose()?
                .flatten()
            {
                return Ok(Some(Incoming { stream, discovery }));
            }
        }
        Ok(None)
    }
}

#[cfg(test)]
#[path = "generation_listeners_tests.rs"]
mod tests;
