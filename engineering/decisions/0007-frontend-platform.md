# ADR 0007: One renderer for frontends in every language

Status: decided by the owner; this record awaits an accepting independent review.
Owner: the project owner.
Date: 2026-10-09.
Related tasks: `FP-0035`, `FP-0041`, `FP-0042`, `FP-0043`, `FP-0044`, `FP-0045`, `FP-0046`, `FP-0048`.

## Decision

> **Choose your language. Use the same frontend platform. Receive accelerated output without inheriting the browser shell's framework.**

> **GPU requests go to a validated GPU service. Rendered surfaces go to the compositor and shell.**

The quoted statements are the owner's wording.
The frontend language becomes independent of the frontend renderer.
A frontend in any qualified language can use Fairpane's document model and receive GPU-accelerated output.
It needs no JavaScript application hidden underneath it.
Fairpane is one renderer with several idiomatic ways to drive it, not a separate UI engine for each language.

Each SDK therefore exposes actual frontend behavior, not only browser commands.
A multilingual extension system alone would stop short of a multilingual application platform.
The first-party integrations of ADR 0006 prove the platform in each language.

## Two frontend paths

A document frontend uses Fairpane's HTML and CSS machinery.
Its language controls application state and document updates through its SDK.
Fairpane keeps responsibility for layout and text behavior.
Input and accessibility stay part of that shared platform.

A custom graphics frontend uses a GPU surface for specialized output.
It still needs explicit input and accessibility contracts, because a texture alone does not describe an operable application.

Neither path requires GPUI.
GPUI is the browser shell's framework, not Fairpane's frontend programming model.
GPUI provides no browser DOM and no complete CSS compatibility.
Fairpane-specific runtime support stays separate from standards-compatible web delivery.
An installed language integration never permits an arbitrary page to load native code.

## GPU components

| Component | Role |
| --- | --- |
| WebGPU | It is the web API for GPU graphics and computation. |
| wgpu | It is a Rust graphics library based on WebGPU, with native graphics backends. |
| GPUI | It is the GPU-accelerated UI framework for the browser shell. |

The surface bridge avoids any translation from WebGPU commands into GPUI widgets.
WebGPU computation needs no canvas, so that work never passes through GPUI.
For visible output, a WebGPU canvas supplies a texture that the engine composes into the page.
The shell then presents the resulting page surface beside its chrome.
The engine keeps the page's visual semantics, and GPUI never reinterprets its CSS or reconstructs its layout.
GPU acceleration for ordinary pages and WebGPU support are separate deliverables.
They can share infrastructure without becoming the same feature.

## Interoperability is a measurement

GPUI documents Metal on macOS, DirectX 11 on Windows, and wgpu on Linux.
A shared wgpu device is therefore not a portable assumption.
wgpu exposes raw-backend texture access only under explicit safety and lifetime requirements, and its resource model checks device ownership.

The performance target is GPU-resident presentation without routine CPU readback.
Zero-copy remains a measured result for a specific configuration, not an architectural promise.
The implementation negotiates a supported path.
A shared surface is the preferred candidate, and an explicit copy path remains where resource sharing does not qualify.
This record selects none of those mechanisms yet.

## The surface contract reserved now

The public contract reserves a versioned surface interface.

- Opaque handles identify resources, and Rust and GPUI object layouts stay outside the public ABI.
- Ownership includes GPU completion, so a producer cannot reuse a surface while its consumer still uses it.
- Surface metadata states the pixel format and color space explicitly.
- Producer and consumer negotiate presentation capabilities.
- Unsupported imports and device loss have defined outcomes.

Platform adapters follow later.
No frontend language needs to know which adapter presents its frame.

## Dependency distinction

wgpu in the shell for presentation fits the application's dependency exception.
A mandatory wgpu implementation of the engine's WebGPU behavior would change the engine dependency policy.
A callback does not erase that distinction.
The WebGPU backend decision stays open, and no integration detail makes it implicitly.
Any third-party implementation of engine WebGPU behavior needs a separate owner decision.

## Consequences

`FP-0035` defines the versioned surface interface and the input contract.
`FP-0043` exposes the document frontend platform through the public contract.
`FP-0044` defines the custom graphics frontend contract.
`FP-0048` builds the first internal GPU paint adapter against the scalar reference.
`FP-0045` qualifies GPU-resident presentation without routine CPU readback.
`FP-0046` defines the validated GPU service boundary, and it reports WebGPU as unsupported until a WebGPU task implements it.
`FP-0041` and `FP-0042` build document and custom graphics frontends through each language's SDK.

## Sources and evidence

- `engineering/evidence/frontends/owner-memo-2026-10-09.md` holds the owner's memo verbatim.
- GPUI examples and backends: <https://gpui.rs/examples/>.
- wgpu: <https://wgpu.rs/>.
- WebGPU explainer: <https://gpuweb.github.io/gpuweb/explainer/>.
- wgpu texture safety requirements: <https://docs.rs/wgpu/latest/wgpu/struct.Texture.html>.
