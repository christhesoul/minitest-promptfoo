# frozen_string_literal: true

require_relative "lib/minitest/promptfoo/version"

Gem::Specification.new do |spec|
  spec.name = "minitest-promptfoo"
  spec.version = Minitest::Promptfoo::VERSION
  spec.authors = ["Chris Waters"]
  spec.email = ["chris.waters@shopify.com"]

  spec.summary = "Minitest integration for promptfoo - test your LLM prompts with confidence"
  spec.description = "A thin Minitest wrapper around promptfoo that brings prompt testing to Ruby projects. Test LLM prompts with a familiar Minitest-like DSL, supporting multiple providers and assertion types."
  spec.homepage = "https://github.com/christhesoul/minitest-promptfoo"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/christhesoul/minitest-promptfoo"
  spec.metadata["changelog_uri"] = "https://github.com/christhesoul/minitest-promptfoo/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "minitest", "~> 5.0"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "standard", ">= 1.35.1"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
