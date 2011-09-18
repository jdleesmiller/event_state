module EventState
  #
  # The example in the README.
  #
  class MessageEchoServer < EventState::ObjectMachine
    Noise = Struct.new(:content)

    protocol do
      state :listening do
        on_recv Noise, :speaking
      end

      state :speaking do
        on_send Noise, :listening

        on_enter do |noise|
          EM.add_timer 0.5 do
            send_message Noise.new(noise.content)
          end
        end
      end
    end
  end

  class MessageEchoClient < EventState::ObjectMachine
    Noise = MessageEchoServer::Noise

    def initialize noises
      super
      @noises = noises
    end

    protocol do
      state :speaking do
        on_send Noise, :listening

        on_enter do
          if @noises.empty?
            EM.stop
          else
            send_message MessageEchoServer::Noise.new(@noises.shift)
          end
        end
      end

      state :listening do
        on_recv Noise, :speaking

        on_enter do |noise|
          puts "heard: #{noise.content}"
        end
      end
    end

    def self.demo
      EM.run do
        EM.start_server('localhost', 14159, MessageEchoServer)
        EM.connect('localhost', 14159, MessageEchoClient, %w(foo bar baz))
      end
    end
  end
end

