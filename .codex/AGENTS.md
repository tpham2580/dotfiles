# Agent Instructions for Codex CLI

## DeepSeek Models Critical Instructions

### IF YOU ARE A DEEPSEEK MODEL:

**CRITICAL**: DeepSeek models MUST use the shell function for ALL command execution.

#### Shell Command Execution
- **ALWAYS** use the `shell` function to execute commands
- **NEVER** call commands directly
- Syntax: `shell(cmd=["bash", "-lc", "command"], workdir="path")`

Examples:
- List files: `shell(cmd=["bash", "-lc", "ls -la"], workdir=".")`
- Read file: `shell(cmd=["bash", "-lc", "cat filename"], workdir=".")`
- Search: `shell(cmd=["bash", "-lc", "rg 'pattern'"], workdir=".")`

#### File Operations
- Use provided file operation tools when available (read_file, write_file)
- Otherwise use shell commands through the shell function

### Working Directory
- Always set the `workdir` parameter when using shell function
- Use absolute paths or specify workdir instead of `cd`

### For All Models
- Respect sandbox mode settings
- Follow approval policy
- Handle errors gracefully
