# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = true
end

desc "Validate the RBS signatures in sig/"
task :rbs do
  sh "rbs -I sig validate"
end

task default: :test
