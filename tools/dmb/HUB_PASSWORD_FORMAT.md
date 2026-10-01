# Native hub-password encoding

Dream Maker 516.1687 writes a text-valued `world.hub_password` as:

```text
inner = lowercase_hex(MD5(native_password_bytes))
stored = "X" + lowercase_hex(MD5("hub" + native_password_bytes + inner))
```

The native assignment routine checks for a text value, appends the literal
`hub`, password bytes and inner digest, computes the outer digest, prefixes `X`,
and interns the result. Static assembly evidence is retained under
`D:/opendream-diagnostic/hub_hash_full.py` and `hub_hash_xrefs.py`.
No DreamDaemon execution was used.

Seven ASCII values, UTF-8 Latin/CJK text, newline/tab controls and escaped
quote/backslash values match independent native compiler output. Portable
fixtures are in `fixtures/translation/hub_password`; the expanded integration gate passes all twelve text/null cases, including
formatting controls, plus five assignment-history cases.

## Assignment history

Native compilation ignores a later null assignment when a previous authored
text password exists. `"secret"` followed by `null` retains the secret hash;
`"secret"`, `""`, then `null` retains the empty-string hash. An isolated null
assignment leaves the header StringID absent. This requires preserving the last
constant text assignment in source order, independently of the final variable
value. The patched compiler exports optional `NativeHubPassword` metadata for
that purpose; stock exports cannot reconstruct a discarded text assignment.

OpenDream formatting controls are translated to native string bytes before
hashing. MD5 here implements the existing BYOND wire format.
