#!/bin/bash

## Function to generate commit message using local Ollama LLM
commit() {
  # --- Configuration ---
  local OLLAMA_MODEL="commit" # See Modelfile for system prompt.
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

  # 1. Get the diff and determine which files to list
  local git_diff
  local modified_files
  local using_staged=false

  git_diff=$(git diff HEAD) # Check unstaged changes first

  if [ -z "$git_diff" ]; then
    local staged_diff=$(git diff --staged)
    if [ -z "$staged_diff" ]; then
        echo "No changes detected (vs HEAD) and no changes staged for commit."
        return 0 # Exit gracefully
    else
        echo "Using staged changes for commit message generation..."
        git_diff=$staged_diff
        modified_files=$(git diff --name-only --staged) # List staged files
        using_staged=true
    fi
  else
    # Using unstaged changes
    modified_files=$(git diff --name-only HEAD) # List unstaged files
  fi

  # 2. Get additional context
  local branch_name
  branch_name=$(git rev-parse --abbrev-ref HEAD)

  local prev_commit_messages
  prev_commit_messages=$(git log --format="%s" --max-count=3)

  # 3. Construct the prompt for the LLM
  modified_files=$(echo "$modified_files" | tr '\n' ' ')
  local prompt_text
  prompt_text=$(cat <<-PROMPT
  --- Context ---
  Current Git Branch: $branch_name
  Files Modified:
  $modified_files

  --- Changes (Git Diff) ---
  \`\`\`diff
  $git_diff
  \`\`\`

  Commit Message:
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
        "temperature": 1.0,
        "num_predict": 40
      }
    }')

  echo "$json_payload" # Optional: uncomment to debug the payload

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

  # --- Now parse the response with jq ---
  # Attempt to directly parse; handle potential errors below
  llm_message=$(echo "$ollama_response" | tr -d '\n\r' | sed 's/\\"/\"/g' | jq -r '.response')

  # Shell-based cleanup of potential leading/trailing whitespace or quotes AFTER successful jq extraction
  llm_message="${llm_message#"${llm_message%%[![:space:]]*}"}" # Remove leading whitespace
  llm_message="${llm_message%"${llm_message##*[![:space:]]}"}" # Remove trailing whitespace


  # Final check if message is empty after cleanup
  if [ -z "$llm_message" ]; then
    echo "Error: Extracted message was empty after cleanup." >&2
    echo "Ollama Raw Response: $ollama_response"
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
    echo "Staging changes and committing..."
    # 8. Stage changes and commit
    local add_cmd_result=0
    local commit_cmd_result=0

    # Only run `git add .` if we weren't using staged changes initially.
    # If we were using staged changes, the user likely wants only those committed.
    if [ "$using_staged" = false ]; then
        echo "Running 'git add .' to stage changes..."
        git add .
        add_cmd_result=$?
    else
        echo "Using already staged changes for the commit."
        # No need to run git add . if we specifically used staged diff
    fi

    if [ $add_cmd_result -eq 0 ]; then
        git commit -m "$llm_message"
        commit_cmd_result=$?
        if [ $commit_cmd_result -eq 0 ]; then
            echo "Commit successful."
        else
            echo "Error: 'git commit' command failed with exit code $commit_cmd_result." >&2
            return 1 # Propagate git commit error
        fi
    else
      echo "Error: 'git add .' command failed with exit code $add_cmd_result." >&2
      return 1 # Propagate git add error
    fi
  else
    echo "Commit aborted by user."
  fi
}