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
* **Atomic Writes:** Code updates are performed via temporary files to prevent corruption during I/O failures.
* **ShellCheck Integration:** Built-in static analysis integration to ensure generated code meets Bash best practices.
* **Execution Modes:**
    * `--dry-run`: Evaluate changes without writing them to disk.
    * `--no-llm`: Reprocess the last generated response stored in `output.out`.
* **Analytics & Stats:** Automatically collects JSON-based metrics (`stats.json`) covering execution time, successful mutations, used models, and providers.
* ** Chain-of-Thought (CoT) Auditing: EVA does not blindly generate code. It utilizes an internal <THOUGHT_PROCESS> validation step where it plans changes and verifies its own adherence to guardrails before execution. These cognitive steps are extracted and preserved in thought.log for transparency and human-in-the-loop oversight.

## Technical Requirements

* **Dependencies:** `curl`, `jq`, `git`.
* **API Configuration:** For OpenAI or Google models, create a `.env` file in the root directory:
    ```env
    OPENAI_API_KEY="sk-..."
    GOOGLE_API_KEY="AIza..."
    ```

## Usage

Basic self-mutation using local Ollama (default):
`./gen.sh`

Refactor a specific external script using Google Gemini:
`./gen.sh --target /path/to/other_script.sh --provider google --model gemini-1.5-pro`

Run a dry-run test with OpenAI:
`./gen.sh --provider openai --model gpt-4o --dry-run`

## Current Task (ToDo)
- [ ] Expand Guardrails to include automated testing (e.g., executing a dummy run of the target script in an isolated namespace).
