# local-helpers
Local helper functions


# Expose the defined functions
Add the following to the repo root into your zshrc or bashrc

```bash
repo="<path-to-repo>/local-helpers" # Define the repo variable

if [ -d "$repo" ]; then
  find "$repo" -type f -name "*.sh" -print0 | while IFS= read -r -d $'\0' func_file; do
    source "$func_file"
  done
fi
```