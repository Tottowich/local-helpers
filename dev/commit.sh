#!/bin/bash

## Function to generate commit message using local Ollama LLM
commit() {
  # --- Configuration ---
  local OLLAMA_MODEL="gemma3:4b"
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
  local git_diff
  git_diff=$(git diff HEAD)

  if [ -z "$git_diff" ]; then
    local staged_diff=$(git diff --staged)
    if [ -z "$staged_diff" ]; then
        echo "No changes detected (vs HEAD) and no changes staged for commit."
        return 0 # Exit gracefully
    else
        echo "Using staged changes for commit message generation..."
        git_diff=$staged_diff
    fi
  fi

  # 2. Get the last 3 commit messages (subject lines only)
  local last_commits
  last_commits=$(git log --pretty=format:"%s" -n 3)
  if [ $? -ne 0 ]; then
      echo "Warning: Error getting git log. Proceeding without recent commit context." >&2
      last_commits="Could not retrieve recent commits."
  fi

  # 3. Construct the prompt for the LLM
  local prompt_text
  prompt_text=$(cat <<-PROMPT
Please generate a concise and informative commit message in the conventional commit format (e.g., feat: ..., fix: ..., chore: ..., docs: ...). 
The message should summarize the following changes. Include specific information if the diff is small such as a single line, but be concise. Focus on the key points of the changes if the diff is large. 
Output ONLY the commit message itself, without any extra explanations, preamble, or quotation marks surrounding the message.

+ signifies addition, - signifies deletion, ~ signifies change.
Current Changes (Git Diff):
\`\`\`diff
$git_diff
\`\`\`

New Commit Message Based on diff above:
PROMPT
)

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
  echo "$json_payload"

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

  if [ $? -ne 0 ]; then
    echo "Error: Failed to connect to Ollama API at $OLLAMA_API_ENDPOINT." >&2
    echo "Please ensure Ollama is running ('ollama serve')." >&2
    return 1
  fi
  # 6. Parse the response to extract the commit message
  local llm_message

  # --- Now parse the SANITIZED response with jq ---
  llm_message=$(echo "$ollama_response" | tr -d '\n\r' | jq -r '.response')

  # Check if jq command itself failed (e.g., still invalid JSON after sanitizing)
  if [ $? -ne 0 ]; then
      echo "Error: 'jq' failed to parse the Ollama response even after sanitizing." >&2
      echo "Ollama Raw Response (Original): $ollama_response" # Show original raw response
      return 1
  fi

  # Shell-based cleanup of potential leading/trailing whitespace or quotes
  # (Keep this part as it handles other cleanup after jq)
  llm_message="${llm_message#"${llm_message%%[![:space:]]*}"}" # Remove leading whitespace
  llm_message="${llm_message%"${llm_message##*[![:space:]]}"}" # Remove trailing whitespace
  llm_message="${llm_message#\"}" # Remove leading quote if present
  llm_message="${llm_message%\"}" # Remove trailing quote if present
  # No need for another tr -d '\r' here, already done before jq

  # Check if the message extraction resulted in an empty string or the string "null"
  # Use POSIX standard '=' for string comparison inside single brackets [ ]
  if [ -z "$llm_message" ] || [ "$llm_message" = "null" ]; then
    echo "Error: Failed to get a valid message from Ollama (jq extraction failed or returned empty/null)." >&2
    echo "Ollama Raw Response (Original): $ollama_response" # Print raw response for debugging
    return 1
  fi


  # 7. Display the message and ask for confirmation
  echo "-------------------------------------"
  echo "Generated Commit Message:"
  echo "$llm_message"
  echo "-------------------------------------"

  echo -n "Do you want to commit with this message? (y/N) "
  read -r confirm < /dev/tty
  echo # Add a newline

  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "Staging all changes and committing..."
    # 8. Stage all changes and commit
    if git add .; then
      if git commit -m "$llm_message"; then
        echo "Commit successful."
      else
        echo "Error: 'git commit' command failed." >&2
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