# frozen_string_literal: true

require_relative 'lib/rubycli/version'

Gem::Specification.new do |spec|
  spec.name = 'rubycli'
  spec.version = Rubycli::VERSION
  spec.authors = ['inakaegg']
  spec.email = ['52376271+inakaegg@users.noreply.github.com']

  spec.summary = 'Python Fire-inspired doc-comment CLI wrapper delivering a Ruby Fire experience.'

  spec.description = 'Rubycli turns plain Ruby classes and modules into command-line interfaces by reading their documentation comments, inspired by Python Fire but tailored for Ruby tooling.'
  spec.homepage = 'https://github.com/inakaegg/rubycli'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['documentation_uri'] = "#{spec.homepage}#readme"
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.required_ruby_version = '>= 3.0'

  # Minitest 6 moved Minitest::Mock into the separate minitest-mock gem; staying
  # on the 5.x line keeps `bundle exec rake test` working without extra setup.
  spec.add_development_dependency 'minitest', '~> 5.25'
  spec.add_development_dependency 'rake', '~> 13.0'
  # Optional stdlib type hints (BigDecimal) are exercised by the test suite;
  # bigdecimal stopped being a default gem in Ruby 3.4.
  spec.add_development_dependency 'bigdecimal', '~> 3.1'

  # examples/ is shipped because both READMEs walk through those files.
  spec.files = Dir.glob('lib/**/*') +
               Dir.glob('exe/*') +
               Dir.glob('examples/*.rb') +
               %w[README.md README.ja.md CHANGELOG.md LICENSE]
  spec.bindir = 'exe'
  spec.executables = ['rubycli']
  spec.require_paths = ['lib']
  spec.license = 'MIT'
end
