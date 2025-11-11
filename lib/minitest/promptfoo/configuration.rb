# frozen_string_literal: true

module Minitest
  module Promptfoo
    class Configuration
      attr_accessor :promptfoo_executable, :root_path

      def initialize
        @promptfoo_executable = nil
        @root_path = Dir.pwd
      end

      # Resolves the promptfoo executable path
      # Priority: configured path > npx promptfoo
      def resolve_executable
        return promptfoo_executable if promptfoo_executable && executable_exists?(promptfoo_executable)

        # Try local node_modules
        local_bin = File.join(root_path, "node_modules", ".bin", "promptfoo")
        return local_bin if executable_exists?(local_bin)

        # Fall back to npx
        "npx promptfoo"
      end

      private

      def executable_exists?(path)
        File.exist?(path) && File.executable?(path)
      end
    end

    class << self
      attr_writer :configuration

      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end
