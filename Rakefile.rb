require 'rubygems'
require 'bundler/setup'
require 'gemma'

Gemma::RakeTasks.with_gemspec_file 'event_state.gemspec'

task :default => :test

task :assets do
  require 'event_state'
  $: << 'test'
  require 'event_state/ex_echo'
  IO.popen("dot -Tpng -o assets/echo.png", 'w') do |io|
    EventState::EchoClient.print_state_machine_dot io, 'rankdir=LR;'
  end
end
