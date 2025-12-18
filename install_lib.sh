#!/bin/bash

# Check if pyproject.toml exists
if [[ ! -f "pyproject.toml" ]]; then
    echo "Error: pyproject.toml not found. Are you in the root of a Poetry project?"
    exit 1
fi

# 1. Execute poetry build
echo "Building package with Poetry..."
if ! poetry build; then
    echo "Error: Poetry build failed."
    exit 1
fi

# 2. Install the local path as a python package
echo "Installing package in editable mode..."
if ! pip install -e .; then
    echo "Error: Pip install failed."
    exit 1
fi

# 3. Get current position as PACKAGE_PATH
PACKAGE_PATH=$(pwd)

# 4. Check if current position is in PYTHONPATH
if [[ ":$PYTHONPATH:" == *":$PACKAGE_PATH:"* ]]; then
    echo "Current path is already in the active PYTHONPATH."
else
    echo "Path not found in active PYTHONPATH. Checking ~/.zshrc..."

    # 5. Add to ~/.zshrc if not already written there
    ZSHRC="$HOME/.zshrc"
    EXPORT_LINE="export PYTHONPATH=\"\${PYTHONPATH}:$PACKAGE_PATH\""

    if grep -Fq "$PACKAGE_PATH" "$ZSHRC"; then
        echo "The path is already referenced in your .zshrc."
    else
        echo "" >> "$ZSHRC"
        echo "# Added by dev_setup script" >> "$ZSHRC"
        echo "$EXPORT_LINE" >> "$ZSHRC"
        echo "Success: Added to .zshrc. Run 'source ~/.zshrc' to update your current session."
    fi
fi