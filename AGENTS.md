# Repository Guidelines

## Project Structure & Module Organization
- `lib/`: Ruby source (root namespace `DhanScalper`). Key areas: `brokers/`, `balance_providers/`, `indicators/`, `ui/`, `support/`, CLI in `lib/dhan_scalper/cli.rb` and executables in `exe/`.
- `spec/`: RSpec tests (unit, integration under `spec/integration/`).
- `config/`: YAML configs (e.g., `scalper.yml`, `development.yml`).
- `bin/`: Dev helpers (`bin/console`, `bin/dev_setup`, `bin/dev_test`).
- `data/`: Local cache/runtime data.

## Build, Test, and Development Commands
- `bundle exec rake`: Default task (runs specs + RuboCop).
- `bundle exec rspec`: Run the test suite.
- `bundle exec rubocop`: Lint and format checks.
- `bundle exec rake build` / `install`: Build/install the gem locally.
- `./bin/dev_setup`: One-time local setup (.env, deps, data/).
- `bundle exec bin/console`: Interactive console for quick experiments.
- Run locally: `bundle exec exe/dhan_scalper paper -c config/scalper.yml`.

## Coding Style & Naming Conventions
- Ruby 3.2+, 2-space indentation, freeze string literals where used.
- RuboCop configured in `.rubocop.yml` (double-quoted strings). Fix offenses before PRs.
- Files: `snake_case.rb`; Classes/Modules: `CamelCase` under `DhanScalper::...` matching path.
- Keep public API small; prefer service objects (`Support::ApplicationService`).

## Testing Guidelines
- Framework: RSpec with SimpleCov (min coverage 90%).
- Place tests in `spec/` with `*_spec.rb`; mirror directory structure.
- Use WebMock for any HTTP; do not call live APIs in tests.
- Run: `bundle exec rspec` or `bundle exec rake spec`.

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`.
  - Examples: `feat: add paper broker PnL preview`, `fix: correct historical data debug output`.
- Before opening a PR: rebase, ensure `bundle exec rake` passes.
- PRs must include: clear description, rationale, linked issues, screenshots/logs for UI/CLI, and tests for new behavior.

## Security & Configuration Tips
- Do not commit secrets. Use `.env` (see `.env.example`). Required: `CLIENT_ID`, `ACCESS_TOKEN` (see README for more vars).
- Prefer paper mode for demos: `paper`, `dashboard`, `dryrun` commands.
- Configuration lives in `config/`; keep defaults safe and documented.

