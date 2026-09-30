#!/usr/bin/env bash
set -e

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

if [ -f "$INSTALL_DIR/multigravity" ]; then
    rm -f "$INSTALL_DIR/multigravity"
    echo "Removed $INSTALL_DIR/multigravity."
else
    echo "multigravity was not found in $INSTALL_DIR."
fi

echo ""
echo "Note: Profile data in ~/.config/multigravity-profiles was preserved."
echo "If you also wish to delete all profiles and tokens, run:"
echo "  rm -rf ~/.config/multigravity-profiles"
