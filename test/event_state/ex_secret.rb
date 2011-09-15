module EventState
  LoginMessage = MessageStruct.new(:user_name, :password)
  SecretMessage = MessageStruct.new(:message)

  class TopSecretServer < EventState::Machine
    state :public do
      on_enter do
        puts "server started"
      end
      on_recv :login_message, :pending
    end

    state :pending do
      on_enter do |message|
        if message.user_name == message.password # high security
          send_message :access_granted
        else
          send_message :access_denied
        end
      end

      on_send :access_granted, :authenticated
      on_send :access_denied,  :public
    end

    state :authenticated do
      on_recv :get_fast_secret, :sending
      on_recv :get_slow_secret, :sending
      on_recv :logout, :public
    end

    state :sending do
      on_enter :get_fast_secret do
        send_message SecretMessage.new("42")
      end

      on_enter :get_slow_secret do
        EM.defer do
          sleep 3
          send_message SecretMessage.new("43")
        end
      end

      on_send :secret, :authenticated
    end
  end

  class TopSecretClient < EventState::Machine
    state :unauthenticated do
      on_send :login_message, :pending

      on_enter do
        send_message LoginMessage.new('hello','hello')
      end
    end
    
    state :pending do
      on_recv :access_granted, :authenticated
      on_recv :access_denied,  :unauthenticated
    end

    state :authenticated do
      on_send [:get_fast_secret, :get_slow_secret], :receiving
      on_send :logout, :unauthenticated

      on_enter :access_granted do
        @secrets = 0
        send_message :get_fast_secret
      end
      
      on_enter :secret do
        @secrets += 1
        if @secrets == 1
          send_message :get_slow_secret
        else
          send_message :logout
        end
      end
    end

    state :receiving do
      on_recv :secret_message, :authenticated
    end
  end
end
