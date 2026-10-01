# Cross-kind resource identity and native phase order

The three PNG files here have identical bytes and CRC3844205640 but different extensions. Native516.1687 accepts all three with no warnings. Root globals are realized before class defaults, even when the class declaration appears first in source.

| Fixture | Named RSC order | Sole DMB resource kind |
| --- | --- | --- |
| global_generic | same.txt(0), same.png(6) | 0 |
| global_image | same.png(6), same.txt(0) | 6 |
| global_dmi | same.dmi(3), same.txt(0) | 3 |

The integration test compares complete ordered name/kind/CRC/payload/size signatures, DMB ResourceRefs, and HashOnly emission agreement in both debug modes. Physical timestamps are excluded. Native fixture evidence is complete; focused integration passed both debug modes and HashOnly on the current parent-built Rust library. Full package gate pending current exporter/cache batch.

