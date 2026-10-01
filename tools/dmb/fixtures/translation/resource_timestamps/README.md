# Resource timestamps

Native516.1687 compile-only probes use fresh outputs. The portable native pair was compiled with asset.txt modification time1700000123; native source_timestamp is exactly1700000123. Creation/access timestamp records emission Unix time.

Additional native probes establish positive modification times wrap to32bits:4294967419 ->123 and4294967296 ->0, both accepted.2147483647 is accepted unchanged. Source mtimes0,-1,1,2147483648 and pre1900 were rejected as `cannot find file` by the installed Windows native compiler. These rejections do not mean serialized source_timestamp0 is invalid, since4294967296 is accepted and encodes0.

The integration test sets filesystem modification times explicitly in a private temporary directory, checks native-proven normal/wrapped values, bounds creation timestamp between before/after emission, and verifies kind/CRC/name/size/payload/DMB references remain identical. Source mtimes from checkout metadata are not used as fixture expectations. Integration gate pending parent emitter fix.
