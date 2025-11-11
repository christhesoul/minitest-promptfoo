# frozen_string_literal: true

require "yaml"
require "json"
require "tmpdir"
require "open3"
require "minitest/test"

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
      class PromptNotFoundError < StandardError; end
      class EvaluationError < StandardError; end

      # DSL for building promptfoo assertions in a minitest-like style
      class AssertionBuilder
        def initialize
          @assertions = []
        end

        # String inclusion check
        def includes(text)
          @assertions << {
            "type" => "contains",
            "value" => text,
          }
        end

        # Regex pattern matching
        def matches(pattern)
          @assertions << {
            "type" => "regex",
            "value" => pattern.source,
          }
        end

        # Exact equality check
        def equals(expected)
          @assertions << {
            "type" => "equals",
            "value" => expected,
          }
        end

        # JSON structure validation using JavaScript
        def json_includes(key:, value:)
          @assertions << {
            "type" => "is-json",
          }
          # Handle both string output (needs parsing) and object output (already parsed)
          @assertions << {
            "type" => "javascript",
            "value" => "(typeof output === 'string' ? JSON.parse(output) : output)[#{key.inspect}] === #{value.to_json}",
          }
        end

        # Custom JavaScript assertion
        def javascript(js_code)
          @assertions << {
            "type" => "javascript",
            "value" => js_code,
          }
        end

        # LLM-as-judge rubric evaluation
        def rubric(criteria, threshold: 0.5)
          @assertions << {
            "type" => "llm-rubric",
            "value" => criteria,
            "threshold" => threshold,
          }
        end

        # Convert to promptfoo assertion format
        def to_promptfoo_assertions
          @assertions
        end
      end

      # Class-level provider configuration (inheritable)
      class << self
        attr_accessor :_providers

        def providers
          @_providers || "echo"
        end

        def providers=(value)
          @_providers = value
        end

        def inherited(subclass)
          super
          subclass._providers = _providers
        end
      end

      def prompt_path
        raise NotImplementedError, "Subclasses must implement #prompt_path"
      end

      def prompt_content
        @prompt_content ||= File.read(prompt_path)
      end

      # Minitest-like DSL for prompt testing
      #
      # Example:
      #   assert_prompt(vars: { input: "test" }) do |response|
      #     response.includes("expected text")
      #     response.matches(/\d{3}-\d{4}/)
      #     response.rubric("Response is professional and courteous")
      #   end
      def assert_prompt(vars:, providers: nil, verbose: false, pre_render: false, &block)
        builder = AssertionBuilder.new
        yield(builder)

        evaluate_prompt(
          prompt_content,
          vars: vars,
          providers: providers,
          assertions: builder.to_promptfoo_assertions,
          verbose: verbose,
          pre_render: pre_render,
        )

        # Satisfy minitest's assertion count requirement
        pass
      end

      def evaluate_prompt(prompt_text, vars:, pre_render:, providers: nil, assertions: [], show_output: false, verbose: false)
        Dir.mktmpdir do |tmpdir|
          config_path = File.join(tmpdir, "promptfooconfig.yaml")
          output_path = File.join(tmpdir, "output.json")

          # Convert single-brace {var} syntax to double-brace {{var}} for promptfoo
          promptfoo_text = prompt_text.gsub(/(?<!\{)\{(\w+)\}(?!\})/, '{{\1}}')

          if pre_render
            vars.each do |key, value|
              promptfoo_text = promptfoo_text.gsub("{{#{key}}}", value.to_s)
            end
            config_vars = {}
          else
            config_vars = vars
          end

          # Use provided provider(s) or fall back to class-level default
          providers_array = wrap_array(providers || self.class.providers)

          config = build_promptfoo_config(
            prompt: promptfoo_text,
            vars: config_vars,
            providers: providers_array,
            assertions: assertions,
            output_path: output_path,
          )

          config_yaml = YAML.dump(config)
          File.write(config_path, config_yaml)

          if ENV["DEBUG_PROMPT_TEST"]
            puts "\n=== Promptfoo Config ===\n"
            puts config_yaml
            puts "\n======================\n"
          end

          result = shell_out_to_promptfoo(config_path, tmpdir, show_output: show_output, pre_render: pre_render)

          if ENV["DEBUG_PROMPT_TEST"]
            puts "\n=== Promptfoo Result ===\n"
            puts result.inspect
            puts "\n======================\n"
          end

          output = parse_promptfoo_output(output_path)

          unless result[:success] || output.any?
            error_msg = "promptfoo evaluation failed\n"
            error_msg += "STDOUT: #{result[:stdout]}\n" if result[:stdout]&.length&.positive?
            error_msg += "STDERR: #{result[:stderr]}\n" if result[:stderr]&.length&.positive?
            raise EvaluationError, error_msg
          end

          check_provider_failures(output, providers_array, verbose: verbose) if assertions.any?

          output
        end
      end

      private

      # Simple array wrapper (replaces ActiveSupport's Array.wrap)
      def wrap_array(object)
        if object.nil?
          []
        elsif object.respond_to?(:to_ary)
          object.to_ary || [object]
        else
          [object]
        end
      end

      # Simple deep stringify keys (replaces ActiveSupport method)
      def deep_stringify_keys(hash)
        hash.each_with_object({}) do |(key, value), result|
          new_key = key.to_s
          new_value = case value
                      when Hash
                        deep_stringify_keys(value)
                      when Array
                        value.map { |v| v.is_a?(Hash) ? deep_stringify_keys(v) : v }
                      else
                        value
                      end
          result[new_key] = new_value
        end
      end

      def check_provider_failures(output, providers, verbose: false)
        results = output.dig("results", "results") || []
        passing_providers = []
        failing_providers = []

        results.each do |provider_result|
          provider_id = provider_result.dig("provider", "id")
          success = provider_result.dig("success")

          if success
            passing_providers << provider_id
          else
            failing_providers << {
              id: provider_id,
              result: provider_result,
            }
          end
        end

        if failing_providers.any?
          error_msg = build_failure_message(passing_providers, failing_providers, verbose: verbose)
          flunk(error_msg)
        end
      end

      def build_failure_message(passing_providers, failing_providers, verbose: false)
        msg = "Prompt evaluation results:\n"

        passing_providers.each do |provider_id|
          msg += "  ✓ #{provider_id}\n"
        end

        failing_providers.each do |failure|
          msg += "  ✗ #{failure[:id]}\n"
        end

        msg += "\n"

        failing_providers.each do |failure|
          msg += format_provider_failure(failure[:id], failure[:result], verbose: verbose)
          msg += "\n"
        end

        unless verbose
          msg += "💡 Tip: Add `verbose: true` to assert_prompt for detailed debugging output\n"
        end

        msg
      end

      def format_provider_failure(provider_id, provider_result, verbose: false)
        output_text = provider_result.dig("response", "output") || provider_result.dig("output")
        error = provider_result.dig("error") || provider_result.dig("response", "error")
        grading_result = provider_result.dig("gradingResult") || {}
        component_results = grading_result.dig("componentResults") || []

        msg = "#{provider_id} FAILED:\n\n"

        if error&.length&.positive?
          msg += "API Error:\n"
          msg += "  #{error}\n\n"
        end

        if output_text && output_text.to_s.length > 0
          msg += "Response:\n"
          formatted_output = output_text.is_a?(String) ? output_text : JSON.pretty_generate(output_text)
          msg += "  #{formatted_output.gsub("\n", "\n  ")}\n\n"
        elsif !error || error.length == 0
          msg += "No response received from provider\n\n"
        end

        assertion_failures = extract_assertion_failures(component_results)

        if assertion_failures.any?
          msg += "Failures:\n"

          json_parse_failure = assertion_failures.find { |f| f[:type] == "is-json" }

          if json_parse_failure
            msg += format_assertion_failure(json_parse_failure, output_text, verbose: verbose)
          else
            assertion_failures.each do |failure|
              msg += format_assertion_failure(failure, output_text, verbose: verbose)
            end
          end
        end

        if verbose
          msg += "\nRaw Provider Result (verbose mode):\n"
          msg += "  #{JSON.pretty_generate(provider_result).gsub("\n", "\n  ")}\n"
        end

        msg
      end

      def extract_assertion_failures(component_results)
        component_results.select { |result| !result.dig("pass") }.map do |result|
          {
            type: result.dig("assertion", "type"),
            value: result.dig("assertion", "value"),
            threshold: result.dig("assertion", "threshold"),
            score: result.dig("score"),
            reason: result.dig("reason"),
            named_scores: result.dig("namedScores"),
          }
        end
      end

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

        { key: key, expected: expected_value }
      end

      def extract_json_value(output_text, key)
        return nil unless output_text && output_text.to_s.length > 0

        parsed = output_text.is_a?(String) ? JSON.parse(output_text) : output_text
        parsed[key]
      rescue JSON::ParserError
        nil
      end

      def format_assertion_failure(failure, output_text, verbose: false)
        case failure[:type]
        when "llm-rubric"
          format_rubric_failure(failure, verbose: verbose)
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
          snippet = text.length > 100 ? "#{text[0..100]}..." : text
          msg += "    Output: #{snippet.inspect}\n"
        end

        msg
      end

      def format_rubric_failure(failure, verbose: false)
        score = failure[:score] || 0
        threshold = failure[:threshold] || 0.5

        if score >= threshold
          msg = "  ✗ rubric (score: #{score.round(2)}/#{threshold})\n"
          msg += "      Note: Score meets threshold but one or more criteria failed\n"
          msg += "      Promptfoo requires ALL criteria to pass, not just the aggregate score\n"
        else
          msg = "  ✗ rubric (score: #{score.round(2)}/#{threshold})\n"
        end

        if verbose
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

      def build_promptfoo_config(prompt:, vars:, providers:, assertions:, output_path:)
        normalized_providers = providers.map do |provider|
          case provider
          when String
            provider
          when Hash
            deep_stringify_keys(provider)
          end
        end

        {
          "prompts" => [prompt],
          "providers" => normalized_providers,
          "tests" => [
            {
              "vars" => vars.transform_keys(&:to_s),
              "assert" => assertions,
            },
          ],
          "outputPath" => output_path,
        }
      end

      def shell_out_to_promptfoo(config_path, working_dir, pre_render:, show_output: false)
        promptfoo_cmd = Minitest::Promptfoo.configuration.resolve_executable

        env_vars = {}
        env_vars["PROMPTFOO_DISABLE_TEMPLATING"] = "true" if pre_render

        # Handle both "npx promptfoo" and direct path
        if promptfoo_cmd.start_with?("npx")
          cmd_parts = promptfoo_cmd.split
          cmd = cmd_parts + ["eval", "-c", config_path, "--no-cache"]
        else
          cmd = [promptfoo_cmd, "eval", "-c", config_path, "--no-cache"]
        end

        if show_output
          system(
            env_vars,
            *cmd,
            chdir: working_dir,
          )
          status = $?

          {
            success: status.success?,
            stdout: "",
            stderr: "",
          }
        else
          stdout, stderr, status = Open3.capture3(
            env_vars,
            *cmd,
            chdir: working_dir,
          )

          {
            success: status.success?,
            stdout: stdout,
            stderr: stderr,
          }
        end
      end

      def parse_promptfoo_output(output_path)
        return {} unless File.exist?(output_path)

        JSON.parse(File.read(output_path))
      end
    end
  end
end
