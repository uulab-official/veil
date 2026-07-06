import os

/// This codebase has no logging framework at all -- every failure that isn't funneled into a
/// user-visible `errorMessage`/`displayMessage` property is completely invisible after the fact,
/// with no Console.app trace and no log file. That gap directly caused a real same-day incident on
/// the Windows guest-agent side (a crash masked because the failing exception was swallowed with no
/// diagnostic trace anywhere). `os.Logger` is the idiomatic macOS unified-logging API and costs
/// nothing to introduce; use it for background/best-effort failures that don't have (and shouldn't
/// force) a user-facing error surface, so at least `log stream`/Console.app can show what happened.
public enum VeilLog {
    public static let runtime = Logger(subsystem: "com.uulab.veil.host", category: "runtime")
    public static let agent = Logger(subsystem: "com.uulab.veil.host", category: "agent")
}
