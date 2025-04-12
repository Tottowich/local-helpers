# local-helpers
Local helper functions

# Project Structure
```
.
├── README.md
└── dev
    ├── commit.sh
    └── project-tree.sh

2 directories, 3 files
```
### Stop Project Structure



# Expose the defined functions
Add the following to the repo root into your zshrc or bashrc

```bash
repo="<path-to-repo>/local-helpers" # Define the repo variable

if [ -d "$repo" ]; then
  find "$repo" -type f -name "*.sh" -print0 | while IFS= read -r -d $' ' func_file; do
    source "$func_file"
  done
fi
```

## commit.sh
```bash
commit
```
Produce a commit message using local Ollama LLM based on the current git diff in the project.
Does not commit unless approved by the user.

## project-tree.sh
```bash
project-tree
```
Updates the project tree in README.md. Will be written to `start_marker="# Project Structure"` and `end_marker="### Stop Project Structure"` in README.md