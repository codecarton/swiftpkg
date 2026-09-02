---
status: accepted
---

# Make Package Inspection a shared first-class workflow

## Context

Swiftpkg currently centers on Package Projects. Existing Installer Packages can be imported into new projects, but import is a mutating conversion workflow, cannot represent every package hierarchy, and is not suitable for users who only want to understand an artifact before installing it. Swiftpkgr also retains one project-oriented application model, while the swiftpkg CLI and Swiftpkgr otherwise share package behavior through SwiftPkgCore.

Package Inspection introduces stateful behavior that must remain consistent and safe across both frontends: temporary extraction, source fingerprinting, package hierarchy discovery, trust evaluation, on-demand content access, cancellation, staleness, and cleanup. Implementing those concerns separately in the CLI and app would create two interpretations of the same Installer Package and duplicate the security-sensitive parts of inspection.

## Decision

Package Inspection is a read-only, first-class peer to Package Project authoring. Inspecting an Installer Package does not require importing or converting it into a Package Project, and Swiftpkgr represents project editing and package inspection as independent window sessions.

SwiftPkgCore owns a session-oriented Package Inspection module. A session manages the source artifact and temporary resources, produces the canonical Inspection Report, and provides the operations needed for verification, preview, export, cancellation, and cleanup. The swiftpkg CLI and Swiftpkgr consume that same module and report model rather than implementing frontend-specific inspection behavior.

The stable Package Inspection release requires frontend parity. Incremental implementation may land behind incomplete surfaces, but inspection is not considered stable until both frontends expose the shared capabilities appropriate to their interaction models. The detailed product contract and delivery slices live in the [Package Inspection specification](https://github.com/codecarton/swiftpkg/issues/31).

## Considered Options

- **Require import before inspection.** Rejected because it creates or mutates a Package Project, conflates read-only examination with conversion, and excludes valid package structures that Swiftpkg cannot import.
- **Build inspection only in Swiftpkgr.** Rejected because CLI users and automation need the same evidence, and package interpretation would no longer be a shared core capability.
- **Implement inspection independently in each frontend.** Rejected because parsing, trust evaluation, resource limits, and extraction safety would be duplicated and could drift.
- **Expose stateless inspection helper functions from SwiftPkgCore.** Rejected because callers would have to coordinate temporary-resource lifetime, source changes, cancellation, on-demand access, and cleanup themselves.

## Consequences

- Package interpretation, trust semantics, safety limits, and report versioning have one implementation and one primary testing seam.
- Installer Packages that cannot become Package Projects, including multi-component distributions, remain inspectable.
- SwiftPkgCore gains a larger stateful module and a compatibility-sensitive Inspection Report model.
- Swiftpkgr must move from one application-wide project model to independently owned project and inspection window sessions.
- CLI and app delivery must be coordinated, so a complete feature may take longer than an app-only viewer.
- Frontend presentation may differ, but neither frontend may redefine the meaning of an Inspection Report or its Trust Results.
