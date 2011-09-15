# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
 
require 'event_state/version'
 
Gem::Specification.new do |s|
  s.name              = 'event_state'
  s.version           = EventState::VERSION
  s.platform          = Gem::Platform::RUBY
  s.authors           = ['John Lees-Miller']
  s.email             = ['jdleesmiller@gmail.com']
  s.homepage          = 'http://github.com/jdleesmiller/event_state'
  s.summary           = %q{StateMachines for EventMachines.}
  s.description       = %q{A small embedded DSL for implementing stateful protocols in EventMachine using finite state machines.}

  s.rubyforge_project = 'event_state'

  s.add_runtime_dependency 'eventmachine', '~> 0.12.10'

  s.add_development_dependency 'gemma', '~> 2.0.0'

  s.files       = Dir.glob('{lib,bin}/**/*.rb') + %w(README.rdoc)
  s.test_files  = Dir.glob('test/**/*_test.rb')

  s.rdoc_options = [
    "--main",    "README.rdoc",
    "--title",   "#{s.full_name} Documentation"]
  s.extra_rdoc_files << "README.rdoc"
end

