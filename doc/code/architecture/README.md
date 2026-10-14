# Architecture

This folder goes into depth on how the codebase works, what systems exist, and how to use them.

# Design

This codebase is completely rewritten from most SS13 codebases, and features a lot of systems completely unique from /TG/ and other traditional servers.
Here are the set of general rules that should be followed when working on code in this codebase, which the architecture was built from:

# Code Reuse

Base SS13 code tends to be very verbose and copy-pasted. An example of this is the interaction system, where every single machine 
re-implements all of the different tool interactions, id locking, etc. This is resolved in quite a few ways, looking at a current machine,
you'll notice