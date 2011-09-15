module EventState
  #
  # The message object for the {EchoServer} and {EchoClient}s.
  #
  EchoMessage = Struct.new(:noise)
  class EchoMessage
    include EventState::Message
  end

  #
  # Receives a message and sends it back. Keeps a log for testing purposes.
  #
  class EchoServer < EventState::Machine

    def initialize log=nil
      super
      @log = log
    end

    state :listening do
      on_recv :echo_message, :echoing

      on_enter do
        @log << "entering listening state" if @log
      end

      on_exit do
        @log << "exiting listening state" if @log
      end
    end

    state :echoing do
      on_send :echo_message, :listening

      on_enter do |message|
        @log << "echoing #{message.noise}" if @log
        send_message message
      end

      on_exit do
        @log << "exiting echoing state" if @log
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
      send_object EchoMessage.new(@noises.shift)
    end

    def receive_object message
      # record received noise
      @recorder << message.noise

      if @noises.empty?
        # done
        EventMachine.stop
      else
        # make more noises
        send_object EchoMessage.new(@noises.shift)
      end
    end
  end

  #
  # Send a list of noises to an {EchoServer} and record the echos.
  #
  class EchoClient < EventState::Machine
    def initialize noises, recorder
      super
      @noises, @recorder = noises, recorder
    end

    attr_accessor :recorder

    state :speaking do
      on_send :echo_message, :listening

      on_enter do
        if @noises.empty?
          EventMachine.stop
        else
          send_message EchoMessage.new(@noises.shift)
        end
      end
    end

    state :listening do
      on_recv :echo_message, :speaking

      on_exit do |message|
        @recorder << message.noise
      end
    end
  end
end

