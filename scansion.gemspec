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
                       '(e caduc) selon les règles de la scansion classique, puis marque ' \
                       'les frontières de syllabes et compte les syllabes.'
  spec.homepage      = 'https://github.com/anantone/scansion'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.files         = Dir['lib/**/*.rb', 'docs/**/*.txt', 'README.md', 'LICENSE', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'phonemizer_ffi', '~> 0.1'

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 3.13'
end
