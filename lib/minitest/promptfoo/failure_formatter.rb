# frozen_string_literal: true

require "json"

module Minitest
  module Promptfoo
    # Formats promptfoo test failures into human-readable error messages
    class FailureFormatter
      def initialize(verbose: false)
        @verbose = verbose
      end

      # Main entry point: formats a complete failure message from promptfoo results
      def format_results(passing_providers, failing_providers)
        msg = "Prompt evaluation results:\n"

        passing_providers.each do |provider_id|
          msg += "  ✓ #{provider_id}\n"
        end

        failing_providers.each do |failure|
          msg += "  ✗ #{failure[:id]}\n"
        end

        msg += "\n"

        failing_providers.each do |failure|
          msg += format_provider_failure(failure[:id], failure[:result])
          msg += "\n"
        end

        unless @verbose
          msg += "💡 Tip: Add `verbose: true` to assert_prompt for detailed debugging output\n"
        end

        msg
      end

      private

      def format_provider_failure(provider_id, provider_result)
        output_text = provider_result.dig("response", "output") || provider_result.dig("output")
        error = provider_result.dig("error") || provider_result.dig("response", "error")
        grading_result = provider_result.dig("gradingResult") || {}
        component_results = grading_result.dig("componentResults") || []

        msg = "#{provider_id} FAILED:\n\n"

        msg += format_api_error(error) if error&.length&.positive?
        msg += format_response_output(output_text, error)

        assertion_failures = extract_assertion_failures(component_results)
        msg += format_assertion_failures(assertion_failures, output_text) if assertion_failures.any?

        msg += format_verbose_output(provider_result) if @verbose

        msg
      end

      def format_api_error(error)
        "API Error:\n  #{error}\n\n"
      end

      def format_response_output(output_text, error)
        if output_text && output_text.to_s.length > 0
          formatted_output = output_text.is_a?(String) ? output_text : JSON.pretty_generate(output_text)
          "Response:\n  #{formatted_output.gsub("\n", "\n  ")}\n\n"
        elsif !error || error.length == 0
          "No response received from provider\n\n"
        else
          ""
        end
      end

      def format_assertion_failures(assertion_failures, output_text)
        msg = "Failures:\n"

        # If JSON parsing failed, only show that error (other failures are consequences)
        json_parse_failure = assertion_failures.find { |f| f[:type] == "is-json" }

        if json_parse_failure
          msg += format_assertion_failure(json_parse_failure, output_text)
        else
          assertion_failures.each do |failure|
            msg += format_assertion_failure(failure, output_text)
          end
        end

        msg
      end

      def format_verbose_output(provider_result)
        "\nRaw Provider Result (verbose mode):\n" \
          "  #{JSON.pretty_generate(provider_result).gsub("\n", "\n  ")}\n"
      end

      def extract_assertion_failures(component_results)
        component_results.select { |result| !result.dig("pass") }.map do |result|
          {
            type: result.dig("assertion", "type"),
            value: result.dig("assertion", "value"),
            threshold: result.dig("assertion", "threshold"),
            score: result.dig("score"),
            reason: result.dig("reason"),
            named_scores: result.dig("namedScores")
          }
        end
      end

      def format_assertion_failure(failure, output_text)
        case failure[:type]
        when "llm-rubric"
          format_rubric_failure(failure)
        when "contains"
          "  ✗ includes(#{failure[:value].inspect}) - not found in response\n"
        when "regex"
          "  ✗ matches(/#{failure[:value]}/) - pattern not found\n"
        when "equals"
          "  ✗ equals(#{failure[:value].inspect}) - response does not match\n"
        when "javascript"
          format_javascript_failure(failure, output_text)
        when "is-json"
          format_invalid_json_failure(failure, output_text)
        else
          "  ✗ #{failure[:type]} assertion failed\n"
        end
      end

      def format_javascript_failure(failure, output_text)
        js_code = failure[:value].to_s

        if json_assertion?(js_code)
          parsed = parse_json_assertion(js_code)
          if parsed
            key = parsed[:key]
            expected = parsed[:expected]
            actual_value = extract_json_value(output_text, key.to_s)
            msg = "  ✗ json_includes(key: #{key.inspect})\n"
            msg += "    Expected: #{expected.inspect}\n"
            msg += "    Actual: #{actual_value.inspect}\n"
            return msg
          end
        end

        "  ✗ javascript assertion failed\n"
      end

      def format_invalid_json_failure(failure, output_text)
        msg = "  ✗ response is not valid JSON\n"

        if output_text && output_text.to_s.length > 0
          text = output_text.is_a?(String) ? output_text : JSON.pretty_generate(output_text)
          snippet = (text.length > 100) ? "#{text[0..100]}..." : text
          msg += "    Output: #{snippet.inspect}\n"
        end

        msg
      end

      def format_rubric_failure(failure)
        score = failure[:score] || 0
        threshold = failure[:threshold] || 0.5

        msg = "  ✗ rubric (score: #{score.round(2)}/#{threshold})\n"
        if score >= threshold
          msg += "      Note: Score meets threshold but one or more criteria failed\n"
          msg += "      Promptfoo requires ALL criteria to pass, not just the aggregate score\n"
        end

        if @verbose
          criteria = failure[:value]
          reason = failure[:reason]

          if criteria && criteria.to_s.length > 0
            msg += "\n    Rubric criteria:\n"
            criteria.split("\n").each do |line|
              msg += "      #{line}\n" if line.strip.length > 0
            end
          end

          if reason && reason.to_s.length > 0
            msg += "\n    Judge feedback:\n"
            reason.split("\n").each do |line|
              msg += "      #{line}\n"
            end
          end

          msg += "\n"
        end

        msg
      end

      # JSON assertion helpers

      def json_assertion?(js_code)
        js_code.to_s.match?(/JSON\.parse\(output\)\[/)
      end

      def parse_json_assertion(js_code)
        match = js_code.match(/JSON\.parse\(output\)\[(['"])(.+?)\1\]\s*===\s*(.+)/)
        return nil unless match

        key = match[2]
        expected_json = match[3]

        expected_value = begin
          JSON.parse(expected_json)
        rescue JSON::ParserError
          expected_json
        end

        {key: key, expected: expected_value}
      end

      def extract_json_value(output_text, key)
        return nil unless output_text && output_text.to_s.length > 0

        parsed = output_text.is_a?(String) ? JSON.parse(output_text) : output_text
        parsed[key]
      rescue JSON::ParserError
        nil
      end
    end
  end
end
