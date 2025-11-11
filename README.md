# Minitest::Promptfoo

A thin Minitest wrapper around [promptfoo](https://www.promptfoo.dev/) that brings prompt testing to Ruby projects. Test your LLM prompts with a familiar Minitest-like DSL, supporting multiple providers and assertion types.

## Why Test Your Prompts?

LLM outputs are non-deterministic, but that doesn't mean you can't test them. With minitest-promptfoo, you can:

- Ensure prompts produce expected types of responses
- Validate JSON structure in responses
- Use LLM-as-judge for qualitative evaluation
- Test against multiple providers simultaneously
- Catch prompt regressions before they hit production

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'minitest-promptfoo'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install minitest-promptfoo
```

### Promptfoo Setup

You'll need promptfoo installed. You can either:

1. Install it locally via npm:
```bash
npm install -D promptfoo
```

2. Or use npx (no installation required):
```bash
# The gem will automatically fall back to `npx promptfoo`
```

## Basic Usage

### Plain Ruby Projects

```ruby
require 'minitest/autorun'
require 'minitest/promptfoo'

class GreetingPromptTest < Minitest::Promptfoo::Test
  # Set provider(s) for all tests in this class
  self.providers = "openai:gpt-4o-mini"

  def prompt_path
    "prompts/greeting.ptmpl"  # Or .liquid
  end

  def test_generates_professional_greeting
    assert_prompt(vars: { name: "Alice" }) do |response|
      response.includes("Hello Alice")
      response.matches(/[A-Z]/)  # Starts with capital
      response.rubric("Response is professional and courteous")
    end
  end

  def test_validates_json_structure
    assert_prompt(vars: { format: "json" }) do |response|
      response.json_includes(key: "greeting", value: "Hello")
      response.json_includes(key: "sentiment", value: "positive")
    end
  end
end
```

### Rails Projects

In Rails, the gem automatically discovers prompt files based on test file paths:

```ruby
# test/services/greeting_service_test.rb
class GreetingServiceTest < Minitest::Promptfoo::RailsTest
  self.providers = "openai:gpt-4o-mini"

  # Automatically finds app/services/greeting_service.ptmpl
  # No need to define prompt_path!

  def test_greeting_is_friendly
    assert_prompt(vars: { name: "Bob" }) do |response|
      response.includes("Hello Bob")
      response.rubric("Greeting is warm and welcoming", threshold: 0.7)
    end
  end
end
```

## Configuration

Configure the gem in your test helper or setup file:

```ruby
# test/test_helper.rb
require 'minitest/promptfoo'

Minitest::Promptfoo.configure do |config|
  # Optional: specify custom promptfoo executable path
  config.promptfoo_executable = "./node_modules/.bin/promptfoo"

  # Optional: set root path for resolving prompt files
  config.root_path = Rails.root # or Dir.pwd
end
```

## Assertion Types

### String Matching

```ruby
assert_prompt(vars: { topic: "weather" }) do |response|
  # Contains substring
  response.includes("sunny")

  # Matches regex
  response.matches(/\d+°[CF]/)

  # Exact equality
  response.equals("It's a beautiful day!")
end
```

### JSON Validation

```ruby
assert_prompt(vars: { query: "status" }) do |response|
  response.json_includes(key: "status", value: "success")
  response.json_includes(key: "code", value: 200)
end
```

### Custom JavaScript

```ruby
assert_prompt(vars: { count: 5 }) do |response|
  response.javascript("parseInt(output) > 3")
  response.javascript("output.split(' ').length <= 10")
end
```

### LLM-as-Judge

```ruby
assert_prompt(vars: { tone: "professional" }) do |response|
  response.rubric("Response is professional and courteous")
  response.rubric("Uses business-appropriate language", threshold: 0.8)
end
```

## Multiple Providers

Test your prompt across multiple providers:

```ruby
class MultiProviderTest < Minitest::Promptfoo::Test
  self.providers = [
    "openai:gpt-4o-mini",
    "openai:chat:anthropic:claude-3-7-sonnet",
    "openai:chat:google:gemini-2.0-flash"
  ]

  def prompt_path
    "prompts/greeting.ptmpl"
  end

  def test_works_across_providers
    assert_prompt(vars: { name: "Alice" }) do |response|
      response.includes("Alice")
    end
  end
end
```

## Provider Configuration

Pass custom configuration to providers:

```ruby
def test_json_response_format
  json_provider = {
    id: "openai:gpt-4o-mini",
    config: {
      response_format: { type: "json_object" },
      temperature: 0.7
    }
  }

  assert_prompt(vars: { input: "data" }, providers: json_provider) do |response|
    response.json_includes(key: "result", value: "success")
  end
end
```

## Prompt File Formats

### Promptfoo Templates (.ptmpl)

Use double-brace syntax for variables:

```
You are a helpful assistant.

Greet the user named {{name}} in a {{tone}} manner.
```

### Liquid Templates (.liquid)

Standard Liquid syntax (converted internally):

```
You are a helpful assistant.

Greet the user named {name} in a {tone} manner.
```

## Pre-rendering Templates

If your prompt contains syntax that conflicts with promptfoo's templating (like analyzing Liquid code), pre-render it:

```ruby
def test_liquid_code_analysis
  assert_prompt(
    vars: { code: "{{user.name | upcase}}" },
    pre_render: true
  ) do |response|
    response.includes("variable interpolation")
  end
end
```

## Debugging

Enable debug output to see the generated promptfoo config:

```bash
DEBUG_PROMPT_TEST=1 bundle exec rake test
```

Or enable verbose mode for detailed failure messages:

```ruby
assert_prompt(vars: { name: "Alice" }, verbose: true) do |response|
  response.rubric("Be friendly")
end
```

## Real-World Example

```ruby
class CustomerSupportPromptTest < Minitest::Promptfoo::Test
  self.providers = "openai:gpt-4o-mini"

  def prompt_path
    "prompts/customer_support.ptmpl"
  end

  def test_handles_refund_request_professionally
    assert_prompt(vars: {
      issue: "item arrived damaged",
      customer_name: "Jane Doe"
    }) do |response|
      response.includes("Jane")
      response.rubric("Acknowledges the issue empathetically")
      response.rubric("Offers clear next steps")
      response.rubric("Maintains professional tone")
      response.matches(/refund|replacement/i)
    end
  end

  def test_escalates_complex_issues
    assert_prompt(vars: {
      issue: "legal complaint about data breach",
      customer_name: "John Smith"
    }) do |response|
      response.rubric("Recognizes this requires escalation")
      response.rubric("Does not make promises outside of AI's authority")
      response.includes("escalate")
    end
  end
end
```

## Differences from ActiveSupport::TestCase

When using `Minitest::Promptfoo::Test` (non-Rails), note these differences:

- No fixtures or setup helpers from Rails
- Must explicitly define `prompt_path`
- No automatic database transaction rollbacks
- Uses plain Minitest assertions

For Rails projects, use `Minitest::Promptfoo::RailsTest` to get all Rails testing features plus automatic prompt discovery.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/christhesoul/minitest-promptfoo.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Credits

Built with love on top of:
- [promptfoo](https://www.promptfoo.dev/) - The excellent prompt testing framework
- [minitest](https://github.com/minitest/minitest) - Ruby's favorite testing library
