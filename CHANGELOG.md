# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - Blinded by the Light

Initial release of minitest-promptfoo:

- Core `Minitest::Promptfoo::Test` class for prompt testing
- Configuration system for promptfoo executable path
- Support for multiple providers
- Assertion DSL: `includes`, `matches`, `equals`, `json_includes`, `javascript`, `rubric`
- Rails integration with automatic prompt file discovery
- Support for both .ptmpl and .liquid prompt formats
- Pre-rendering support for template conflicts
- Debug mode with `DEBUG_PROMPT_TEST` environment variable
- Verbose mode for detailed failure messages
- Comprehensive README with examples
- Basic test coverage

## [0.1.1] - Spirit in the Night

- Fixed bug causing unbound method call in Rails apps

## [0.1.2] - Growin' Up

- Fixed more bugs relating to Rails implementation

## [0.1.3] - Does This Bus Stop at 82nd Street?

- Renamed `Minitest::Promptfoo::RailsTest` to `Minitest::Promptfoo::PromptTest` for clearer semantics

## [0.1.4] - For You

- `force_json!` method to handle JSON responses wrapped in markdown code fences (e.g., ` ```json `)
  - Automatically strips backticks before parsing JSON
  - Skips `is-json` validation when enabled (since raw output isn't valid JSON)
  - Particularly useful for Anthropic and other providers that ignore `response_format` settings
