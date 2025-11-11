# frozen_string_literal: true

require "json"

module Minitest
  module Promptfoo
    # DSL for building promptfoo assertions in a minitest-like style
    #
    # Example:
    #   builder = AssertionBuilder.new
    #   builder.includes("Hello")
    #   builder.matches(/\d+/)
    #   builder.rubric("Response is professional")
    #   builder.to_promptfoo_assertions
    class AssertionBuilder
      def initialize
        @assertions = []
      end

      # String inclusion check
      def includes(text)
        @assertions << {
          "type" => "contains",
          "value" => text
        }
      end

      # Regex pattern matching
      def matches(pattern)
        @assertions << {
          "type" => "regex",
          "value" => pattern.source
        }
      end

      # Exact equality check
      def equals(expected)
        @assertions << {
          "type" => "equals",
          "value" => expected
        }
      end

      # JSON structure validation using JavaScript
      def json_includes(key:, value:)
        @assertions << {
          "type" => "is-json"
        }
        # Handle both string output (needs parsing) and object output (already parsed)
        @assertions << {
          "type" => "javascript",
          "value" => "(typeof output === 'string' ? JSON.parse(output) : output)[#{key.inspect}] === #{value.to_json}"
        }
      end

      # Custom JavaScript assertion
      def javascript(js_code)
        @assertions << {
          "type" => "javascript",
          "value" => js_code
        }
      end

      # LLM-as-judge rubric evaluation
      def rubric(criteria, threshold: 0.5)
        @assertions << {
          "type" => "llm-rubric",
          "value" => criteria,
          "threshold" => threshold
        }
      end

      # Convert to promptfoo assertion format
      def to_promptfoo_assertions
        @assertions
      end
    end
  end
end
