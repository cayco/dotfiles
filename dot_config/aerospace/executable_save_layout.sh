#!/bin/bash
# Saves the window-id and workspace name for each window to a CSV file.
aerospace list-windows --all --format '%{window-id},%{workspace}' > ~/.config/aerospace/layout.csv
echo "Window layout saved to layout.csv"
