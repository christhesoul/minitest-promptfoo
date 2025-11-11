# frozen_string_literal: true

require_relative "promptfoo/version"
require_relative "promptfoo/configuration"
require_relative "promptfoo/test"

# Auto-load Rails integration if Rails is detected
if defined?(Rails)
  require_relative "promptfoo/rails"
end

module Minitest
  module Promptfoo
    class Error < StandardError; end
  end
end
