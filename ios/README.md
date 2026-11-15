# Native iOS application

This directory contains the native iOS foundation. The existing repository root is a React/Rspack web application and does not produce an IPA.

## Current foundation

- `Package.swift`: Swift Package Manager module for shared iOS chat logic.
- `HybridChatCore`: provider-neutral message types and a router for Automatic, Offline only, and Online only modes.

## Planned native layers

1. SwiftUI app target and app lifecycle.
2. Network reachability monitor.
3. Local model runtime adapter backed by llama.cpp with Metal.
4. Remote DeepSeek adapter using Keychain-managed credentials.
5. Model download/storage manager and local conversation persistence.
6. UI integration, localization, tests, and signed IPA archive.

## Build environment

A real iOS app target, Xcode project, Apple signing configuration, and macOS/Xcode build environment are required to create and sign an IPA. The Swift package can be checked independently with Swift Package Manager on a compatible Swift toolchain.

## Privacy invariant

The local provider must process prompts and conversation history on-device. Automatic fallback to the local provider is allowed; automatic upload of local chat history is not.
