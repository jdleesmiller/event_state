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
    EventState::EchoServer.print_state_machine_dot :io => io,
      :graph_opts => 'rankdir=LR;'
  end

  require 'event_state/ex_secret'
  abbrev = proc {|s| s.to_s.split('::').last.sub(/Message$/,'')}
  IO.popen("dot -Tpng -o assets/secret_server.png", 'w') do |io|
    EventState::TopSecretServer.print_state_machine_dot :io => io,
      :message_name_transform => abbrev
  end
  IO.popen("dot -Tpng -o assets/secret_client.png", 'w') do |io|
    EventState::TopSecretClient.print_state_machine_dot :io => io,
      :message_name_transform => abbrev
  end
end
