# Swiftpkg

Swiftpkg provides tools for creating and examining Apple installer packages.

## Language

**Package Project**:
An editable directory containing the configuration, content, scripts, and metadata used to build an installer package.
_Avoid_: Package workspace, workspace

**Installer Package**:
An Apple `.pkg` artifact, whether built by Swiftpkg or supplied by a user, and whether it is a component or distribution package.
_Avoid_: Pkg artifact, package file

**Flat Package**:
An installer package stored as a single archive file.
_Avoid_: Modern package

**Bundle Package**:
A legacy installer package stored as a directory bundle and still supported for import and inspection.
_Avoid_: Unsupported package

**Component Package**:
An installable unit containing package metadata and optional payload or scripts.
_Avoid_: Subpackage

**Payload-free Component**:
A component package with no payload archive, though it may still contain scripts and create an installer receipt.
_Avoid_: Empty-payload component

**Empty-payload Component**:
A component package whose payload exists but contains no entries.
_Avoid_: Payload-free component

**Payload Entry**:
A file, directory, or symbolic link recorded for installation by a component package. It has both an archive path and an intended installed path.
_Avoid_: Package file

**Payload Code**:
An executable, application, or other signable code object carried as a payload entry. Its architectures, platform requirements, signing evidence, notarization evidence, entitlements, and hardened-runtime status are independent of the installer package that contains it.
_Avoid_: Package signature

**Payload Export**:
Copying a selected payload entry from an installer package to a user-chosen destination without installing it. Export preserves content and safe structure but does not apply package-declared ownership, ACLs, or extended attributes.
_Avoid_: Install, extract package

**Installer Script**:
Executable content embedded in an installer package that may run during installation rather than becoming a payload entry.
_Avoid_: Payload entry

**Distribution Package**:
An installer package that coordinates one or more component packages with installation choices and requirements.
_Avoid_: Wrapper package

**Installation Choice**:
A distribution-defined selection or condition that determines whether associated component packages are eligible for installation.
_Avoid_: App setting, build option

**Installation Requirement**:
A condition declared by an installer package that constrains where or when its components are eligible for installation.
_Avoid_: Build requirement

**Eligible Components on This Mac**:
The component packages selected by evaluating installation choices and requirements against the current Mac. This result does not predict changes made by installer scripts.
_Avoid_: Installation path, simulated installation

**Package Inspection**:
The read-only examination of an installer package without converting it into a package project. Inspection never installs payloads or executes embedded scripts.
_Avoid_: Import, open as project

**Full Inspection**:
The default inspection scope, including trust checks for installer package nodes and discovered payload code.
_Avoid_: Deep scan

**Package-only Inspection**:
An inspection scope that still inventories payload entries and installer scripts but limits trust checks to installer package nodes.
_Avoid_: Shallow scan, metadata-only inspection

**Inspection Report**:
The structured result of package inspection, including provenance, scope, package hierarchy, contents, scripts, requirements, and trust results. A report may retain partial results when inspection is incomplete.
_Avoid_: Scan results

**Inspection Issue**:
A problem that prevents some package information from being examined, scoped to the affected package node or resource and kept distinct from a trust result.
_Avoid_: Trust failure

**Stale Inspection Report**:
An inspection report whose source installer package has changed since the report was produced and therefore no longer represents the current artifact.
_Avoid_: Current report

**Notarization Configuration**:
Credentials and options used to submit an installer package for notarization.
_Avoid_: Notarization status

**Notarization Status**:
The independently reported stapled-ticket and requested Gatekeeper evidence observable from an installer package or payload code, excluding credentials used during submission. Absence of a stapled ticket alone does not mean the examined object was not notarized.
_Avoid_: Notarization configuration, notary credentials

**Signing Status**:
The independently reported signature integrity, host certificate trust, certificate purpose, identity, Team ID, certificate chain and fingerprints, certificate dates, and secure timestamp for an installer package or payload code object. It remains available independently of any trust summary.

**Trust Result**:
The outcome of one signing or notarization check for a specific installer package node or payload code object: Passed, Failed, Absent, Unavailable, Not Performed, or Not Applicable.

**Trust Summary**:
A derived roll-up of detailed trust results using Checks Failed, Attention Needed, Checks Passed, or Not Checked; it never replaces those results or claims safety. Failed results fail the summary, Absent or Unavailable results require attention, and skipped or inapplicable checks do not penalize the disclosed scope.
_Avoid_: Overall trust status
