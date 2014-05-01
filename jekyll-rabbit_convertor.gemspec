# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'jekyll/rabbit_convertor/version'

Gem::Specification.new do |spec|
  spec.name          = "jekyll-rabbit_convertor"
  spec.version       = Jekyll::RabbitConvertor::VERSION
  spec.authors       = ["akira yamada"]
  spec.email         = ["akira@arika.org"]
  spec.summary       = %q{rabbit support for jekyll}
  spec.description   = %q{jekyll-rabbit_convertor adds rabbit support to jekyll.}
  spec.homepage      = "https://github.com/arika/jekyll-rabbit_convertor"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'rabbit', '~> 2.1.2'

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
end
