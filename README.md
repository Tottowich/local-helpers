# local-helpers

A collection of shell helper functions designed to streamline common development tasks locally.

## Requirements

Before using these helpers, ensure you have the following installed:

* **Shell:** Bash or Zsh
* **Core Utilities:** `find`, `git` (Standard Unix/Linux/macOS utilities, usually pre-installed).
* **`tree` command:** Required for the `project-tree` helper.
    * Install via package manager (e.g., `sudo apt install tree`, `brew install tree`).
* **Ollama:** Required *only* for the `commit` helper.
    * Download and install from [https://ollama.com/](https://ollama.com/).
    * Ensure the Ollama service/application is running in the background (often started automatically or via `ollama serve`).

## Setup

1.  **Clone the Repository:** Clone this repository to a permanent location on your machine, for example:
    ```bash
    git clone https://github.com/Tottowich/local-helpers.git
    ```

2.  **Expose Functions:** Add the following snippet to your shell configuration file (`~/.zshrc` for Zsh, `~/.bashrc` or `~/.bash_profile` for Bash). This will automatically find and load (source) all `.sh` files within this repository, making the functions available in your terminal sessions.

    **Important:** Replace `<path-to-repo>` with the **actual absolute path** where you cloned `local-helpers`.

    ```bash
    # --- Load local-helpers functions ---
    repo="/path/to/your/cloned/local-helpers" # <-- IMPORTANT: SET THIS PATH!

    if [ -d "$repo" ]; then
      # Find all .sh files and source them safely (handles spaces/special chars)
      find "$repo" -type f -name "*.sh" -print0 | while IFS= read -r -d $'\0' func_file; do
        source "$func_file"
      done
      unset func_file
    fi
    unset repo
    # --- End local-helpers ---
    ```

3.  **Apply Changes:** Restart your shell or source your configuration file for the changes to take effect (e.g., run `source ~/.zshrc` or `source ~/.bashrc`).

## Available Helpers

### `commit`

Automatically generates a concise commit message based on the staged or unstaged changes (`git diff`) in your current Git repository using a local Ollama LLM.

**Usage:**

Navigate to your Git project directory and run:

```bash
commit
```

The script will:
1.  Detect staged or unstaged changes compared to HEAD.
2.  Send the diff and context to your local Ollama instance.
3.  Display the AI-generated commit message.
4.  Prompt you for confirmation (`y/N`) before proceeding.
5.  If confirmed and unstaged changes were used, it runs `git add .` to stage them.
6.  Run `git commit -m "..."` with the generated (or edited, if implemented) message.

**Specific Requirements:**

* Ollama application/service must be installed and **running**.
* The custom `commit` Ollama model must be created (see below).

**Model Creation (One-Time Setup):**

The `commit` helper relies on a custom Ollama model tailored for generating commit messages. This model is defined by the `Modelfile` located in `dev/commit/Modelfile`. You need to create this model within Ollama before using the `commit` function for the first time.

Run the following command from the **root directory of this `local-helpers` repository**:

```bash
ollama create commit -f ./dev/commit/Modelfile
```

This command tells Ollama to create a new model named `commit` based on the instructions in the specified `Modelfile`. You only need to do this once (or again if you update the `Modelfile`).

### `project-tree`

Generates a directory tree structure of the current project and updates the `# Project Structure` section in the `README.md` file located in the current directory.

**Usage:**

Navigate to your project directory (where the `README.md` resides) and run:

```bash
project-tree
```

The script uses the `tree` command (excluding common ignore patterns like `.git`, `node_modules`) and inserts its output into `README.md` between specific marker lines:

* **Start Marker:** `# Project Structure`
* **End Marker:** `### Stop Project Structure`

Ensure these exact lines exist in your `README.md` where you want the tree to be placed. The content between these markers will be overwritten.

**Specific Requirements:**

* The `tree` command must be installed.

## Project Structure

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