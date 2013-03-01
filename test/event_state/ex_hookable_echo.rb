module EventState

  #
  # Receives a message and sends it back.
  #
  class HookableEchoMachine < HookableMachine
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

  # For a single test we do not add a mock library
  class HookableTestCallback

    attr_accessor :no_of_invocations, :last_message


    def send_message(message)
      @last_message = message
      @no_of_invocations ||= 0
      @no_of_invocations += 1
      nil
    end


  end



end