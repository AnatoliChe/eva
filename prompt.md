Analyze the provided context (Target Script, Readme, Changes).
Your task:
1. Analyze the current state of the code.
2. Implement requested tasks from the ToDo list (if any).
3. Refactor the code for better performance, error handling, and readability.
4. Generate a concise list of changes for the current version (do not rewrite the whole history).

CRITICAL SECURITY & CODE SAFETY REQUIREMENTS (GUARDRAILS):
- NEVER hardcode any API keys, access tokens, passwords, or sensitive credentials. All configurations must strictly rely on environment variables or `.env` files.
- PRESERVE GUARDRAILS: You are strictly forbidden from removing, bypassing, or weakening existing security features in the target script, especially secret scanners (like `check_secrets`), or syntax validation blocks (`bash -n`, `shellcheck`). Any optimization must maintain or enhance these protections.
- SECURE BASH PRACTICES: Avoid dangerous patterns (e.g., unvalidated `eval`, insecure temporary file creation). Always double-quote variables to prevent word splitting and code injection vulnerabilities.
- FAIL-SAFE EXECUTION: Ensure that generated logic includes proper error trapping (`set -euo pipefail`) and clean exit codes so the autonomous loop does not break unexpectedly.
- HTML ENTITIES: When using `sed` or `awk`, preserve HTML entities (e.g., `&amp;`). Work with code as raw text.


OUTPUT FORMAT CONSTRAINTS:
- You must act as a reasoning agent. Before writing any code, you MUST output a <THOUGHT_PROCESS> block where you step-by-step analyze the problem, list the planned changes, and explicitly confirm how you will adhere to the Guardrails.
- Do NOT use markdown code blocks (e.g., ```bash) inside the XML tags.
- Do NOT use the structural tags as plain text inside your content.

Return the result strictly in the following XML format:
<THOUGHT_PROCESS>
YOUR REASONING, ANALYSIS, AND PLANNING HERE
</THOUGHT_PROCESS>
<README>
UPDATED README CONTENT HERE
</README>
<SCRIPT>
UPDATED SCRIPT CODE HERE
</SCRIPT>
<CHANGES>
UPDATED CHANGELOG HERE
</CHANGES>
