# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |task|
  task.libs = %w[lib test]
  task.test_files = FileList['test/*_test.rb']
  task.warning = false
end

desc 'Run the test suite and enforce the repository coverage thresholds'
task :coverage do
  ruby '-Ilib:test test/coverage_runner.rb'
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:lint)
rescue LoadError
  desc 'Run RuboCop (not installed)'
  task :lint do
    abort 'RuboCop is not available. Run `bundle install` first.'
  end
end

task default: %i[test lint]
