#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alfred Jean LLC
# install-remote.sh - Remote install via curl-pipe
# Usage: curl -fsSL https://raw.githubusercontent.com/alfredjeanlab/v0/main/install-remote.sh | bash
#
# Environment variables:
#   V0_INSTALL - Installation directory (default: ~/.local/share/v0)
#   V0_REPO    - Git repository URL (default: https://github.com/alfredjeanlab/v0)

set -e

V0_INSTALL="${V0_INSTALL:-$HOME/.local/share/v0}"
V0_REPO="${V0_REPO:-https://github.com/alfredjeanlab/v0}"

echo "Installing v0..."

# Check for git
if ! command -v git &> /dev/null; then
  echo "Error: git is required but not installed" >&2
  exit 1
fi

# Remove existing installation
if [ -d "$V0_INSTALL" ]; then
  echo "Removing existing installation at $V0_INSTALL"
  rm -rf "$V0_INSTALL"
fi

# Clone repository
echo "Cloning from $V0_REPO..."
git clone --depth 1 "$V0_REPO" "$V0_INSTALL"

# Create bin directory if needed
mkdir -p ~/.local/bin

# Symlink main command
ln -sf "$V0_INSTALL/bin/v0" ~/.local/bin/v0

echo ""
echo "v0 installed successfully!"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo ""
  echo "Warning: ~/.local/bin is not in your PATH"
  echo "Add this to your shell profile:"
  echo ""
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "To get started in a project:"
echo "  cd /path/to/your/project"
echo "  v0 init"
