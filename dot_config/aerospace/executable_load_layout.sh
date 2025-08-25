#!/bin/bash
sleep 15

LAYOUT_FILE="$HOME/.config/aerospace/layout.csv"

if [ ! -f "$LAYOUT_FILE" ]; then
    echo "Layout file not found!"
    exit 1
fi

while IFS=, read -r window_id workspace; do
    if [ -z "$window_id" ] || [ -z "$workspace" ]; then
        continue
    fi
    
    echo "Moving window ID $window_id to workspace $workspace..."
    aerospace focus --window-id "$window_id" && aerospace move-node-to-workspace "$workspace"
    sleep 0.1
done < "$LAYOUT_FILE"

aerospace workspace 1
echo "Window layout restored."
