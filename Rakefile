# frozen_string_literal: true

require "bundler/gem_tasks"
begin
  require "rspec/core/rake_task"
  require "rubocop/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  RuboCop::RakeTask.new
rescue LoadError => exception
  puts "Library not available: #{exception.message}"
end

desc "Build, lint, and test"
task :build_and_test do
  Rake::Task["lint"].invoke
  Rake::Task["test"].invoke
  Rake::Task["build"].invoke unless ENV["CI"]
end

desc "Lint"
task lint: :rubocop

desc "Test"
task test: :spec

task default: :build_and_test
