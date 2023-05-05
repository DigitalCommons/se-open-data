# Rakefile contents copied from https://gist.github.com/zuazo/650eda19dc88a4eb91d4
#
# Available Rake tasks:
#
# $ rake -T
# rake doc   # Generate Ruby documentation
# rake style                    # Run all style checks
# rake style:ruby               # Run Ruby style checks using rubocop
# rake style:ruby:auto_correct  # Auto-correct RuboCop offenses
# rake yard                     # Generate Ruby documentation using yard

desc 'Generate Ruby documentation using yard'
task :yard do
  require 'yard'
  YARD::Rake::YardocTask.new do |t|
    # See .yardopts for the options for this
  end
end

desc 'Run yard documentation server'
task :yardserver do
  # See .yardopts for the options for this
  `yard server --reload`
end

desc 'Generate Ruby documentation'
task doc: %w(yard)

#namespace :style do
#  require 'rubocop/rake_task'
#  desc 'Run Ruby style checks using rubocop'
#  RuboCop::RakeTask.new(:ruby)
#end
#
#desc 'Run all style checks'
#task style: %w(style:ruby)

desc 'Run tests'
task :test do
  require "rake/testtask"
  Rake::TestTask.new(:test) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/**/test_*.rb"]
    t.warning = false # avoids warning about all the gems we depend on
  end
end

