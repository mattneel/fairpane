# Frontend platform

## Rule

> **Choose your language. Use the same frontend platform. Receive accelerated output without inheriting the browser shell's framework.**

The quoted rule is the owner's wording, and ADR 0007 records the decision.
Fairpane is one renderer with several idiomatic ways to drive it.
A frontend in any qualified language can use Fairpane's document model and receive GPU-accelerated output.
It needs no JavaScript application hidden underneath it.
Each SDK therefore exposes actual frontend behavior, not only browser commands.

## Frontend paths

| Path | Rendering | Obligations |
| --- | --- | --- |
| Document frontend | Fairpane's HTML and CSS machinery renders it. | The SDK drives application state and document updates, and Fairpane keeps layout, text, input, and accessibility. |
| Custom graphics frontend | The frontend renders specialized output into a GPU surface. | The frontend supplies explicit input and accessibility contracts, because a texture alone does not describe an operable application. |

Neither path requires GPUI.
GPUI is the browser shell's framework, not Fairpane's frontend programming model.
Fairpane-specific runtime support stays separate from standards-compatible web delivery.
An installed language integration never permits an arbitrary page to load native code.

## GPU boundary

> **GPU requests go to a validated GPU service. Rendered surfaces go to the compositor and shell.**

| Component | Role |
| --- | --- |
| WebGPU | It is the web API for GPU graphics and computation. |
| wgpu | It is a Rust graphics library based on WebGPU, with native graphics backends. |
| GPUI | It is the GPU-accelerated UI framework for the browser shell. |

WebGPU commands never become GPUI widgets.
Compute-only WebGPU work never passes through GPUI.
The engine composes each visible WebGPU canvas texture into the page.
The shell presents the resulting page surface beside its chrome.
GPUI never reinterprets page CSS or reconstructs page layout.
GPU acceleration for ordinary pages and WebGPU support are separate deliverables with separate evidence.

## Surface interface

The public contract reserves a versioned surface interface.

- Opaque handles identify surface resources.
- Rust and GPUI object layouts stay outside the public ABI.
- Ownership includes GPU completion, so a producer cannot reuse a surface while its consumer still uses it.
- Surface metadata states the pixel format and color space explicitly.
- Producer and consumer negotiate presentation capabilities.
- Unsupported imports and device loss have defined outcomes.

No frontend language needs to know which platform adapter presents its frame.
The first adapter uploads CPU-memory surfaces.

## Presentation performance

The target is GPU-resident presentation without routine CPU readback.
Zero-copy is a measured result for a specific configuration, not an architectural promise.
A shared surface is the preferred path, and an explicit copy path remains where sharing does not qualify.
GPUI uses Metal on macOS, DirectX 11 on Windows, and wgpu on Linux, so a shared wgpu device is not a portable assumption.

## Dependency boundary

wgpu in the shell for presentation fits the application's dependency exception.
A mandatory wgpu implementation of the engine's WebGPU behavior would change the engine dependency policy.
A callback does not erase that distinction.
Any third-party implementation of engine WebGPU behavior needs a separate owner decision.

## Tasks

`FP-0035` defines the surface interface and the input contract.
`FP-0043` exposes document frontends through the public contract.
`FP-0044` defines custom graphics frontends.
`FP-0048` builds the first internal GPU paint adapter against the scalar reference.
`FP-0045` qualifies GPU-resident presentation.
`FP-0046` defines the validated GPU service boundary and reports WebGPU as unsupported until a WebGPU task implements it.
`FP-0041` and `FP-0042` prove both frontend paths through the TypeScript and Elixir SDKs.
