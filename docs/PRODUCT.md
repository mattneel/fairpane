# Product contract

## Experience

Fairpane feels like an application workspace with a browser's reach.
The default window contains an address bar and the page.
It does not contain a permanent collection of promotional panels or unrelated services.
The user's VS Code and Stencil references express restraint and application focus, not a requirement to copy their interface or implementation.

Minimal chrome does not mean missing capabilities.
Commands and secondary surfaces expose advanced controls without permanent visual clutter.
The application remains operable with a keyboard and assistive technology.

## Required application behavior

- Navigation includes history, reload, stop, back, forward, and explicit error states.
- Address presentation protects origin identity and resists page-controlled spoofing.
- Application windows support launch, focus, restore, and OS-level identity.
- Sessions preserve useful state without pretending that stale authentication remains valid.
- Downloads expose destination, progress, failure, and recovery.
- Permissions expose the requesting origin and revocation controls.
- Profiles and storage controls separate identities and origin data.
- Clipboard, file selection, printing, notifications, and external links follow explicit host policy.
- Developer inspection exposes DOM, styles, layout, network behavior, console output, and runtime state.
- Accessibility includes navigation, focus, text input, selection, zoom, and platform integration.

Each behavior needs a task and executable acceptance scenario.
This list is a product obligation list, not a claim of implementation.

## Application mode

An application window can open a pinned launch address with a distinct OS entry.
The browser preserves the real origin across redirects and external navigation.
Application identity never grants a page additional privileges by itself.
Cross-origin navigation and permission changes remain visible.

The initial shell uses the same first-party engine as the library.
It cannot use Electron, CEF, WebView2, WKWebView, or a system renderer to pass a product milestone.
External browsers can serve as test references only.

## Delivery sequence

Windows is the first native development surface because the project starts at `C:\src\fairpane`.
Linux and macOS ports remain first-class requirements.
WebAssembly embedding has a distinct memory and capability contract.
Mobile ports require their own lifecycle and policy work.

An early window can display unsupported content honestly.
A browser milestone cannot pass through a hardcoded screenshot or static mock.
Each vertical slice connects actual parsing, layout, paint, and host presentation as those components arrive.

## Non-goals

Fairpane does not become an advertising network or a mandatory cloud account.
The browser does not require telemetry for operation.
The initial product does not copy another application's trade dress.
The agent does not purchase domains or establish public infrastructure without owner authorization.
