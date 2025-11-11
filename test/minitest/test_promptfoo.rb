# frozen_string_literal: true

require "test_helper"

class Minitest::TestPromptfoo < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Minitest::Promptfoo::VERSION
  end

  def test_it_loads_without_error
    assert true
  end
end
