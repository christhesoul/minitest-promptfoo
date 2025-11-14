# frozen_string_literal: true

require "test_helper"
require "yaml"

module Minitest
  module Promptfoo
    class TestPromptfooTest < Minitest::Test
      def test_assertion_builder_includes
        builder = Minitest::Promptfoo::AssertionBuilder.new
        builder.includes("hello")

        assertions = builder.to_promptfoo_assertions
        assert_equal(1, assertions.length)
        assert_equal("contains", assertions[0]["type"])
        assert_equal("hello", assertions[0]["value"])
      end

      def test_assertion_builder_matches
        builder = Minitest::Promptfoo::AssertionBuilder.new
        builder.matches(/\d+/)

        assertions = builder.to_promptfoo_assertions
        assert_equal(1, assertions.length)
        assert_equal("regex", assertions[0]["type"])
        assert_equal("\\d+", assertions[0]["value"])
      end

      def test_assertion_builder_equals
        builder = Minitest::Promptfoo::AssertionBuilder.new
        builder.equals("exact match")

        assertions = builder.to_promptfoo_assertions
        assert_equal(1, assertions.length)
        assert_equal("equals", assertions[0]["type"])
        assert_equal("exact match", assertions[0]["value"])
      end

      def test_assertion_builder_json_includes
        builder = Minitest::Promptfoo::AssertionBuilder.new
        builder.json_includes(key: "status", value: "success")

        assertions = builder.to_promptfoo_assertions
        assert_equal(2, assertions.length)
        assert_equal("is-json", assertions[0]["type"])
        assert_equal("javascript", assertions[1]["type"])
      end

      def test_assertion_builder_rubric
        builder = Minitest::Promptfoo::AssertionBuilder.new
        builder.rubric("Response is professional", threshold: 0.8)

        assertions = builder.to_promptfoo_assertions
        assert_equal(1, assertions.length)
        assert_equal("llm-rubric", assertions[0]["type"])
        assert_equal("Response is professional", assertions[0]["value"])
        assert_equal(0.8, assertions[0]["threshold"])
      end

      def test_assertion_builder_multiple_assertions
        builder = Minitest::Promptfoo::AssertionBuilder.new
        builder.includes("hello")
        builder.matches(/world/)
        builder.rubric("Be nice")

        assertions = builder.to_promptfoo_assertions
        assert_equal(3, assertions.length)
      end

      def test_assertion_builder_force_json_flag_defaults_to_false
        builder = Minitest::Promptfoo::AssertionBuilder.new
        refute(builder.force_json?)
      end

      def test_assertion_builder_force_json_sets_flag
        builder = Minitest::Promptfoo::AssertionBuilder.new
        builder.force_json!
        assert(builder.force_json?)
      end

      def test_build_promptfoo_config_adds_transform_response_when_force_json
        test_class = Class.new do
          include Minitest::Promptfoo::TestMethods
          public :build_promptfoo_config
        end.new

        config = test_class.build_promptfoo_config(
          prompt: "test",
          vars: {},
          providers: ["anthropic:claude-3-5-sonnet-20241022"],
          assertions: [],
          output_path: "/tmp/output.json",
          force_json: true
        )

        provider_config = config["providers"].first
        assert_equal("anthropic:claude-3-5-sonnet-20241022", provider_config["id"])
        assert(provider_config["config"])
        assert(provider_config["config"]["transformResponse"])
        assert_match(/replace/, provider_config["config"]["transformResponse"])
      end

      def test_build_promptfoo_config_without_force_json
        test_class = Class.new do
          include Minitest::Promptfoo::TestMethods
          public :build_promptfoo_config
        end.new

        config = test_class.build_promptfoo_config(
          prompt: "test",
          vars: {},
          providers: ["anthropic:claude-3-5-sonnet-20241022"],
          assertions: [],
          output_path: "/tmp/output.json",
          force_json: false
        )

        provider_config = config["providers"].first
        assert_equal("anthropic:claude-3-5-sonnet-20241022", provider_config["id"])
        refute(provider_config["config"])
      end
    end
  end
end
