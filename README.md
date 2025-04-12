# local-helpers
Local helper functions



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

### Load the underlying model.
```bash
ollama create commit -f ./dev/commit/Modelfile
```

## project-tree.sh
```bash
project-tree
```
Updates the project tree in README.md. Will be written to `start_marker="# Project Structure"` and `end_marker="### Stop Project Structure"` in README.md


# Project Structure
```
.
├── README.md
├── dev
│   ├── commit
│   │   ├── Modelfile
│   │   └── commit.sh
│   └── project-tree.sh
└── modelfiles

4 directories, 4 files
```
### Stop Project Structure
