# frozen_string_literal: true

module Minitest
  module Promptfoo
    # Rails integration for automatic prompt file discovery
    #
    # Automatically discovers .ptmpl or .liquid prompt files based on Rails conventions:
    #   app/services/foo/bar.ptmpl → test/services/foo/bar_test.rb
    #
    # Usage:
    #   class MyPromptTest < Minitest::Promptfoo::RailsTest
    #     # No need to define prompt_path, it's auto-discovered!
    #
    #     test "generates greeting" do
    #       assert_prompt(vars: { name: "Alice" }) do |response|
    #         response.includes("Hello Alice")
    #       end
    #     end
    #   end
    module Rails
      def self.included(base)
        base.class_eval do
          # Override prompt_path to use Rails convention-based discovery
          def prompt_path
            @prompt_path ||= resolve_prompt_path_rails
          end

          private

          def resolve_prompt_path_rails
            test_file_path = method(name).source_location[0]
            test_dir = File.dirname(test_file_path)
            test_basename = File.basename(test_file_path, "_test.rb")

            app_dir = test_dir.gsub(%r{^(.*/)?test/}, '\1app/')

            [".ptmpl", ".liquid"].each do |ext|
              candidate = File.join(app_dir, "#{test_basename}#{ext}")
              return candidate if File.exist?(candidate)
            end

            raise PromptNotFoundError, "Could not find prompt file for #{test_file_path}"
          end
        end
      end
    end

    # Convenience class that combines Test + Rails integration
    # Inherits from ActiveSupport::TestCase if available, otherwise Minitest::Test
    if defined?(ActiveSupport::TestCase)
      class RailsTest < ActiveSupport::TestCase
        include Minitest::Promptfoo::Rails

        # Borrow all the assertion methods from Test
        # but keep ActiveSupport::TestCase as the base
        include Minitest::Promptfoo::Test.instance_methods(false).each_with_object(Module.new) { |m, mod|
          mod.define_method(m, Minitest::Promptfoo::Test.instance_method(m))
        }

        # Include class methods
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
      end
    else
      # Fallback if ActiveSupport isn't available
      class RailsTest < Test
        include Rails
      end
    end
  end
end
