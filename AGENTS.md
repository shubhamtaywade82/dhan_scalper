# Repository Guidelines

## Project Structure & Module Organization
- Source: `lib/` under `DhanScalper::...` (e.g., `brokers/`, `balance_providers/`, `indicators/`, `ui/`, `support/`).
- CLI entry: `lib/dhan_scalper/cli.rb`; executables in `exe/`.
- Tests: `spec/` mirrors `lib/`; integration in `spec/integration/`.
- Config: YAML in `config/` (e.g., `scalper.yml`, `development.yml`).
- Dev helpers: `bin/` (`bin/console`, `bin/dev_setup`, `bin/dev_test`).
- Runtime cache: `data/` (safe to purge when troubleshooting).

## Build, Test, and Development Commands
- `bundle exec rake`: Default task; runs RSpec and RuboCop.
- `bundle exec rspec`: Run the full test suite.
- `bundle exec rubocop`: Lint/style checks per `.rubocop.yml`.
- `bundle exec rake build` / `install`: Build/install the gem locally.
- `./bin/dev_setup`: One‑time local setup (`.env`, deps, `data/`).
- `bundle exec bin/console`: Interactive console.
- Run locally: `bundle exec exe/dhan_scalper paper -c config/scalper.yml`.

## Coding Style & Naming Conventions
- Ruby 3.2+, 2‑space indent, double‑quoted strings; freeze string literals where used.
- Files: `snake_case.rb`; Classes/Modules: `CamelCase` under `DhanScalper::...` matching path.
- Keep public API small; prefer service objects inheriting `Support::ApplicationService`.

## Testing Guidelines
- Framework: RSpec + SimpleCov (min coverage 90%).
- Naming: `*_spec.rb`; mirror `lib/` structure; integration under `spec/integration/`.
- HTTP: Use WebMock; do not call live APIs in tests.
- Run: `bundle exec rspec` or `bundle exec rake spec`.

## Commit & Pull Request Guidelines
- Commits: Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`). Example: `feat: add paper broker PnL preview`.
- Before PR: rebase; ensure `bundle exec rake` passes and lint is clean.
- PRs: clear description, rationale, linked issues, and screenshots/logs for CLI/UI; include tests for new behavior.

## Security & Configuration Tips
- Never commit secrets. Use `.env` (see `.env.example`). Required: `CLIENT_ID`, `ACCESS_TOKEN`.
- Prefer safe modes for demos: `paper`, `dashboard`, `dryrun`.
- Keep configs in `config/`; defaults should be safe and documented.

