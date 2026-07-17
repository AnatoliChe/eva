# Agent-Evolution (Self-Mutating AI Agent)

## Project Goal
To pioneer recursive self-evolution via a hyper-minimalist, zero-overhead kinetic loop that autonomously refactors its own architecture and dynamically orchestrates, hot-swaps, or spawns the optimal LLM engine to accelerate its path toward autonomous code singularity.

## Project Overview

This script acts as an autonomous Bash-based multi-agent system, designed for the Kaggle 5-Day AI Agents Capstone Project. It can rewrite its own code or target external project files to add features, fix bugs, and optimize logic based on natural language instructions. It supports complex context transmission, including system instructions, codebase state, and documentation.

## Core Features

* **Targeted Refactoring:** Can mutate itself or target external scripts (`--target <path>`).
* **Multi-Provider API Integration:** Supports Ollama, OpenAI, Google Gemini, and llama.cpp via a unified `.env` setup.
* **Git State Management:** Automatically uses local Git for atomic backups and version control, ensuring safe rollbacks if self-mutation fails.
* **Dual-Layer Guardrails (Safety & Alignment):** * *System-Level:* Built-in `check_secrets()` prevents the LLM from accidentally leaking API keys, and `bash -n` validates syntax before any code is applied.
    * *Prompt-Level:* Strict LLM instructions in `prompt.md` prevent the agent from disabling its own security checks or using insecure scripting patterns.
* **Isolated Smoke Testing:** Every generated script must survive a dummy run inside an isolated sandbox (empty temp directory, network-isolated via `unshare` when available, hard timeout) before it is allowed to replace the target.
* **Self-Safe Response Parsing:** Structural tags in the LLM response are matched as exact whole lines by a generic `extract_block()` helper, so the parser can safely process its own source code during self-mutation.
* **Atomic Writes:** Code updates are performed via temporary files to prevent corruption during I/O failures.
* **ShellCheck Integration:** Built-in static analysis integration to ensure generated code meets Bash best practices.
* **Execution Modes:**
    * `--dry-run`: Evaluate changes without writing them to disk.
    * `--no-llm`: Reprocess the last generated response stored in `output.out`.
    * `--api-url <url>`: Override the API endpoint for the chosen provider (self-hosted gateways, proxies, remote Ollama).
    * `--version`: Print the agent version and exit.
* **Resilient API Calls:** All requests go through configurable curl timeouts (`CURL_CONNECT_TIMEOUT`, default 10s; `CURL_MAX_TIME`, default 900s), so a dead endpoint fails fast instead of hanging the loop.
* **Analytics & Stats:** Automatically collects JSON-based metrics (`stats.json`) covering execution time, successful mutations, used models, and providers. The `--stats` flag prints an aggregated report (total runs, success rate, average duration, providers, models).
* **Chain-of-Thought (CoT) Auditing:** EVA does not blindly generate code. It utilizes an internal THOUGHT_PROCESS validation step where it plans changes and verifies its own adherence to guardrails before execution. These cognitive steps are extracted and preserved in thought.log for transparency and human-in-the-loop oversight.

## Technical Requirements

* **Dependencies:** `curl`, `jq`, `git`, `coreutils` (`timeout`); optional: `shellcheck`, `unshare` (util-linux) for network-isolated smoke tests.
* **API Configuration:** For OpenAI or Google models, create a `.env` file in the root directory:
    ```env
    OPENAI_API_KEY="sk-..."
    GOOGLE_API_KEY="AIza..."
    ```

## Usage

Basic self-mutation using local Ollama (default):
`./eva.sh`

Refactor a specific external script using Google Gemini:
`./eva.sh --target /path/to/other_script.sh --provider google --model gemini-1.5-pro`

Run a dry-run test with OpenAI:
`./eva.sh --provider openai --model gpt-4o --dry-run`

## Current Task (ToDo)
- [ ] Support patch/diff-based mutations as an alternative to full-file rewrites, to reduce the risk of truncated generations on large targets.
