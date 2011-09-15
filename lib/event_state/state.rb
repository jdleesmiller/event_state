module EventState
  StateHandler = Struct.new(:message_name, :block)

  Transition = Struct.new(:message_name, :next_state)

  State = Struct.new(:name, :on_enters, :on_exits, :on_sends, :on_recvs)
  class State
    def call_on_enter context, message_name, message
      call_handler context, on_enters, message_name, message
    end

    def call_on_exit context, message_name, message
      call_handler context, on_exits, message_name, message
    end

    private

    def call_handler context, handlers, message_name, message
      # take the first handler that matches the message name
      handler = handlers.find {|h|
        h.message_name == message_name || h.message_name.nil?
      }

      # evaluate the block in the right context, namely the machine instance
      context.instance_exec(message, &handler.block) if handler 
    end
  end
end
