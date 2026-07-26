# Make Package Inspection a shared first-class workflow

Swiftpkg will treat read-only Package Inspection as a first-class peer to Package Project authoring rather than requiring import or conversion. A session-oriented SwiftPkgCore module will own inspection and produce the same Inspection Report for the swiftpkg CLI and Swiftpkgr, with frontend parity gating the stable release. This centralizes extraction, trust, and safety semantics at the cost of a larger shared core and coordinated delivery instead of simpler app-only or import-first implementations.
