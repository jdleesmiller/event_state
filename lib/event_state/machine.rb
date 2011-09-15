module EventState

  class Machine < EventMachine::Connection
    include EventMachine::P::ObjectProtocol

    class << self
      def state state_name
        @states ||= {}

        # create new state or edit exiting state
        @state = @states[state_name] ||
          State.new(state_name, [], [], {}, {})

        # configure this state 
        yield

        # need to know the start state
        @start_state = @state if @states.empty?

        # index by name for easy lookup
        @states[@state.name] = @state

        # ensure that on_enter etc. aren't callable outside of a state block
        @state = nil
      end

      def on_enter *message_names, &block
        raise "on_enter must be called from a state block" unless @state
        push_state_handlers(@state.on_enters, message_names, block)
      end

      def on_exit *message_names, &block
        raise "on_exit must be called from a state block" unless @state
        push_state_handlers(@state.on_exits, message_names, block)
      end

      def on_send *message_names, next_state
        raise "on_send must be called from a state block" unless @state
        message_names.flatten.each do |name|
          @state.on_sends[name] = Transition.new(name, next_state)
        end
      end
      
      def on_recv *message_names, next_state
        raise "on_recv must be called from a state block" unless @state
        message_names.flatten.each do |name|
          @state.on_recvs[name] = Transition.new(name, next_state)
        end
      end

      def on_protocol_error &block
        if block_given?
          @on_protocol_error = block
          nil
        else
          # set default
          @on_protocol_error ||= proc {|message|
            raise "bad message: #{$!.inspect}"
          }

          @on_protocol_error
        end
      end

      attr_reader :states

      attr_reader :start_state

      private

      def push_state_handlers handlers, message_names, block
        message_names.flatten!
        if message_names.empty?
          # this is convention for a catch-all handler
          handlers.push(StateHandler.new(nil, block))
        else
          # push the handlers on in order
          handlers.push(*message_names.map {|name|
            StateHandler.new(name, block)})
        end
      end
    end

    def initialize(*)
      super

      puts "MACHINE INIT"

      # put machine into the start state
      @state = self.class.start_state
    end

    #
    # Called by +EventMachine+ when a new connection has been established. This
    # calls the +on_enter+ handler for the machine's start state with a +nil+
    # message name and a +nil+ message.
    #
    # Be sure to call +super+ if you override this method, or +on_enter+ handler
    # for the start state will not be called.
    #
    # @return [nil]
    #
    def post_init
      puts "MACHINE POST_INIT: #{@state.inspect}"

      @state.call_on_enter self, nil, nil
      nil
    end

    #
    # Called by +EventMachine+ (actually, the +ObjectProtocol+) when a message
    # is recived.
    #
    # Note: if you want to receive non-messages as well, you should override
    # this method in your subclass, and call +super+ only when a message is
    # received.
    #
    # @return [nil]
    #
    def receive_object message
      puts "MACHINE RECV: #{message.inspect} (#{message.to_sym})"
      # all valid messages must have a symbolic name
      begin
        message_name = message.to_sym
      rescue NoMethodError
        raise "received object is not a message: #{message.inspect}"
      end

      # look up what we should do for this message
      transition = @state.on_recvs[message_name]
      p transition

      # if transition is nil, it's a protocol error
      if transition.nil?
        self.class.on_protocol_error.call(message)
      else
        # call exit handler, do the transition, then call enter handler
        @state.call_on_exit self, message_name, message
        @state = self.class.states[transition.next_state]
        @state.call_on_enter self, message_name, message
      end

      nil
    end

    #
    # Send the given message to the client and update the current machine state.
    #
    # The precise order of events is:
    # 1. the +on_exit+ handler of the current state is called with +message+ 
    # 2. the +message+ is sent using <tt>ObjectProtocol</tt>'s +send_object+
    # 3. the current state is set to the successor state
    # 4. the +on_enter+ handler of the new current state is called with
    #    +message+
    #
    # @return [nil]
    #
    def send_message message
      puts "MACHINE SEND: #{message.inspect}"

      # all valid messages must have a symbolic name
      begin
        message_name = message.to_sym
      rescue NoMethodError
        raise "object to be sent is not a message: #{message.inspect}"
      end

      # look up what we should do for this message
      transition = @state.on_sends[message_name]
      p transition

      # if transition is nil, it's a protocol error
      if transition.nil?
        self.class.on_protocol_error.call(message)
      else
        # call exit handler, do the transition, then call enter handler
        @state.call_on_exit self, message_name, message
        send_object message
        @state = self.class.states[transition.next_state]
        @state.call_on_enter self, message_name, message
      end
      
      nil
    end
  end
end
