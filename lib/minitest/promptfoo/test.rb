# frozen_string_literal: true

require "yaml"
require "json"
require "tmpdir"
require "open3"
require "minitest/test"
require_relative "assertion_builder"
require_relative "failure_formatter"

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
          pre_render: pre_render
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
            output_path: output_path
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
              result: provider_result
            }
          end
        end

        if failing_providers.any?
          formatter = FailureFormatter.new(verbose: verbose)
          error_msg = formatter.format_results(passing_providers, failing_providers)
          flunk(error_msg)
        end
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
              "assert" => assertions
            }
          ],
          "outputPath" => output_path
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
            chdir: working_dir
          )
          status = $?

          {
            success: status.success?,
            stdout: "",
            stderr: ""
          }
        else
          stdout, stderr, status = Open3.capture3(
            env_vars,
            *cmd,
            chdir: working_dir
          )

          {
            success: status.success?,
            stdout: stdout,
            stderr: stderr
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
