#!/bin/bash

## Function to generate commit message using local Ollama LLM
commit() {
  # --- Configuration ---
  # IMPORTANT: Change this to your preferred Ollama model name if needed!
  local OLLAMA_MODEL="gemma3:1b"
  local OLLAMA_API_ENDPOINT="http://localhost:11434/api/generate"
  # --- /Configuration ---

  # Check if jq is installed
  if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' command not found. Please install jq." >&2
    return 1
  fi

  # Check if curl is installed
  if ! command -v curl &> /dev/null; then
    echo "Error: 'curl' command not found. Please install curl." >&2
    return 1
  fi

  # Check if inside a git repository
  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
      echo "Error: Not inside a git repository." >&2
      return 1
  fi

  # 1. Get the diff
  # Use git diff HEAD for all changes (staged & unstaged) vs last commit
  # Use 'git diff' for only unstaged changes
  # Use 'git diff --staged' for only staged changes
  local git_diff
  git_diff=$(git diff HEAD)

  if [ -z "$git_diff" ]; then
    # If you prefer to check only staged changes for commit:
    local staged_diff=$(git diff --staged)
    if [ -z "$staged_diff" ]; then
        echo "No changes detected (vs HEAD) and no changes staged for commit."
        return 0 # Exit gracefully
    else
        echo "Using staged changes for commit message generation..."
        git_diff=$staged_diff
    fi
    # If you want to *always* use HEAD diff even if empty, remove the staged check above
    # and just uncomment the below 'return 0'
    # echo "No changes detected to commit (compared to HEAD)."
    # return 0
  fi

  # 2. Get the last 3 commit messages (subject lines only)
  local last_commits
  last_commits=$(git log --pretty=format:"%s" -n 3)
  if [ $? -ne 0 ]; then
      echo "Warning: Error getting git log. Proceeding without recent commit context." >&2
      last_commits="Could not retrieve recent commits."
  fi

  # 3. Construct the prompt for the LLM
  # Note: Using heredoc with <<- allows leading tabs for formatting here, but not spaces.
  local prompt_text
  prompt_text=$(cat <<-PROMPT
Please generate a concise and informative commit message in the conventional commit format (e.g., feat: ..., fix: ..., chore: ..., docs: ...).
The message should summarize the following changes. Output ONLY the commit message itself, without any extra explanations, preamble, or quotation marks surrounding the message.

Recent Commit Messages (if any):
$last_commits

Current Changes (Git Diff):
\`\`\`diff
$git_diff
\`\`\`

Generate commit message:
PROMPT
)

  # Add a debug line to show the prompt being sent (optional)
  # echo "-------------------------------------"
  # echo "Input Prompt Message:"
  # echo "$prompt_text"
  # echo "-------------------------------------"

  # 4. Prepare the JSON payload for Ollama using jq
  local json_payload
  json_payload=$(jq -n --arg model "$OLLAMA_MODEL" --arg prompt "$prompt_text" \
    '{
      model: $model,
      prompt: $prompt,
      stream: false,
      options: {
        "temperature": 0.5,
        "num_predict": 100
      }
    }')

  # Check if jq succeeded in creating the payload
  if [ $? -ne 0 ]; then
    echo "Error: Failed creating JSON payload with jq. Check prompt content or jq installation." >&2
    return 1
  fi

  echo "Asking Ollama ($OLLAMA_MODEL) to generate commit message..."

  # 5. Send request to Ollama API and capture the response
  local ollama_response
  ollama_response=$(curl -s -X POST "$OLLAMA_API_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "$json_payload")

  # Check if curl command was successful
  if [ $? -ne 0 ]; then
    echo "Error: Failed to connect to Ollama API at $OLLAMA_API_ENDPOINT." >&2
    echo "Please ensure Ollama is running ('ollama serve')." >&2
    return 1
  fi

  # 6. Parse the response to extract the commit message
  # Use simpler jq extraction first, then shell cleanup for robustness against malformed JSON strings
  local llm_message
  llm_message=$(echo "$ollama_response" | jq -r '.response // empty') # Use // empty as fallback

  # Shell-based cleanup of potential leading/trailing whitespace or quotes
  # Needs extended glob patterns (usually enabled by default in modern bash/zsh)
  llm_message="${llm_message#"${llm_message%%[![:space:]]*}"}" # Remove leading whitespace
  llm_message="${llm_message%"${llm_message##*[![:space:]]}"}" # Remove trailing whitespace
  llm_message="${llm_message#\"}" # Remove leading quote if present
  llm_message="${llm_message%\"}" # Remove trailing quote if present
  # Remove potential carriage returns often inserted by models
  llm_message=$(echo "$llm_message" | tr -d '\r')

  # Check if the message extraction resulted in an empty string or the string "null"
  # Use POSIX standard '=' for string comparison inside single brackets [ ]
  if [ -z "$llm_message" ] || [ "$llm_message" = "null" ]; then
    echo "Error: Failed to get a valid message from Ollama." >&2
    echo "Ollama Raw Response: $ollama_response" # Print raw response for debugging
    return 1
  fi

  # 7. Display the message and ask for confirmation
  echo "-------------------------------------"
  echo "Generated Commit Message:"
  echo "$llm_message"
  echo "-------------------------------------"

  # Separate prompt and read for better portability (especially with Zsh - avoids '-p: no coprocess' error)
  echo -n "Do you want to commit with this message? (y/N) " # Print prompt without newline
  # Read response directly from terminal, -r prevents backslash interpretation
  read -r confirm < /dev/tty
  echo # Add a newline after user input for cleaner output

  # Check if the user confirmed with 'y' or 'Y'
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "Staging all changes and committing..."
    # 8. Stage all changes and commit
    # IMPORTANT: 'git add .' stages ALL unstaged files in the current directory and below.
    # If you prefer to only commit files you've manually staged before running the script,
    # you can comment out the 'git add .' line.
    if git add .; then
      # Commit using the generated message
      if git commit -m "$llm_message"; then
        echo "Commit successful."
      else
        echo "Error: 'git commit' command failed." >&2
        # Attempt to unstage if commit failed? Optional.
        # git reset HEAD -- .
        return 1 # Propagate git commit error
      fi
    else
      echo "Error: 'git add .' command failed." >&2
      return 1 # Propagate git add error
    fi
  else
    echo "Commit aborted by user."
  fi
}