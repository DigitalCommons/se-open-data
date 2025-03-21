# -*- ruby -*-
# frozen_string_literal: true
Gem::Specification.new do |s|
  s.name        = 'se_open_data'
  s.version     = '2.4.1'
  s.licenses    = ['GPL-3.0-or-later']
  s.summary     = "Digital Commons Co-operative Open Data transforms"
  s.description = <<-HERE
    This is a collection of Ruby classes for transforming 3rd party data into 
    a uniform schema and thence into RDF linked open data.
  HERE
  s.authors     = ["Digital Commons Co-operative"]
  s.email       = 'tech.accounts@digitalcommons.coop'
  # The twiddly [!~] bit at the end of these globs excludes emacs backup files
  s.files       =  Dir['lib/**/*.rb'] + Dir['bin/**[!~]'] + Dir['resources/**[!~]']
  s.executables.concat Dir.glob('*[!~]', base: 'bin')
  s.homepage    = 'https://github.com/DigitalCommons/se-open-data'
  s.metadata    = { "source_code_uri" => "https://github.com/DigitalCommons/se-open-data" }

  s.add_runtime_dependency('httparty')
  s.add_runtime_dependency('i18n')
  s.add_runtime_dependency('geocoder', '>= 1.8')
  s.add_runtime_dependency('levenshtein')
  s.add_runtime_dependency('linkeddata', '>= 3.2')
  s.add_runtime_dependency('nokogiri')
  s.add_runtime_dependency('normalize_country')
  s.add_runtime_dependency('opencage-geocoder')
  s.add_runtime_dependency('prawn')
  s.add_runtime_dependency('prawn-table')
  s.add_runtime_dependency('thor')
  
  s.add_development_dependency('rake')
  s.add_development_dependency('minitest')
end

# Ubuntu prereqs
# sudo apt-get install build-essential patch ruby-dev zlib1g-dev liblzma-dev git dev-libzip ruby ruby-bundler
