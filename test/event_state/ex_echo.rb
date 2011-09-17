module EventState
  #
  # Receives a message and sends it back.
  #
  class EchoServer < EventState::ObjectMachine
    protocol do
      state :listening do
        on_recv String, :speaking
      end

      state :speaking do
        on_enter do |message|
          send_message message
        end

        on_send String, :listening
      end
    end
  end

  #
  # Receives a message and sends it back after a short delay.
  #
  class DelayedEchoServer < EventState::ObjectMachine
    def initialize delay
      super
      @delay = delay
    end

    protocol do
      state :listening do
        on_recv String, :speaking
      end

      state :speaking do
        on_enter do |message|
          EM.defer proc { sleep @delay },
                   proc { send_message message }
        end

        on_send String, :listening
      end
    end
  end

  #
  # Receives a message and sends it back. Keeps a log for testing purposes.
  #
  class LoggingEchoServer < EventState::ObjectMachine

    def initialize log=nil
      super
      @log = log
    end

    protocol do
      state :listening do
        on_recv String, :speaking

        on_enter do
          @log << "entering listening state" if @log
        end

        on_exit do
          @log << "exiting listening state" if @log
        end
      end

      state :speaking do
        on_send String, :listening

        on_enter do |message|
          @log << "speaking #{message}" if @log
          send_message message
        end

        on_exit do
          @log << "exiting speaking state" if @log
        end
      end
    end
  end

  #
  # Implementation of {EchoClient} without EventState, for comparison.
  #
  module ObjectProtocolEchoClient
    include EventMachine::P::ObjectProtocol

    def initialize noises, recorder
      super
      @noises, @recorder = noises, recorder
    end

    attr_accessor :recorder

    def post_init
      # send first noise
      send_object @noises.shift
    end

    def receive_object message
      # record received noise
      @recorder << message

      if @noises.empty?
        # done
        EventMachine.stop
      else
        # make more noises
        send_object @noises.shift
      end
    end
  end

  #
  # Send a list of noises to an {EchoServer} and record the echos.
  #
  class EchoClient < EventState::ObjectMachine
    def initialize noises, recorder
      super
      @noises, @recorder = noises, recorder
    end

    attr_accessor :recorder

    protocol do
      state :speaking do
        on_send String, :listening

        on_enter do
          if @noises.empty?
            EventMachine.stop
          else
            send_message @noises.shift
          end
        end
      end

      state :listening do
        on_recv String, :speaking

        on_exit do |message|
          @recorder << message
        end
      end
    end
  end
end

