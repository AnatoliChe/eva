## 2026-07-17

### v2.1.1
* **Critical Fix — Restored Validation & Write Pipeline:** The `apply_changes()` function was truncated mid-body (likely by an interrupted self-mutation), leaving the script with a syntax error and no code that actually validated or wrote generated files. Restored the full pipeline: `bash -n` syntax check → ShellCheck (errors are fatal, warnings reported) → `check_secrets()` on every generated file → atomic write via same-directory temp file + `mv`.
* **Guardrails Now Enforced:** `check_secrets()` was previously defined but never called; it now scans the generated script, readme, and changelog before anything touches disk. `--dry-run` runs the full validation pipeline without writing.
* **Secret Scanner Update:** Broadened the OpenAI key pattern to cover modern project-scoped keys (`sk-` followed by 20+ chars).
* **Stats Rotation:** `stats.json` is now trimmed to the last `MAX_STATS_ENTRIES` (default 1000) entries.
* **Cleanup:** Removed unused variables (`OUTPUT_STREAM`, `STATS_LOG`, `TEMP_TOKEN_FILE`, `MAGENTA`); fixed usage examples in readme (`gen.sh` → `eva.sh`).

## 2026-06-25

### v2.1.0
* **Chain-of-Thought (CoT) Architecture:** Implemented ReAct-style reasoning. The agent is now required to output a `<THOUGHT_PROCESS>` block to explicitly plan its changes and verify guardrails *before* generating any code.
* **Reasoning Audit Log:** Added logic to the main execution loop to parse the agent's internal monologue and save it to `thought.log`. This provides full transparency into the AI's decision-making process and proves autonomous reasoning.* 

## 2026-06-24

### v2.0.1
* **Prompt-Level Security Guardrails:** Added a strict "Security & Code Safety Requirements" section to `prompt.md`. This forces the LLM to preserve existing security validation functions, forbids hardcoding of credentials, and mandates secure Bash practices during self-mutation.
* **Vision Realignment:** Redefined the core project objective towards minimalist recursive self-evolution and autonomous model orchestration in documentation and submission assets.

### v2.0.0
* **Language Translation:** Entire codebase and documentation translated to English to meet Kaggle project guidelines.
* **Version Control:** Replaced custom directory-based backup logic with automated `git commit` functionality for robust state management.
* **Security Guardrails:** Added `check_secrets()` to scan for leaked API keys (OpenAI, Google, AWS) in the generated code before applying it.
* **API Agnosticism:** Integrated support for OpenAI, Google Gemini, and llama.cpp alongside Ollama.
* **Target Flexibility:** Added `--target` flag to allow the agent to refactor external files instead of just itself.

---

## 2026-06-20 (Legacy Versions)

### v1.12.2
* **Improved Progress Bar:** Real-time console output now contains generated token counts, generation speed, and elapsed time.
* **Documentation Update:** Removed completed items from ToDo section.

### v1.12.0
* Added `--no-llm` flag to run without querying Ollama (uses output.out).

### v1.11.0
* Fixed error with file path passing in ShellCheck validator.
* Improved temporary file handling to prevent `/tmp` clutter.
