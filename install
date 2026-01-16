#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Alfred Jean LLC
# install.sh - Local development install (symlinks)
# Usage: ./install.sh

set -e

V0_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create bin directory if needed
mkdir -p ~/.local/bin

# Symlink main v0 command
ln -sf "$V0_DIR/bin/v0" ~/.local/bin/v0

echo "Installed v0 to ~/.local/bin/v0"

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
