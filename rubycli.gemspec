# frozen_string_literal: true

require_relative "lib/rubycli/version"

Gem::Specification.new do |spec|
  spec.name = "rubycli"
  spec.version = Rubycli::VERSION
  spec.authors = ["inakaegg"]
  spec.email = ["52376271+inakaegg@users.noreply.github.com"]

  spec.summary = "Python Fire-inspired doc-comment CLI wrapper delivering a Ruby Fire experience."

  spec.description = "Rubycli turns plain Ruby classes and modules into command-line interfaces by reading their documentation comments, inspired by Python Fire but tailored for Ruby tooling."
  spec.homepage = "https://github.com/inakaegg/rubycli"

  spec.metadata["homepage_uri"] = spec.homepage if spec.homepage
  spec.metadata["documentation_uri"] = "#{spec.homepage}#readme" if spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases" if spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues" if spec.homepage

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir.glob("lib/**/*") +
               Dir.glob("exe/*") +
               %w[README.md README.ja.md CHANGELOG.md LICENSE]
  spec.bindir = "exe"
  spec.executables = ["rubycli"]
  spec.require_paths = ["lib"]
  spec.license = "MIT"
end
