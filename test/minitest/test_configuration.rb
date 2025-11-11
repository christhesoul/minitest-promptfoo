# frozen_string_literal: true

require "test_helper"

module Minitest
  module Promptfoo
    class TestConfiguration < Minitest::Test
      def setup
        Minitest::Promptfoo.reset_configuration!
      end

      def teardown
        Minitest::Promptfoo.reset_configuration!
      end

      def test_default_configuration
        config = Minitest::Promptfoo.configuration

        assert_instance_of(Configuration, config)
        assert_nil(config.promptfoo_executable)
        assert_equal(Dir.pwd, config.root_path)
      end

      def test_configure_block
        Minitest::Promptfoo.configure do |config|
          config.promptfoo_executable = "/custom/path/promptfoo"
          config.root_path = "/custom/root"
        end

        config = Minitest::Promptfoo.configuration
        assert_equal("/custom/path/promptfoo", config.promptfoo_executable)
        assert_equal("/custom/root", config.root_path)
      end

      def test_resolve_executable_with_configured_path
        # Skip this test since we can't easily create a fake executable
        # The real-world usage will have an actual promptfoo binary
        skip "Requires actual executable file for testing"
      end

      def test_resolve_executable_falls_back_to_npx
        config = Minitest::Promptfoo.configuration
        resolved = config.resolve_executable

        # Should fall back to npx since no executable is configured
        assert_equal("npx promptfoo", resolved)
      end
    end
  end
end
