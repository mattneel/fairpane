**Exactly. The frontend language becomes independent of the frontend renderer.**

A frontend in any qualified language can use Fairpane’s document model and receive GPU-accelerated output. It does not need a JavaScript application hidden underneath it.

That adds one important obligation: **the SDK must expose actual frontend behavior, not only browser commands.** Otherwise, we create a multilingual extension system, but stop short of a multilingual application platform.

My target is one renderer with multiple idiomatic ways to drive it—not a separate UI engine for every language.

## Two frontend paths, one platform

A **document frontend** uses Fairpane’s HTML/CSS machinery. Its chosen language controls application state and document updates through its SDK. Fairpane retains responsibility for layout and text behavior. Input and accessibility remain part of that shared platform.

A **custom graphics frontend** uses a GPU surface for specialized output. It still needs explicit input and accessibility contracts. A texture alone does not describe an operable application.

Neither path requires the frontend author to use GPUI. **GPUI is our browser-shell choice, not our frontend programming model.** GPUI itself does not provide a browser DOM or complete CSS compatibility. [GPUI](https://gpui.rs/examples/)

I also keep Fairpane-specific runtime support separate from standards-compatible web delivery. An installed language integration does not become permission for arbitrary pages to load native code.

## The GPU bridge is probably a surface bridge

Your direction makes sense. I separate the three similarly named pieces:

| Component | Role |
|---|---|
| **WebGPU** | The web API for GPU graphics and computation. [GPU Web](https://gpuweb.github.io/gpuweb/explainer/) |
| **wgpu** | A Rust graphics library based on WebGPU, with native graphics backends. [Wgpu](https://wgpu.rs/) |
| **GPUI** | The GPU-accelerated UI framework for the browser shell. [GPUI](https://gpui.rs/examples/) |

My proposed boundary is:

> **GPU requests go to a validated GPU service. Rendered surfaces go to the compositor and shell.**

That avoids an unnecessary translation from WebGPU commands into GPUI widgets.

WebGPU also supports computation without a canvas. That work has no reason to pass through GPUI. For visible canvas output, WebGPU supplies a texture that participates in browser composition. [GPU Web](https://gpuweb.github.io/gpuweb/explainer/)

For Fairpane, I propose that the engine incorporates that canvas into the page. The shell then presents the resulting page surface alongside its chrome.

The engine still owns the page’s visual semantics. GPUI does not reinterpret its CSS or reconstruct its layout.

**GPU acceleration for ordinary pages and WebGPU support remain separate deliverables.** They can share infrastructure without becoming the same feature.

## “Both use the GPU” does not establish interoperability

GPUI currently documents Metal on macOS, DirectX 11 on Windows, and wgpu on Linux. A shared wgpu device is therefore not a portable assumption. [GPUI](https://gpui.rs/examples/)

wgpu exposes raw-backend texture access, but that access carries explicit safety and lifetime requirements. Its resource model also checks device ownership. [Docs.rs](https://docs.rs/wgpu/latest/wgpu/struct.Texture.html?utm_source=chatgpt.com)

My performance target is **GPU-resident presentation without routine CPU readback**. Zero-copy remains a measured result for a specific configuration, not an architectural promise.

The implementation can negotiate a supported path. A shared surface is the preferred candidate. An explicit copy path remains useful where resource sharing does not qualify.

There is no need to select those mechanisms now.

## The contract worth preserving now

I reserve a versioned surface interface with these properties:

- **Opaque handles identify resources.** Rust and GPUI object layouts stay outside the public ABI.
- **Ownership includes GPU completion.** A producer cannot reuse a surface while its consumer still uses it.
- **Surface metadata defines interpretation.** Pixel format and color space are explicit.
- **Presentation capabilities are negotiated.** Unsupported imports and device loss have defined outcomes.

The actual platform adapters can follow later. No frontend language needs to know which adapter presents its frame.

One dependency distinction remains important: **wgpu in the shell for presentation fits your exception.** A mandatory wgpu implementation of the engine’s WebGPU behavior changes the engine dependency policy.

A callback does not erase that distinction. We can defer the backend decision without accidentally making it through an integration detail.

The larger direction is now clear:

> **Choose your language. Use the same frontend platform. Receive accelerated output without inheriting the browser shell’s framework.**

That is a much larger promise than language bindings—and the first-party integrations give us a concrete way to prove it.
