# frozen_string_literal: true

require_relative 'lib/scansion/version'

Gem::Specification.new do |spec|
  spec.name          = 'scansion'
  spec.version       = Scansion::VERSION
  spec.executables   = ['scansion']
  spec.bindir        = 'bin'
  spec.authors       = 'anantone'
  spec.email         = 'self@anantone.me'

  spec.summary       = 'Scansion de vers français : syllabes, accents, régimes classique/contemporain'
  spec.description   = 'Phonétise des vers français (espeak-ng via phonemizer_ffi), compte les ' \
                       'syllabes et produit groupes rythmiques et accents ˈ/ˌ. Le régime du texte ' \
                       'est détecté automatiquement (mode :auto) : vers classique (mètres pairs ' \
                       'rimés, diérèses, césure) ou contemporain (e caduc non compté, tirage ' \
                       'accentuel 2.6).'
  spec.homepage      = 'https://github.com/anantone/scansion'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata = {
    'source_code_uri' => 'https://github.com/anantone/scansion',
    'changelog_uri' => 'https://github.com/anantone/scansion/blob/main/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/anantone/scansion/issues',
    'documentation_uri' => 'https://rubydoc.info/gems/scansion'
  }

  spec.files         = Dir['lib/**/*.rb', 'docs/**/*.txt', 'README.md', 'LICENSE', 'CHANGELOG.md', '.yardopts']
  spec.require_paths = ['lib']

  spec.add_dependency 'phonemizer_ffi', '~> 0.1'

  spec.add_development_dependency 'kramdown'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rdoc'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.93'
  spec.add_development_dependency 'yard'
end
