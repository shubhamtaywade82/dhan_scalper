# Repository Guidelines

## Project Structure & Module Organization
- `lib/`: Ruby source under `DhanScalper::...`. Key areas: `brokers/`, `balance_providers/`, `indicators/`, `ui/`, `support/`. CLI entry: `lib/dhan_scalper/cli.rb`; executables in `exe/`.
- `spec/`: RSpec tests. Unit specs mirror `lib/`; integration specs in `spec/integration/`.
- `config/`: YAML configs (e.g., `scalper.yml`, `development.yml`).
- `bin/`: Dev helpers (`bin/console`, `bin/dev_setup`, `bin/dev_test`).
- `data/`: Local cache/runtime data (safe to purge when troubleshooting).

## Build, Test, and Development Commands
- `bundle exec rake`: Default task; runs RSpec and RuboCop.
- `bundle exec rspec`: Run the full test suite.
- `bundle exec rubocop`: Lint/style checks (see `.rubocop.yml`).
- `bundle exec rake build` / `install`: Build/install the gem locally.
- `./bin/dev_setup`: One‑time local setup (`.env`, deps, `data/`).
- `bundle exec bin/console`: Interactive console for experiments.
- Run locally: `bundle exec exe/dhan_scalper paper -c config/scalper.yml`.

## Coding Style & Naming Conventions
- Ruby 3.2+, 2‑space indentation, double‑quoted strings; freeze string literals where used.
- Files: `snake_case.rb`; Classes/Modules: `CamelCase` under `DhanScalper::...` matching path.
- Keep public API small; prefer service objects inheriting `Support::ApplicationService`.

## Testing Guidelines
- Framework: RSpec with SimpleCov (minimum coverage 90%).
- Name tests `*_spec.rb`; mirror directory structure. Place integration specs in `spec/integration/`.
- Use WebMock for any HTTP; do not call live APIs in tests.
- Run: `bundle exec rspec` or `bundle exec rake spec`.

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:` (e.g., `feat: add paper broker PnL preview`).
- Before PR: rebase, ensure `bundle exec rake` passes, and lint is clean.
- PRs must include a clear description, rationale, linked issues, screenshots/logs for UI/CLI, and tests for new behavior.

## Security & Configuration Tips
- Never commit secrets. Use `.env` (see `.env.example`). Required: `CLIENT_ID`, `ACCESS_TOKEN` (see README for more).
- Prefer safe modes for demos: `paper`, `dashboard`, `dryrun`.
- Keep configs in `config/`; defaults should be safe and documented.

