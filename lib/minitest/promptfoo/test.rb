# frozen_string_literal: true

require "yaml"
require "tmpdir"
require "minitest/test"
require_relative "assertion_builder"
require_relative "failure_formatter"
require_relative "promptfoo_runner"

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

      # Class-level configuration
      class << self
        def debug?
          ENV["DEBUG_PROMPT_TEST"] == "1"
        end

        def providers
          @providers || "echo"
        end

        attr_writer :providers

        def inherited(subclass)
          super
          subclass.providers = providers if defined?(@providers)
        end
      end

      def prompt_path
        raise NotImplementedError, "#{self.class}#prompt_path must be implemented"
      end

      def prompt_content
        @prompt_content ||= begin
          path = prompt_path
          raise PromptNotFoundError, "Prompt file not found: #{path}" unless File.exist?(path)
          File.read(path, encoding: "UTF-8")
        end
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

        output = evaluate_prompt(
          prompt_text: prompt_content,
          vars: vars,
          providers: providers,
          assertions: builder.to_promptfoo_assertions,
          verbose: verbose,
          pre_render: pre_render
        )

        # Real assertion: verify promptfoo produced results
        assert(output.any?, "Promptfoo evaluation produced no output")

        output
      end

      def evaluate_prompt(prompt_text:, vars:, providers: nil, assertions: [], pre_render: false, verbose: false, show_output: false)
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

          debug("Promptfoo Config", config_yaml)

          runner = PromptfooRunner.new(Minitest::Promptfoo.configuration)
          result = runner.execute(config_path, tmpdir, show_output: show_output, pre_render: pre_render)

          debug("Promptfoo Result", result.inspect)

          output = runner.parse_output(output_path)

          unless result[:success] || output.any?
            raise EvaluationError, <<~ERROR
              promptfoo evaluation failed
              STDOUT: #{result[:stdout]}
              STDERR: #{result[:stderr]}
            ERROR
          end

          check_provider_failures(output, providers_array, verbose: verbose) if assertions.any?

          output
        end
      end

      private

      def debug(title, content)
        return unless self.class.debug?

        warn "\n=== #{title} ==="
        warn content
        warn "=" * (title.length + 8)
        warn ""
      end

      # Simple array wrapper (replaces ActiveSupport's Array.wrap)
      def wrap_array(object)
        case object
        when nil then []
        when Array then object
        else [object]
        end
      end

      # Simple deep stringify keys (replaces ActiveSupport method)
      def deep_stringify_keys(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_s] = stringify_value(value)
        end
      end

      def stringify_value(value)
        case value
        when Hash then deep_stringify_keys(value)
        when Array then value.map { |v| stringify_value(v) }
        else value
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
    end
  end
end
