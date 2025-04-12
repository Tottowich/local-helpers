#!/bin/bash

# File: dev/project-tree.sh
# Defines the project-tree function to update README.md

# Depends on the 'tree' command.
# Install: brew install tree | sudo apt install tree | sudo dnf install tree

project-tree() {
    local readme_file="README.md"
    # --- Use non-empty markers! ---
    local start_marker="# Project Structure"
    local end_marker=""
    # --- Patterns to ignore ---
    local ignore_pattern='node_modules|venv|.git'
    local tmp_file
    local tree_output
    local inside_markers=0 # Flag to track if we are between markers

    # === 1. Pre-checks ===

    # Check if README.md exists
    if [[ ! -f "$readme_file" ]]; then
        echo "Error: '$readme_file' not found in the current directory." >&2 # Error to stderr
        return 1
    fi

    # Check if 'tree' command is available
    if ! command -v tree &> /dev/null; then
        echo "Error: 'tree' command not found. Please install it (e.g., brew install tree)." >&2
        return 1
    fi

    # Check if markers exist in the README
    # Use grep -F for fixed string matching (safer for markers)
    # Use grep -q to suppress output
    if ! grep -q -F "$start_marker" "$readme_file" || ! grep -q -F "$end_marker" "$readme_file"; then
        echo "Error: Markers not found in '$readme_file'." >&2
        echo "Please add these lines where you want the tree:" >&2
        echo "$start_marker" >&2
        echo "$end_marker" >&2
        return 1
    fi

    # === 2. Generate Tree Output ===
    echo "Generating project tree (ignoring: $ignore_pattern)..."
    # Capture tree output, handle potential errors during execution
    # --- Execute the command directly ---
    if ! tree_output=$(tree -a -I "$ignore_pattern"); then
        # --- Update the error message ---
        echo "Error: Failed to execute 'tree -a -I \"$ignore_pattern\"'." >&2
        return 1
    fi

    # Optional: Check if tree output is empty (can happen in an empty dir)
    if [[ -z "$tree_output" ]]; then
        echo "Warning: 'tree' generated empty output. Inserting empty block." >&2
    fi

    # === 3. Update README using a temporary file ===
    echo "Updating '$readme_file'..."
    # Create a temporary file securely
    tmp_file=$(mktemp) || { echo "Error: Failed to create temporary file." >&2; return 1; }
    # Ensure temp file is removed even if the script fails or is interrupted
    trap 'rm -f "$tmp_file"' EXIT HUP INT QUIT TERM

    # Process the README line by line
    while IFS= read -r line || [[ -n "$line" ]]; do # Handle last line if no newline
        if [[ "$line" == "$start_marker" ]]; then
            # Found start marker: write it, write new content, start skipping old lines
            echo "$line" >> "$tmp_file"
            echo '```' >> "$tmp_file"       # Start markdown code block
            echo "$tree_output" >> "$tmp_file" # Insert the generated tree
            echo '```' >> "$tmp_file"       # End markdown code block
            inside_markers=1
        elif [[ "$line" == "$end_marker" ]]; then
            # Found end marker: write it, stop skipping lines
            echo "$line" >> "$tmp_file"
            inside_markers=0
        elif [[ $inside_markers -eq 0 ]]; then
            # Outside markers: copy the original line
            echo "$line" >> "$tmp_file"
        fi
        # Lines inside the original markers (when inside_markers=1) are skipped
    done < "$readme_file"

    # Final check: Ensure we actually found the end marker
    if [[ $inside_markers -eq 1 ]]; then
         echo "Error: Found start marker '$start_marker' but processing finished before finding end marker '$end_marker'." >&2
         echo "'$readme_file' was not updated." >&2
         # Temp file is removed by trap
         return 1
    fi

    # === 4. Replace Original File ===
    # Overwrite the original README with the updated temporary file
    # Using 'cat >' is often safer than 'mv' for preserving metadata/permissions in some cases
    cat "$tmp_file" > "$readme_file" || { echo "Error: Failed to write updates to '$readme_file'." >&2; return 1; }

    # Temp file will be removed by the trap on successful exit
    echo "Successfully updated project tree in '$readme_file'."
    return 0 # Success
}