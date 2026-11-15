# iOS Hybrid Offline/Online Architecture

## Product decision

Build a native iOS application with two inference paths:
- **Offline:** on-device language model, available without network access.
- **Online:** the existing DeepSeek-compatible API client (and future providers).

The app must never require a network connection to open, browse, or continue local conversations.

## Recommended implementation

### Native runtime
- SwiftUI application shell and chat interface integration.
- `llama.cpp` compiled for iOS with Metal enabled for local inference.
- GGUF quantized model downloaded once, stored in the app's Application Support directory.
- Start with a small Qwen instruct GGUF in a 4-bit quantization; benchmark candidate sizes on iPhone 17 Pro Max before choosing the default.
- Model download is an explicit, resumable setup step; show model size, available storage requirement, and progress.

### Provider abstraction
Introduce a common `ChatProvider` interface with:
- `LocalChatProvider` backed by llama.cpp.
- `RemoteChatProvider` backed by the current DeepSeek API service.
- A provider router with three settings: Automatic, Offline only, Online only.
- Automatic mode uses local inference when offline and remote inference when online; it must not silently upload local conversation data.

### Data and privacy
- Keep conversations and settings in local persistent storage.
- Preserve existing IndexedDB data during migration where feasible; define an export/import path if direct migration is not practical.
- Keep provider credentials in iOS Keychain, not UserDefaults/localStorage.
- Do not ship a shared API key in the IPA.
- Make cloud sync, telemetry, and conversation upload opt-in.

### UX requirements
- Persistent Offline/Online indicator.
- Model manager: download, pause/resume, delete, model version and storage use.
- Provider selector and clear error state when a requested provider is unavailable.
- Stream generated tokens in both modes and support cancellation.
- Preserve chat history, conversation titles, markdown rendering, and message branching where practical.
- Russian interface as the initial locale.

## Phased delivery

1. **Audit and isolate web client:** identify reusable UI/state/API modules and remove assumptions that the browser is always online.
2. **Native iOS shell:** create the SwiftUI app structure and a bridge boundary for the existing chat UI or migrate the chat view to native components.
3. **Local inference proof of concept:** integrate llama.cpp + Metal, load a small GGUF model, stream tokens, cancel generation, and release memory correctly.
4. **Provider routing:** connect local and remote providers behind one interface; add Automatic/Offline only/Online only modes.
5. **Persistence and model manager:** local history, Keychain credentials, model download lifecycle, disk-space checks, and migration/import/export.
6. **QA and IPA:** test airplane mode, cold launch, long conversations, interruption/cancellation, low storage, memory pressure, and online failures; archive and sign the IPA.

## Acceptance criteria

- App launches and opens existing local chats in Airplane Mode.
- User can download a model while online, then generate a response after enabling Airplane Mode.
- Automatic mode falls back to local inference when the remote API is unreachable.
- Offline messages are not sent to the remote provider.
- Online mode works with a user-supplied API key stored in Keychain.
- Generation can be cancelled without corrupting the conversation.
- No claim of model speed or quality is made until measured on the target iPhone.

## Constraints and risks

- The current repository is a React/Rspack web app, not an iOS project; it does not produce an IPA by itself.
- A native iOS target and Xcode build/signing pipeline are required. Final IPA signing/distribution requires Apple signing assets and a macOS/Xcode build environment.
- Model size, memory use, thermal behavior, and token throughput must be measured on the actual target device.
- Some current browser-only features (IndexedDB, localStorage, browser speech APIs, SSE) need native replacements or adapters.
- Internet search, remote APIs, and cloud-only tools are unavailable offline.
