# frozen_string_literal: true

require "test_helper"

module Minitest
  module Promptfoo
    class TestFailureFormatter < Minitest::Test
      def setup
        @formatter = FailureFormatter.new(verbose: false)
        @verbose_formatter = FailureFormatter.new(verbose: true)
      end

      # Top-level formatting

      def test_formats_passing_and_failing_providers
        passing = ["provider-1"]
        failing = [{id: "provider-2", result: {}}]

        output = @formatter.format_results(passing, failing)

        assert_match(/✓ provider-1/, output)
        assert_match(/✗ provider-2/, output)
      end

      def test_includes_verbose_tip_when_not_verbose
        output = @formatter.format_results([], [{id: "test", result: {}}])

        assert_match(/verbose: true/, output)
      end

      def test_excludes_verbose_tip_when_verbose
        output = @verbose_formatter.format_results([], [{id: "test", result: {}}])

        refute_match(/verbose: true/, output)
      end

      # Assertion formatting

      def test_formats_contains_assertion_failure
        failure = {type: "contains", value: "expected text"}
        formatter = FailureFormatter.new

        output = formatter.send(:format_assertion_failure, failure, "some output")

        assert_match(/includes\("expected text"\)/, output)
        assert_match(/not found in response/, output)
      end

      def test_formats_regex_assertion_failure
        failure = {type: "regex", value: "\\d+"}
        formatter = FailureFormatter.new

        output = formatter.send(:format_assertion_failure, failure, "text")

        assert_match(%r{matches\(/\\d\+/\)}, output)
        assert_match(/pattern not found/, output)
      end

      def test_formats_equals_assertion_failure
        failure = {type: "equals", value: "exact"}
        formatter = FailureFormatter.new

        output = formatter.send(:format_assertion_failure, failure, "wrong")

        assert_match(/equals\("exact"\)/, output)
        assert_match(/does not match/, output)
      end

      def test_formats_invalid_json_failure
        failure = {type: "is-json"}
        formatter = FailureFormatter.new

        output = formatter.send(:format_assertion_failure, failure, "not json")

        assert_match(/not valid JSON/, output)
      end

      def test_formats_rubric_failure_below_threshold
        failure = {type: "llm-rubric", score: 0.3, threshold: 0.5, value: "Be nice"}
        formatter = FailureFormatter.new

        output = formatter.send(:format_assertion_failure, failure, "")

        assert_match(/rubric \(score: 0.3\/0.5\)/, output)
      end

      def test_formats_rubric_failure_above_threshold_with_note
        failure = {type: "llm-rubric", score: 0.6, threshold: 0.5}
        formatter = FailureFormatter.new

        output = formatter.send(:format_assertion_failure, failure, "")

        assert_match(/Score meets threshold/, output)
        assert_match(/ALL criteria to pass/, output)
      end

      def test_includes_rubric_details_in_verbose_mode
        failure = {
          type: "llm-rubric",
          score: 0.3,
          threshold: 0.5,
          value: "Be professional",
          reason: "Response was too casual"
        }

        output = @verbose_formatter.send(:format_assertion_failure, failure, "")

        assert_match(/Be professional/, output)
        assert_match(/too casual/, output)
      end

      # JSON assertion formatting

      def test_formats_json_includes_failure
        failure = {
          type: "javascript",
          value: "JSON.parse(output)[\"status\"] === \"success\""
        }
        output_text = '{"status":"failed"}'
        formatter = FailureFormatter.new

        result = formatter.send(:format_assertion_failure, failure, output_text)

        assert_match(/json_includes\(key: "status"\)/, result)
        assert_match(/Expected: "success"/, result)
        assert_match(/Actual: "failed"/, result)
      end

      def test_extracts_json_value_from_string
        formatter = FailureFormatter.new
        json_string = '{"key":"value"}'

        result = formatter.send(:extract_json_value, json_string, "key")

        assert_equal("value", result)
      end

      def test_extracts_json_value_from_hash
        formatter = FailureFormatter.new
        json_hash = {"key" => "value"}

        result = formatter.send(:extract_json_value, json_hash, "key")

        assert_equal("value", result)
      end

      def test_returns_nil_for_invalid_json
        formatter = FailureFormatter.new

        result = formatter.send(:extract_json_value, "not json", "key")

        assert_nil(result)
      end

      # Provider failure formatting

      def test_formats_api_error
        formatter = FailureFormatter.new
        error = "Rate limit exceeded"

        output = formatter.send(:format_api_error, error)

        assert_match(/API Error:/, output)
        assert_match(/Rate limit exceeded/, output)
      end

      def test_formats_response_output_with_string
        formatter = FailureFormatter.new
        output_text = "Hello world"

        result = formatter.send(:format_response_output, output_text, nil)

        assert_match(/Response:/, result)
        assert_match(/Hello world/, result)
      end

      def test_formats_response_output_with_hash
        formatter = FailureFormatter.new
        output_text = {"message" => "test"}

        result = formatter.send(:format_response_output, output_text, nil)

        assert_match(/Response:/, result)
        assert_match(/"message": "test"/, result)
      end

      def test_formats_no_response_message
        formatter = FailureFormatter.new

        result = formatter.send(:format_response_output, nil, nil)

        assert_match(/No response received/, result)
      end
    end
  end
end
