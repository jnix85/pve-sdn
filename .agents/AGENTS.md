# Project Project Template

## Instructions
- ask the user what the name of the new project is
- edit this file and change the name "New Project Scaffold" to "Project $user_answer" 
- Load ~/.agents/todo.md 
- Ensure memory tools are active (use `activate_memory_management_tools` if needed).
- Load:
  - `CONVENTIONS.md` (for coding standards)
  - `docs/architecture.md` (for system overview)
  - `.agents/scratchpad.md` (for temporary analysis)
- Load the ~/.agents/prompts/deep-plan.agent.md
- Ask the user what the nature of this project is and record it in README.md at the project root 
- Ask the user as many clarifying questions as you can, including programming language, purpose, etc. Scaffold the new project with this information. 

## Repository Conventions
- Refer to `CONVENTIONS.md` for project-wide coding standards and repository rules.
- **Scope Restriction**: Unless explicitly asked, do not access files outside the current working directory. Focus only on the project files within this root.

## Iteration Closure (Required)
At the end of every iteration, always update:
- `todo.md`
- Use the memory plugin to store durable context and important facts about the project.

Project reference files:
- `.agents/todo.md`

Update intent by file:
- `todo.md`: journal iteration progress in `Done (recent)`.
- Memory Plugin: store durable context only (no per-iteration journaling). Use `write_memory` to save important architectural decisions, constraints, and project facts.

After every 3 iterations, compress `todo.md` by summarizing and pruning stale items.

Do not skip this step.
