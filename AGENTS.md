# Instructions

You are an expert Ruby developer specializing in creating clean, maintainable, and well-tested Ruby gems and libraries.

## Technology Stack

- **Language:** Ruby
- **Autoloading:** Zeitwerk
- **Linting:** StandardRB
- **Git Hooks:** Lefthook
- **Containerization:** Docker

## Docker Environment

This project is fully containerized. **ALWAYS** run commands through the Docker environment using `dockerized.sh`.

### Setup

Source the dockerized script to set up aliases:

```bash
source dockerized.sh
```

### Available Aliases

After sourcing, these commands run inside Docker:
- `ruby` - Ruby interpreter
- `bundle` - Bundler
- `rake` - Rake tasks
- `standardrb` - Ruby linter (StandardRB)
- `lefthook` - Git hooks manager

### Running Commands

Always use the dockerized environment:

```bash
# Set up aliases first
source dockerized.sh

# Then run commands
rake test
standardrb --fix
lefthook run pre-commit
```

## Project Structure

This is a Ruby gem with the following structure:

```
ruby_base/
├── lib/
│   ├── base_projects.rb          # Main entry point
│   └── base_projects/
│       └── version.rb            # Version constant
├── bin/
│   └── cli                       # CLI executable
├── Gemfile                       # Dependencies
├── compose.yaml                  # Docker Compose config
├── dockerized.sh                 # Docker aliases setup
├── lefthook.yml                  # Git hooks configuration
└── .rubocop.yml                  # StandardRB configuration
```

### Key Files

- **lib/base_projects.rb** - Main module, uses Zeitwerk for autoloading
- **lib/base_projects/version.rb** - Version constant
- **bin/cli** - CLI entry point
- **lefthook.yml** - Pre-commit hooks (StandardRB)

## Code Style

### Naming Conventions
- Use `snake_case` for file names, method names, and variables
- Use `CamelCase` for class and module names
- Follow Ruby naming conventions: methods ending with `?` for predicates, `!` for dangerous operations

### Clean Code Guidelines

#### Constants Over Magic Numbers
- Replace hard-coded values with named constants
- Use descriptive constant names that explain the value's purpose
- Keep constants at the top of the file or in a dedicated constants file

#### Meaningful Names
- Variables, functions, and classes should reveal their purpose
- Names should explain why something exists and how it's used
- Avoid abbreviations unless they're universally understood

#### Smart Comments
- Don't comment on what the code does - make the code self-documenting
- Use comments to explain why something is done a certain way
- Document APIs, complex algorithms, and non-obvious side effects

#### Single Responsibility
- Each function should do exactly one thing
- Functions should be small and focused
- If a function needs a comment to explain what it does, it should be split



## Ruby & Zeitwerk Conventions

This project uses **Zeitwerk** for autoloading. You MUST strictly follow its conventions to avoid `NameError` or loading issues.

### 1. File Structure = Module Structure
The directory and file names MUST match the constant paths exactly, including **plurality**, some examples:
- `lib/base_projects/client.rb` ⮕ `module BaseProjects; class Client; end; end`
- `lib/base_projects/errors.rb` ⮕ `module BaseProjects; module Errors; end; end` (Note: `errors.rb` must define `Errors`, not just `Error`)
- `lib/base_projects/web_parser.rb` ⮕ `module BaseProjects; class WebParser; end; end` (snake_case to CamelCase)

### 2. Explicit Nesting
NEVER use the shorthand `class BaseProjects::Client`. Always use explicit nesting to ensure modules are correctly defined and Zeitwerk can track them. This is especially important for files that define a new namespace:
```ruby
# GOOD
module BaseProjects
  module Errors
    class APIError < StandardError; end
  end
end

# BAD (Zeitwerk will fail to find BaseProjects::Errors if not already loaded)
class BaseProjects::Errors::APIError < StandardError; end
```

### 3. No `require` for Internal Files
Do NOT use `require` or `require_relative` for files inside `lib/`. Zeitwerk handles this automatically. Only `require` external gems at the top of the specific file if they are only used there.

### 4. Multi-class Files (The `errors.rb` Rule)
If a file contains multiple classes or constants, they **MUST** be wrapped in a module or class that matches the filename exactly.
- **Example:** `lib/base_projects/errors.rb` MUST define `module BaseProjects; module Errors; ... end; end`.
- **Reason:** Zeitwerk expects `lib/base_projects/errors.rb` to define the constant `BaseProjects::Errors`. If you define classes like `BaseProjects::Error` directly in that file without the `Errors` wrapper, Zeitwerk will not find them and will complain that the expected constant `BaseProjects::Errors` was not defined.


## Linting with StandardRB

This project uses **StandardRB** (not RuboCop) for consistent Ruby code style.

### Commands

```bash
# Check style
source dockerized.sh && standardrb

# Auto-fix issues
source dockerized.sh && standardrb --fix
```

### Pre-commit Hooks

StandardRB runs automatically on pre-commit via Lefthook. No manual intervention needed.

## Git Hooks with Lefthook

Lefthook manages Git hooks to ensure code quality before commits.

### Current Hooks

- **pre-commit:** Runs StandardRB with auto-fix on staged Ruby files

### Manual Execution

```bash
source dockerized.sh && lefthook run pre-commit
```

## Testing Guidelines

### Test Structure
- Write tests before fixing bugs
- Keep tests readable and maintainable
- Test edge cases and error conditions
- One assertion concept per example; refactor relentlessly

### Best Practices
- Follow TDD/BDD practices where applicable
- Don't test private methods - test behavior through public APIs
- Test only your business logic, not framework functionality
- Keep tests short and concise
- Group related tests in `context` blocks with clear descriptions

### What to Assert
- Return values and state changes
- Side effects (file operations, external calls)
- Error conditions and exceptions

## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `docs/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests - then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Write plan to `docs/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `docs/todo.md`
6. **Capture Lessons**: Update `docs/lessons.md` after corrections

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
