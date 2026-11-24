# frozen_string_literal: true

require_relative 'lib/scansion/version'

Gem::Specification.new do |spec|
  spec.name          = 'scansion'
  spec.version       = Scansion::VERSION
  spec.executables   = ["scansion"]
  spec.bindir        = 'bin'
  spec.authors       = 'anantone'
  spec.email         = 'self@anantone.me'

  spec.summary       = 'Scansion de vers français avec restauration du e muet (e caduc)'
  spec.description   = 'Phonétise des vers français avec espeak-ng et restaure le e muet ' \
                       '(e caduc) selon les règles de la scansion classique, puis accentue' \
                       'et compte les syllabes.'
  spec.homepage      = 'https://github.com/anantone/scansion'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  # Métadonnées lues notamment par rubydoc.info (qui génère la doc avec YARD
  # à partir du dépôt source) et par rubygems.org.
  spec.metadata      = {
    'source_code_uri'   => 'https://github.com/anantone/scansion',
    'changelog_uri'     => 'https://github.com/anantone/scansion/blob/main/CHANGELOG.md',
    'bug_tracker_uri'   => 'https://github.com/anantone/scansion/issues',
    'documentation_uri' => 'https://rubydoc.info/gems/scansion'
  }

  spec.files         = Dir['lib/**/*.rb', 'docs/**/*.txt', 'README.md', 'LICENSE', 'CHANGELOG.md', '.yardopts']
  spec.require_paths = ['lib']

  spec.add_dependency 'phonemizer_ffi', '~> 0.1'

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rdoc'
  spec.add_development_dependency 'yard'
  spec.add_development_dependency 'kramdown' # provider markdown de YARD
end
