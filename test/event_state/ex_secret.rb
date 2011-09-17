module EventState
  LoginMessage = Struct.new(:user_name, :password)
  SecretMessage = Struct.new(:message)
  class AccessGrantedMessage; end
  class AccessDeniedMessage; end
  class LogoutMessage; end
  class GetSmallSecretMessage; end
  class GetBigSecretMessage; end

  class TopSecretServer < EventState::ObjectMachine
    protocol do
      state :unathenticated do
        on_enter do
          puts "server started"
        end
        on_recv LoginMessage, :authenticating
      end

      state :authenticating do
        on_enter do |message|
          if message.user_name == message.password # high security
            send_message AccessGrantedMessage.new
          else
            send_message AccessDeniedMessage.new
          end
        end

        on_send AccessGrantedMessage, :authenticated
        on_send AccessDeniedMessage,  :unathenticated
      end

      state :authenticated do
        on_recv GetSmallSecretMessage, :exchanging
        on_recv GetBigSecretMessage,   :exchanging
        on_recv LogoutMessage, :unathenticated
      end

      state :exchanging do
        on_enter GetSmallSecretMessage do
          send_message SecretMessage.new("42")
        end

        on_enter GetBigSecretMessage do
          EM.defer do
            sleep 1 # takes a while to compute this one
            send_message SecretMessage.new("43")
          end
        end

        on_send SecretMessage, :authenticated
      end
    end
  end

  class TopSecretClient < EventState::ObjectMachine
    reverse_protocol TopSecretServer do
      state :unathenticated do
        on_enter do
          send_message LoginMessage.new('hello','hello')
        end
      end

      state :authenticated do
        on_enter AccessGrantedMessage do
          @secrets = 0
          send_message GetSmallSecretMessage.new
        end
        
        on_enter SecretMessage do
          @secrets += 1
          if @secrets == 1
            send_message GetBigSecretMessage.new
          else
            send_message LogoutMessage.new
            EventMachine.stop
          end
        end
      end
    end
  end
end

#    protocol do
#      state :unauthenticated do
#        on_send :login_message, :pending
#
#        on_enter do
#          send_message LoginMessage.new('hello','hello')
#        end
#      end
#      
#      state :pending do
#        on_recv :access_granted, :authenticated
#        on_recv :access_denied,  :unauthenticated
#      end
#
#      state :authenticated do
#        on_send [:get_fast_secret, :get_slow_secret], :receiving
#        on_send :logout, :unauthenticated
#
#        on_enter :access_granted do
#          @secrets = 0
#          send_message :get_fast_secret
#        end
#        
#        on_enter :secret_message do
#          @secrets += 1
#          if @secrets == 1
#            send_message :get_slow_secret
#          else
#            send_message :logout
#            EventMachine.stop
#          end
#        end
#      end
#
#      state :receiving do
#        on_recv :secret_message, :authenticated
#      end
#    end

