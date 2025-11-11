# frozen_string_literal: true

# Example usage of minitest-promptfoo
#
# To run this example:
# 1. Create a prompt file at examples/greeting.ptmpl
# 2. Run: ruby examples/simple_prompt_test.rb

require "bundler/setup"
require "minitest/autorun"
require "minitest/promptfoo"

class SimplePromptTest < Minitest::Promptfoo::Test
  # Use the echo provider for testing (doesn't call actual LLMs)
  self.providers = "echo"

  def prompt_path
    File.join(__dir__, "greeting.ptmpl")
  end

  def test_prompt_includes_name
    assert_prompt(vars: { name: "Alice", tone: "friendly" }) do |response|
      response.includes("Alice")
      response.includes("friendly")
    end
  end

  def test_prompt_with_different_tone
    assert_prompt(vars: { name: "Bob", tone: "professional" }) do |response|
      response.includes("Bob")
      response.includes("professional")
    end
  end
end
