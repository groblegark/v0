# v0-self-update

**Purpose:** Update v0 to a different version or channel.

## Workflow

1. Resolve target version (stable, nightly, or specific)
2. Download and verify tarball
3. Backup current installation
4. Extract and install new version
5. Verify and clean up

## Usage

```bash
v0 self update              # Update to latest stable
v0 self update nightly      # Switch to nightly
v0 self update 0.2.0        # Install specific version
v0 self update --list       # Show available versions
v0 self update --check      # Check for updates
```
