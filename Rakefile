# frozen_string_literal: true

# Rakefile du gem scansion : tâches de test (rspec) et de documentation (rdoc).

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

require 'rdoc/task'
RDoc::Task.new do |rdoc|
  rdoc.main = 'README.md'
  rdoc.rdoc_files.include('lib/**/*.rb', 'README.md', 'CHANGELOG.md', 'docs/*.txt')
  rdoc.options << '--charset' << 'utf-8'
end

# YARD — utilisé par rubydoc.info pour la documentation en ligne de la gem
# (voir .yardopts). `rake yard` génère la doc dans doc/.
require 'yard'
YARD::Rake::YardocTask.new(:yard)
task doc: :yard

task default: :spec
