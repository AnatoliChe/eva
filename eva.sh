#!/bin/bash
#
# Description: Autonomous AI Agent for code refactoring and self-evolution.
# Features: Multi-provider API (Ollama, OpenAI, Google, llama.cpp), Git backups, Secret Scanning (Guardrails), Target project selection, Stream processing, Stats, Shellcheck, Dry-run.
# Version: v2.0.1
#
set -euo pipefail

# --- CONFIGURATION & COLORS ---
readonly SCRIPT_NAME="${BASH_SOURCE[0]}"
readonly SCRIPT_BASENAME="$(basename "$SCRIPT_NAME")"
readonly SCRIPT_VERSION="2.0.1"

# Target files (can be overridden by arguments)
TARGET_FILE="$SCRIPT_NAME"
README_FILE="readme.md"
CHANGES_FILE="changes.md"
PROMPT_FILE="prompt.md"

readonly OUTPUT_LOG="output.out"
readonly OUTPUT_STREAM="output.stream"
readonly STATS_FILE="stats.json"
readonly STATS_LOG="stats.log"
readonly TEMP_TOKEN_FILE="/tmp/.agent_tokens_$$"

# API Defaults
PROVIDER="ollama"
MODEL="gpt-oss:20b"
API_URL="http://localhost:11434/api/generate"
CONTEXT_SIZE="${CONTEXT_SIZE:-327680}"
MAX_STATS_ENTRIES="${MAX_STATS_ENTRIES:-1000}"

# Flags
DRY_RUN=false
SKIP_SHELLCHECK=false
NO_LLM=false

# Load .env if exists for API keys (OpenAI, Google)
if [ -f ".env" ]; then
    source .env
fi

# Colors
readonly RESET='\033[0m'
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'

# --- LOGGING UTILITIES ---
log_info() { echo -e "${BLUE}[INFO]${RESET} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${RESET} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${RESET} $1" >&2; }
log_stat() { echo -e "${CYAN}[STAT]${RESET} $1" >&2; }
log_progress() { echo -ne "\r${CYAN}[PROGRESS]${RESET} $1          " >&2; }

# --- PARSE ARGUMENTS ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --target) TARGET_FILE="$2"; shift ;;
        --provider) PROVIDER="$2"; shift ;;
        --model) MODEL="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --skip-shellcheck) SKIP_SHELLCHECK=true ;;
        --no-llm) NO_LLM=true ;;
        --help)
            echo "Usage: $SCRIPT_NAME [OPTIONS]"
            echo "Options:"
            echo "  --target <file>     Target script to refactor (default: self)"
            echo "  --provider <name>   API Provider: ollama, openai, google, llama.cpp"
            echo "  --model <name>      Model name to use"
            echo "  --dry-run           Test changes without overwriting files"
            echo "  --no-llm            Run without API request (uses output.out)"
            exit 0
            ;;
        *) log_error "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# --- SECURITY GUARDRAILS ---
check_secrets() {
    local file_to_check="$1"
    log_info "Guardrails: Scanning for leaked secrets in generated code..."
    
    # Common patterns for API keys
    local regex="(AIza[0-9A-Za-z_-]{35}|sk-[a-zA-Z0-9]{48}|AKIA[0-9A-Z]{16})"
    
    if grep -E -q "$regex" "$file_to_check"; then
        log_error "SECURITY VIOLATION: Potential API key or secret detected in the LLM output!"
        log_error "Agent execution halted to prevent credential leakage."
        return 1
    fi
    log_success "Guardrails passed: No hardcoded secrets found."
    return 0
}

# --- GIT BACKUP ---
create_backup() {
    log_info "Creating atomic backup via Git..."
    if [ ! -d ".git" ]; then
        log_info "Initializing new Git repository..."
        git init
    fi
    
    git add "$TARGET_FILE" "$README_FILE" "$CHANGES_FILE" || true
    
    if ! git diff --cached --quiet; then
        git commit -m "Auto-backup before AI refactoring (v${SCRIPT_VERSION})" > /dev/null
        log_success "Git backup committed successfully."
    else
        log_info "No local changes to backup."
    fi
}

# --- STATS MANAGEMENT ---
update_stats() {
    local start_time="$1"
    local end_time="$2"
    local status="$3"
    local elapsed=$((end_time - start_time))
    
    if [ ! -f "$STATS_FILE" ]; then
        echo '{"entries":[]}' > "$STATS_FILE"
    fi
    
    local new_entry
    new_entry=$(jq -n \
       --arg ts "$(date -Iseconds)" \
       --argjson elapsed_seconds "${elapsed:-0}" \
       --arg status "$status" \
       --arg model "$MODEL" \
       --arg provider "$PROVIDER" \
       '$ARGS.named')
       
    local current_json
    current_json=$(cat "$STATS_FILE")
    echo "$current_json" | jq --argjson entry "$new_entry" '.entries += [$entry]' > "${STATS_FILE}.tmp"
    mv "${STATS_FILE}.tmp" "$STATS_FILE"
    log_stat "Stats updated: $elapsed sec, Provider: $PROVIDER, Model: $MODEL"
}

# --- API INTEGRATION ---
call_llm() {
    local prompt_payload="$1"
    log_info "Sending request to $PROVIDER ($MODEL)..."
    
    # Escape quotes and newlines for JSON payload
    local json_safe_prompt
    json_safe_prompt=$(echo "$prompt_payload" | jq -Rsa .)

    if [ "$PROVIDER" = "ollama" ]; then
        curl -s "$API_URL" -d "{\"model\": \"$MODEL\", \"prompt\": $json_safe_prompt, \"stream\": false, \"options\": {\"num_ctx\": $CONTEXT_SIZE}}" | jq -r '.response'
    elif [ "$PROVIDER" = "openai" ]; then
        curl -s -X POST "https://api.openai.com/v1/chat/completions" \
            -H "Authorization: Bearer ${OPENAI_API_KEY:-}" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$MODEL\", \"messages\": [{\"role\": \"user\", \"content\": $json_safe_prompt}]}" | jq -r '.choices[0].message.content'
    elif [ "$PROVIDER" = "google" ]; then
        curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=${GOOGLE_API_KEY:-}" \
            -H 'Content-Type: application/json' \
            -d "{\"contents\": [{\"parts\":[{\"text\": $json_safe_prompt}]}]}" | jq -r '.candidates[0].content.parts[0].text'
    elif [ "$PROVIDER" = "llama.cpp" ]; then
        curl -s "http://localhost:8080/completion" \
            -H "Content-Type: application/json" \
            -d "{\"prompt\": $json_safe_prompt, \"n_predict\": 4096}" | jq -r '.content'
    else
        log_error "Unsupported provider: $PROVIDER"
        exit 1
    fi
}

# --- PARSING & VALIDATION ---
apply_changes() {
    local raw_response="$1"
    
    log_info "Parsing XML tags from LLM response..."
    
    local new_readme
    new_readme=$(echo "$raw_response" | awk '/<README>/{flag=1; next} /<\/README>/{flag=0} flag')
    
    local new_script
    new_script=$(echo "$raw_response" | awk '/<SCRIPT>/{flag=1; next} /<\/SCRIPT>/{flag=0} flag')
    
    local new_changes
    new_changes=$(echo "$raw_response" | awk '/<CHANGES>/{flag=1; next} /<\/CHANGES>/{flag=0} flag')
    
    if [ -z "$new_script" ]; then
        log_error "Failed to extract <SCRIPT> section. Refactoring aborted."
        return 1
    fi

    # Write to temp file for validation
    local temp_script="/tmp/agent_target_temp_$$.sh"
    echo "$new_script" > "$temp_script"
    
    # Guardrails: Check for secrets
    if ! check_secrets "$temp_script"; then return 1; fi
    
    # Syntax Validation
    log_info "Validating Bash syntax..."
    if ! bash -n "$temp_script"; then
        log_error "Syntax validation failed (bash -n). Aborting."
        return 1
    fi
    
    # Shellcheck Validation
    if [ "$SKIP_SHELLCHECK" = false ] && command -v shellcheck &> /dev/null; then
        log_info "Running ShellCheck..."
        if ! shellcheck "$temp_script"; then
            log_warning "ShellCheck found issues! Proceeding anyway, but please review."
        fi
    fi
    
    # Apply changes
    if [ "$DRY_RUN" = false ]; then
        mv "$temp_script" "$TARGET_FILE"
        chmod +x "$TARGET_FILE"
        
        if [ -n "$new_readme" ] && [ "$TARGET_FILE" = "$SCRIPT_NAME" ]; then
            echo "$new_readme" > "$README_FILE"
        fi
        
        if [ -n "$new_changes" ] && [ "$TARGET_FILE" = "$SCRIPT_NAME" ]; then
            # Append changes to the top of the file
            echo -e "## $(date +%Y-%m-%d)\n$new_changes\n\n$(cat "$CHANGES_FILE")" > "$CHANGES_FILE"
        fi
        
        log_success "Refactoring applied to $TARGET_FILE successfully."
    else
        log_info "Dry-run complete. Changes are valid but were not applied."
        rm "$temp_script"
    fi
}

# --- MAIN EXECUTION LOOP ---
main() {
    log_info "Starting Agent-Evolution v${SCRIPT_VERSION}"
    log_info "Target File: $TARGET_FILE"
    
    local start_time
    start_time=$(date +%s)
    
    create_backup
    
    # Build Context
    local target_content
    target_content=$(cat "$TARGET_FILE" 2>/dev/null || echo "")
    local readme_content
    readme_content=$(cat "$README_FILE" 2>/dev/null || echo "")
    local changes_content
    changes_content=$(cat "$CHANGES_FILE" 2>/dev/null || echo "")
    local prompt_instructions
    prompt_instructions=$(cat "$PROMPT_FILE" 2>/dev/null || echo "")
    
    local full_prompt
    full_prompt=$(cat <<EOF
Target Script Code:
$target_content

Project Documentation (Readme):
$readme_content

Recent Changes:
$changes_content

Task Instructions:
$prompt_instructions
EOF
)

    local response=""
    if [ "$NO_LLM" = false ]; then
        response=$(call_llm "$full_prompt")
        echo "$response" > "$OUTPUT_LOG"
    else
        log_info "Running in --no-llm mode. Loading previous response."
        response=$(cat "$OUTPUT_LOG")
    fi
    
    # Apply and validate
    if apply_changes "$response"; then
        update_stats "$start_time" "$(date +%s)" "success"
    else
        update_stats "$start_time" "$(date +%s)" "failed"
        log_error "Refactoring failed. Reverting to previous state."
        git checkout -- "$TARGET_FILE" "$README_FILE" "$CHANGES_FILE" 2>/dev/null || true
    fi
}

main
