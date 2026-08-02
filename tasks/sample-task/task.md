# Sample task: slugify utility

Create `tools/slugify.sh` in this repository (the run worktree): a bash script that converts its first argument to a URL slug and prints it to stdout.

Rules:

- Lowercase everything.
- Replace every run of non-alphanumeric characters with a single `-`.
- Trim leading and trailing `-`.
- An empty or all-punctuation argument prints an empty line and exits 0.
- The script must be executable and pass `shellcheck`.

Examples:

- `Hello, World!` → `hello-world`
- `  Fusion --- Harness v1  ` → `fusion-harness-v1`
- `!!!` → `` (empty line)
