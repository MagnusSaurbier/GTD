import Foundation

/// Where the module picks its platform-specific pieces.
///
/// ARCHITECTURE §5 forbids a `#if` around *part* of a file, so the two implementations live in
/// `Platform/VaultPlatform+Apple.swift` (`#if os(iOS) || os(macOS)`) and
/// `Platform/VaultPlatform+Portable.swift` (everything else). This file only declares the
/// namespace, so it compiles everywhere.
public enum VaultPlatform {}
