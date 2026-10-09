# Experimental embedding surface

`bootstrap.json` is the machine-readable contract for the candidate probe.
`include/fairpane.h` is its C declaration.
`src/c_api.zig` is its candidate implementation.

ABI revision zero is experimental.
The capability mask is zero because no browser feature is implemented.
`fp_query_capabilities` requires a writable, correctly aligned output object when the pointer is non-null.
No native API can validate arbitrary pointer provenance from a hostile in-process caller.

The buffer remains unchanged on invalid size or null output.
The success result initializes the declared structure only.
Bytes beyond that structure remain the caller's property.

The first ABI expansion requires lifecycle, ownership, and cancellation tests.
The browser shell reaches the engine only through this surface and the first-party Rust wrapper.
The surface must therefore carry every capability that the browser needs.
A future schema generator replaces duplicated declarations after its own qualification.
This bootstrap does not claim that the header is generated.

## Internal handles

`src/handles.zig` defines internal owner identities and generational handles.
Internal handles never cross the C ABI or the process protocol directly.
A later boundary maps handles through explicit, validated conversion to its own identifier type.
Those boundary identifier types are outside this revision.
