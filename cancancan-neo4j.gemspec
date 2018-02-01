# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cancancan/neo4j/version'

Gem::Specification.new do |spec|
  spec.name          = 'cancancan-neo4j'
  spec.version       = CanCanCan::Neo4j::VERSION
  spec.authors       = ['Amit Suryavanshi']
  spec.email         = ['amitbsuryavanshi@gmail.com']
  spec.homepage      = 'https://github.com/CanCanCommunity/cancancan-neo4j'
  spec.summary       = 'neo4j database adapter for CanCanCan.'
  spec.description   = "Implements CanCanCan's rule-based record fetching using neo4j gem."
  spec.platform      = Gem::Platform::RUBY
  spec.license       = 'MIT'

  spec.files         = `git ls-files lib init.rb cancancan-neo4j.gemspec`.split($INPUT_RECORD_SEPARATOR)
  spec.require_paths = ['lib']

  spec.add_dependency 'cancancan', '~> 2.0'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake', '~> 10.1'
  spec.add_development_dependency 'rspec', '~> 3.2'
  spec.add_development_dependency 'rubocop', '~> 0.48.1'
  spec.add_development_dependency 'simplecov', '~> 0.12'
  spec.add_development_dependency 'coveralls', '~> 0.8'
  spec.add_development_dependency 'codeclimate-test-reporter', '~> 1.0'
  spec.add_development_dependency 'neo4j', '~> 9.0.0'
  spec.add_development_dependency 'pry', '~> 0.11.3'
  spec.add_development_dependency('neo4j-community', '~> 2.0') if RUBY_PLATFORM =~ /java/
end
