# frozen_string_literal: true

require "open3"
require "json"

module Minitest
  module Promptfoo
    # Handles execution of the promptfoo CLI and parsing of results
    class PromptfooRunner
      class ExecutionError < StandardError; end

      def initialize(configuration)
        @configuration = configuration
      end

      # Executes promptfoo CLI with the given config and options
      # Returns a hash with :success, :stdout, :stderr keys
      def execute(config_path, working_dir, pre_render: false, show_output: false)
        env_vars = build_env_vars(pre_render: pre_render)
        cmd = build_command(config_path)

        if show_output
          execute_with_output(env_vars, cmd, working_dir)
        else
          execute_silently(env_vars, cmd, working_dir)
        end
      end

      # Parses promptfoo JSON output file
      def parse_output(output_path)
        return {} unless File.exist?(output_path)

        JSON.parse(File.read(output_path))
      rescue JSON::ParserError => e
        raise ExecutionError, "Failed to parse promptfoo output: #{e.message}"
      end

      private

      def build_env_vars(pre_render:)
        pre_render ? {"PROMPTFOO_DISABLE_TEMPLATING" => "true"} : {}
      end

      def build_command(config_path)
        base_cmd = @configuration.resolve_executable
        args = ["eval", "-c", config_path, "--no-cache"]

        if base_cmd.start_with?("npx")
          base_cmd.split + args
        else
          [base_cmd] + args
        end
      end

      def execute_with_output(env_vars, cmd, working_dir)
        success = system(env_vars, *cmd, chdir: working_dir)
        {success: success, stdout: "", stderr: ""}
      end

      def execute_silently(env_vars, cmd, working_dir)
        stdout, stderr, status = Open3.capture3(env_vars, *cmd, chdir: working_dir)
        {success: status.success?, stdout: stdout, stderr: stderr}
      end
    end
  end
end
