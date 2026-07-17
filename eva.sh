#!/bin/bash
#
# Description: Autonomous AI Agent for code refactoring and self-evolution.
# Features: Multi-provider API (Ollama, OpenAI, Google, llama.cpp), Git backups, Secret Scanning (Guardrails), Isolated Smoke Testing, Target project selection, Stats & Reporting, Shellcheck, Dry-run, Endpoint override.
# Version: v2.3.0
#
set -euo pipefail

# --- CONFIGURATION & COLORS ---
readonly SCRIPT_NAME="${BASH_SOURCE[0]}"
readonly SCRIPT_VERSION="2.3.0"

# Target files (can be overridden by arguments)
TARGET_FILE="$SCRIPT_NAME"
README_FILE="readme.md"
CHANGES_FILE="changes.md"
PROMPT_FILE="prompt.md"

readonly OUTPUT_LOG="output.out"
readonly STATS_FILE="stats.json"

# API Defaults
PROVIDER="ollama"
MODEL="gpt-oss:20b"
API_URL=""
API_URL_CUSTOM=false
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-10}"
CURL_MAX_TIME="${CURL_MAX_TIME:-900}"
CONTEXT_SIZE="${CONTEXT_SIZE:-327680}"
MAX_STATS_ENTRIES="${MAX_STATS_ENTRIES:-1000}"

# Flags
DRY_RUN=false
SKIP_SHELLCHECK=false
NO_LLM=false
SHOW_STATS=false

# Load .env if exists for API keys (OpenAI, Google)
if [ -f ".env" ]; then
    # shellcheck disable=SC1091
    source .env
fi

# Colors
readonly RESET='\033[0m'
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'

# --- LOGGING UTILITIES ---
log_info() { echo -e "${BLUE}[INFO]${RESET} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${RESET} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${RESET} $1" >&2; }
log_stat() { echo -e "${CYAN}[STAT]${RESET} $1" >&2; }

# --- PARSE ARGUMENTS ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --target) TARGET_FILE="$2"; shift ;;
        --provider) PROVIDER="$2"; shift ;;
        --model) MODEL="$2"; shift ;;
        --api-url) API_URL="$2"; API_URL_CUSTOM=true; shift ;;
        --dry-run) DRY_RUN=true ;;
        --skip-shellcheck) SKIP_SHELLCHECK=true ;;
        --no-llm) NO_LLM=true ;;
        --stats) SHOW_STATS=true ;;
        --version)
            echo "Agent-Evolution (EVA) v${SCRIPT_VERSION}"
            exit 0
            ;;
        --help)
            echo "Usage: $SCRIPT_NAME [OPTIONS]"
            echo "Options:"
            echo "  --target <file>     Target script to refactor (default: self)"
            echo "  --provider <name>   API Provider: ollama, openai, google, llama.cpp"
            echo "  --model <name>      Model name to use"
            echo "  --api-url <url>     Override the API endpoint for the chosen provider"
            echo "  --dry-run           Test changes without overwriting files"
            echo "  --no-llm            Run without API request (uses output.out)"
            echo "  --stats             Print aggregated run statistics and exit"
            echo "  --version           Print version and exit"
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

    # Common patterns for API keys (Google, OpenAI legacy + project keys, AWS)
    local regex="(AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16})"

    if grep -E -q "$regex" "$file_to_check"; then
        log_error "SECURITY VIOLATION: Potential API key or secret detected in the LLM output!"
        log_error "Agent execution halted to prevent credential leakage."
        return 1
    fi
    log_success "Guardrails passed: No hardcoded secrets found."
    return 0
}

run_smoke_test() {
    # Dummy run of the generated script in an isolated environment:
    # empty sandbox dir + network namespace (when unshare is available).
    local script_to_test="$1"
    log_info "Guardrails: Executing isolated smoke test (dummy run)..."

    local sandbox
    sandbox=$(mktemp -d)
    local -a runner=(bash "$script_to_test" --help)
    if command -v unshare > /dev/null 2>&1 && unshare -rn true > /dev/null 2>&1; then
        runner=(unshare -rn bash "$script_to_test" --help)
    else
        log_warning "Smoke test: unshare unavailable, running in plain sandbox dir without network isolation."
    fi

    local rc=0
    (cd "$sandbox" && timeout 15 "${runner[@]}" > /dev/null 2>&1) || rc=$?
    rm -rf "$sandbox"

    if [ "$rc" -ne 0 ]; then
        log_error "Smoke test failed (exit code $rc): generated script does not survive a dummy run."
        return 1
    fi
    log_success "Smoke test passed: script executes cleanly in isolation."
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

    jq --argjson entry "$new_entry" --argjson max "$MAX_STATS_ENTRIES" \
        '.entries = ((.entries + [$entry])[-$max:])' "$STATS_FILE" > "${STATS_FILE}.tmp"
    mv "${STATS_FILE}.tmp" "$STATS_FILE"
    log_stat "Stats updated: $elapsed sec, Provider: $PROVIDER, Model: $MODEL"
}

show_stats() {
    # Aggregated report over stats.json for the --stats flag.
    if [ ! -f "$STATS_FILE" ]; then
        log_warning "No statistics collected yet ($STATS_FILE not found)."
        return 0
    fi
    log_stat "Aggregated run statistics from $STATS_FILE:"
    jq -r '
        .entries as $e
        | ($e | length) as $total
        | ([$e[] | select(.status == "success")] | length) as $ok
        | "  Total runs:    \($total)",
          "  Successful:    \($ok)",
          "  Failed:        \($total - $ok)",
          "  Success rate:  \(if $total > 0 then ($ok * 100 / $total | round) else 0 end)%",
          "  Avg duration:  \(if $total > 0 then (([$e[].elapsed_seconds] | add) / $total * 10 | round / 10) else 0 end)s",
          "  Providers:     \([$e[].provider] | unique | join(", "))",
          "  Models:        \([$e[].model] | unique | join(", "))"
    ' "$STATS_FILE"
}

# --- API INTEGRATION ---
resolve_endpoint() {
    # Print the API endpoint for the current provider; --api-url wins.
    if [ "$API_URL_CUSTOM" = true ]; then
        echo "$API_URL"
        return 0
    fi
    case "$PROVIDER" in
        ollama)    echo "http://localhost:11434/api/generate" ;;
        openai)    echo "https://api.openai.com/v1/chat/completions" ;;
        google)    echo "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=${GOOGLE_API_KEY:-}" ;;
        llama.cpp) echo "http://localhost:8080/completion" ;;
        *)         return 1 ;;
    esac
}

call_llm() {
    local prompt_payload="$1"

    local endpoint
    if ! endpoint=$(resolve_endpoint); then
        log_error "Unsupported provider: $PROVIDER"
        exit 1
    fi
    log_info "Sending request to $PROVIDER ($MODEL) at $endpoint..."

    # Escape quotes and newlines for JSON payload
    local json_safe_prompt
    json_safe_prompt=$(echo "$prompt_payload" | jq -Rsa .)

    local -a curl_opts=(-sS --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME")

    if [ "$PROVIDER" = "ollama" ]; then
        curl "${curl_opts[@]}" "$endpoint" -d "{\"model\": \"$MODEL\", \"prompt\": $json_safe_prompt, \"stream\": false, \"options\": {\"num_ctx\": $CONTEXT_SIZE}}" | jq -r '.response'
    elif [ "$PROVIDER" = "openai" ]; then
        curl "${curl_opts[@]}" -X POST "$endpoint" \
            -H "Authorization: Bearer ${OPENAI_API_KEY:-}" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$MODEL\", \"messages\": [{\"role\": \"user\", \"content\": $json_safe_prompt}]}" | jq -r '.choices[0].message.content'
    elif [ "$PROVIDER" = "google" ]; then
        curl "${curl_opts[@]}" -X POST "$endpoint" \
            -H 'Content-Type: application/json' \
            -d "{\"contents\": [{\"parts\":[{\"text\": $json_safe_prompt}]}]}" | jq -r '.candidates[0].content.parts[0].text'
    elif [ "$PROVIDER" = "llama.cpp" ]; then
        curl "${curl_opts[@]}" "$endpoint" \
            -H "Content-Type: application/json" \
            -d "{\"prompt\": $json_safe_prompt, \"n_predict\": 4096}" | jq -r '.content'
    fi
}

# --- PARSING & VALIDATION ---
extract_block() {
    # Extract the body of an XML-style block from the LLM response.
    # Tags are matched as exact whole lines and the tag name never appears
    # verbatim in this source, so self-mutation cannot corrupt the parser.
    local tag="$1"
    local content="$2"
    echo "$content" | awk -v tag="$tag" '
        $0 == ("<" tag ">") { flag = 1; next }
        $0 == ("</" tag ">") { flag = 0 }
        flag'
}

apply_changes() {
    local raw_response="$1"

    log_info "Parsing XML tags from LLM response..."

    # 1. Chain of Thought
    local thought_process
    thought_process=$(extract_block "THOUGHT_PROCESS" "$raw_response")

    if [ -n "$thought_process" ]; then
        log_info "Agent reasoning captured. Saving to thought.log..."
        echo -e "========== AGENT REASONING LOG | $(date) ==========\n$thought_process\n" >> "thought.log"
    fi

    # 2. Extract the remaining blocks
    local new_readme
    new_readme=$(extract_block "README" "$raw_response")

    local new_script
    new_script=$(extract_block "SCRIPT" "$raw_response")

    local new_changes
    new_changes=$(extract_block "CHANGES" "$raw_response")

    if [ -z "$new_script" ]; then
        log_error "Failed to extract the SCRIPT block. Refactoring aborted."
        [ -n "$thought_process" ] && echo -e "${YELLOW}Agent says:${RESET}\n$thought_process" >&2
        return 1
    fi

    # 3. Validation pipeline (Guardrails) — runs on temp copies BEFORE anything is written
    local tmp_dir
    tmp_dir=$(mktemp -d)

    local tmp_script="$tmp_dir/script.sh"
    printf '%s\n' "$new_script" > "$tmp_script"
    [ -n "$new_readme" ]  && printf '%s\n' "$new_readme"  > "$tmp_dir/readme.md"
    [ -n "$new_changes" ] && printf '%s\n' "$new_changes" > "$tmp_dir/changes.md"

    log_info "Guardrails: Validating Bash syntax (bash -n)..."
    if ! bash -n "$tmp_script"; then
        log_error "Syntax validation failed. Generated script is invalid, nothing was written."
        rm -rf "$tmp_dir"
        return 1
    fi
    log_success "Syntax validation passed."

    if [ "$SKIP_SHELLCHECK" = false ] && command -v shellcheck > /dev/null 2>&1; then
        log_info "Guardrails: Running ShellCheck static analysis..."
        if ! shellcheck --severity=error "$tmp_script" >&2; then
            log_error "ShellCheck found errors. Refactoring aborted."
            rm -rf "$tmp_dir"
            return 1
        fi
        shellcheck "$tmp_script" >&2 || log_warning "ShellCheck reported non-critical warnings (see above)."
    fi

    local generated_file
    for generated_file in "$tmp_dir"/*; do
        if ! check_secrets "$generated_file"; then
            rm -rf "$tmp_dir"
            return 1
        fi
    done

    if ! run_smoke_test "$tmp_script"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        log_success "Dry-run: all validations passed. No files were modified."
        rm -rf "$tmp_dir"
        return 0
    fi

    # 4. Atomic writes: temp file in the destination directory, then mv
    write_atomic "$tmp_script" "$TARGET_FILE"
    [ -n "$new_readme" ]  && write_atomic "$tmp_dir/readme.md" "$README_FILE"
    [ -n "$new_changes" ] && write_atomic "$tmp_dir/changes.md" "$CHANGES_FILE"

    log_success "All changes applied to $TARGET_FILE."
    rm -rf "$tmp_dir"
    return 0
}

write_atomic() {
    local src="$1"
    local dest="$2"
    local dest_tmp="${dest}.tmp.$$"
    cp "$src" "$dest_tmp"
    if [ -f "$dest" ]; then
        chmod --reference="$dest" "$dest_tmp" 2>/dev/null || true
    fi
    mv -f "$dest_tmp" "$dest"
}

# --- MAIN EXECUTION LOOP ---
main() {
    if [ "$SHOW_STATS" = true ]; then
        show_stats
        exit 0
    fi

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
