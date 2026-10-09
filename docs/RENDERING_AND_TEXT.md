# Rendering and text contract

## HTML

The parser follows the specified tokenizer and tree-construction state machines.
Malformed input follows standard recovery behavior.
Parser continuations preserve state across resource chunks and script execution.
HTML tree construction can reenter through script behavior. [S12]

Chunk-partition tests compare incremental input with whole-input parsing.
A mismatch produces a minimized fixture.
The parser does not use a permissive XML parser as an HTML substitute.

## CSS

Selector matching and the cascade remain separate stages.
The property registry records initial values, inheritance, computed representations, and invalidation effects.
A generator produces repetitive tables, not inferred layout algorithms.
Custom properties retain token-level behavior through substitution.

Used values remain separate from computed values.
An indefinite size does not use zero as its representation.
Tagged constraints preserve automatic, definite, and indefinite cases. [S13]
Logical axes remain explicit until physical-coordinate conversion.

## Layout

Formatting contexts return fragments and dependencies.
Fragmentation continuation state is part of the interface.
Inline layout preserves mappings between logical text and visual fragments.
A full-recomputation path checks incremental style and layout results.

Flexbox, grid, tables, floats, positioning, and fragmentation need independent workstreams.
An attractive block-layout demo cannot close those obligations.
Numeric conversions and pixel rounding occur at named boundaries.

## Text

Text is an early critical path, not a final font-loading feature.
The engine owns font parsing, shaping, fallback, and rasterization for the canonical profile.
Platform adapters can discover fonts without defining the engine's text behavior.

- Unicode bidirectional behavior and segmentation need versioned data and tests.
- Contextual substitutions and mark positioning need script-specific OpenType fixtures.
- Line breaking needs language and layout integration.
- Caret movement and selection need visual-to-logical mappings.
- Vertical text and font fallback need explicit qualification.

The source registry identifies Unicode and OpenType references. [S14, S15]
WOFF2 includes a Brotli decompression requirement. [S16]
The project must account for that implementation instead of concealing a third-party decoder.

No proprietary font file belongs in the repository or bootstrap archive without appropriate permission.
Redistributable test fonts need exact provenance and license records.

## Paint and media

The scalar software raster path is the reference backend.
GPU adapters compare their output against declared tolerances.
The paint scene preserves clipping, transforms, stacking, and retained resources.
Canvas and SVG remain guest-facing features, not automatic consequences of internal graphics code.

Guest WebGL and WebGPU are separate workstreams from internal GPU acceleration.
GPU requests go to a validated GPU service, and rendered surfaces go to the compositor and the shell.
The engine composes each visible WebGPU canvas texture into the page.
`docs/FRONTENDS.md` describes the versioned surface interface and the presentation targets.
Image and media decoders need bounds, malformed-input tests, and resource limits.
Media support includes playback behavior and synchronization, not only file decoding.
Codec patent policy and DRM access require explicit legal and platform decisions.
An unresolved policy cannot silently disappear from the public capability report.
