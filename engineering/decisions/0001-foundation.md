# ADR 0001: Foundation boundaries

Status: accepted as the bootstrap's engineering direction.
Authority: the owner's explicit project request and prior design discussion.

## Decision

The portable engine and JavaScript runtime use first-party Zig.
The build follows exact pins from Zig master.
The public embedding boundary uses a C ABI with language-specific wrappers.
One wrapper language is first-party.
Internal modules use Zig-native interfaces.
The product includes a native minimal browser, not only an engine library.
The browser shell is written in the first-party wrapper language and uses only the public embedding contract.

## Consequences

The project owns text, codecs, and runtime semantics instead of concealing external engines.
Development infrastructure can use other languages and tools.
Operating-system adapters expose their dependency inventory separately.
The qualification program must distinguish a bootstrap from a functioning browser.
The browser dogfoods the embedding contract, so a capability that the browser needs and the contract lacks is a contract defect.
No private engine interface can serve the browser and remain unavailable to other embedders.

## Open design choices

The value representation, collector policy, bytecode format, and JIT architecture remain experimental.
Those choices require evidence before permanent adoption.
The owner selects the first-party wrapper language from a recorded comparison of candidates.
