# frozen_string_literal: true

require "minitest/test"
require_relative "assertion_builder"
require_relative "failure_formatter"
require_relative "promptfoo_runner"
require_relative "test_methods"

module Minitest
  module Promptfoo
    # Base class for testing LLM prompts using promptfoo.
    #
    # Recommended Usage (Minitest-like DSL):
    #   class MyPromptTest < Minitest::Promptfoo::Test
    #     # Set provider(s) for ALL tests in this class (DRY!)
    #     # Providers can be strings or hashes with config (see promptfoo docs)
    #     self.providers = [
    #       "openai:gpt-4o-mini",  # Simple string format
    #       {
    #         id: "openai:chat:anthropic:claude-3-7-sonnet",
    #         config: { response_format: { type: "json_object" } }  # With config
    #       }
    #     ]
    #
    #     def prompt_path
    #       "prompts/greeting.ptmpl"  # Or .liquid
    #     end
    #
    #     test "generates professional greeting" do
    #       assert_prompt(vars: { name: "Alice" }) do |response|
    #         response.includes("Hello Alice")
    #         response.matches(/[A-Z]/)  # Starts with capital letter
    #         response.rubric("Response is professional and courteous")
    #       end
    #     end
    #   end
    class Test < Minitest::Test
      include TestMethods
    end
  end
end
