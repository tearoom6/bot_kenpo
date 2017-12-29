Gem::Specification.new do |spec|
  spec.name          = 'lita-kenpo'
  spec.version       = '0.1.0'
  spec.authors       = ['tearoom6']
  spec.email         = ['tearoom6.biz@gmail.com']
  spec.description   = 'Concierge to assist your reservation to its-kenpo.'
  spec.summary       = 'Concierge to assist your reservation to its-kenpo.'
  spec.homepage      = 'https://github.com/tearoom6/bot_kenpo'
  spec.metadata      = { 'lita_plugin_type' => 'handler' }

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'lita', '>= 4.7'

  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rack-test'
  spec.add_development_dependency 'rspec', '>= 3.0.0'
end
