/datum/raw_a
    var/scalar // ALLOW(base_vars): noncompiled declarations still consume their raw policy keeps
/datum/raw_b
    var/scalar // ALLOW(base_vars): source owner grouping preserves this annotation question order
/datum/raw_a
    var/later // ALLOW(base_vars): repeated owner declarations retain first owner encounter ordering
SCHEMA(/atom, raw_schema, schema_path(/obj))
SCHEMA(/atom, raw_schema, schema_ref(/obj))
TRACKED_SCHEMA(/atom, raw_schema, schema_text())
/datum/raw_asset
    var/sound/asset = 'fixture
asset'
    var/after_asset // ALLOW(base_vars): quote-swallowed line coordinates must retain their existing lookup behavior
