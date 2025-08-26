#!/bin/bash

# Script to generate a Brewfile in the current directory
# This will list all installed Homebrew packages, casks, and taps

echo "Generating Brewfile in the current directory..."

# Check if brew is installed
if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew is not installed. Please install Homebrew first."
    echo "Visit https://brew.sh for installation instructions."
    exit 1
fi

# Generate Brewfile in the current directory
brew bundle dump --force

echo "Brewfile has been generated successfully."
echo "You can find it at: $(pwd)/Brewfile"