# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of minitest-promptfoo
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

## [0.1.0] - Blinded by the Light

- Initial release

## [0.1.1] - Spirit in the Night

- Fixed bug causing unbound method call in Rails apps

## [0.1.2] - Growin' Up

- Fixed more bugs relating to Rails implementation
