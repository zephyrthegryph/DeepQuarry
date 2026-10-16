# Lazy skin-command map

Source-only; one `list_init` row removed, verification pending. The command map
allocates only on real registration, with the same key replacement and object
reference semantics. Unknown commands use null-safe lookup. The empty dispatcher
is retained unchanged. The separate `base_var` pointer row remains: this change
does not claim an object-reference map is a scalar sparse value.

Focused selector: `dq_skin_command_cache_home`. Real registration, replacement,
unknown/known dispatch and independent mob maps are asserted.
