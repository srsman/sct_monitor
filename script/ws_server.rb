# Dont run this script directly
# usage: rails r script/ws_server_ctrl.rb start

require 'trollop'
require 'eventmachine'
require 'em-websocket'
require 'json'
require 'active_support/core_ext/object/blank'

opts = Trollop::options do
  opt :debug, "Debug mode", :short => 'd'
end

def send_result(socket, success=false, msg='')
  result = {
    :success => success,
    :msg => msg
  }
  
  socket.send(JSON.dump result)
end

EventMachine.run {
  @channels = {}
  @controllers = {}
  @sockets = {}
  
  EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 1337, :debug => opts[:debug]) do |ws|
    ws.onopen {
      channel = sid = false
      
      ws.onmessage { |msg|
        params = JSON.load(msg)
        
        case params['method']
        when 'register' 
          uid = params['uid'].to_sym    
          @channels[uid] = EM::Channel.new unless @channels.has_key? uid
          channel = @channels[uid]
          sid = channel.subscribe { |msg| ws.send msg }
          @sockets[sid] = ws
          
          if params['password'].presence # FIXME
            if 'demo' == params['password'].downcase
              if (@controllers.has_key? channel.object_id) && 
                 (@controllers[channel.object_id] != sid)
                old_ctrlr = @controllers[channel.object_id]
                send_result @sockets[old_ctrlr], true, 'control off'
              end
              
              @controllers[channel.object_id] = sid
              send_result ws, true, 'control on'
            else
              send_result ws, false, 'wrong controller password'
            end
          else
            send_result ws, true
          end
          
        when 'control_on'
          if params['password'].presence && 
             ('demo' == params['password'].downcase)
            if (@controllers.has_key? channel.object_id) && 
               (@controllers[channel.object_id] != sid)
              old_ctrlr = @controllers[channel.object_id]
              send_result @sockets[old_ctrlr], true, 'control off'
            end
            
            @controllers[channel.object_id] = sid
            send_result ws, true, 'control on'
          else
            send_result ws, false, 'wrong controller password'
          end
          
        when 'control_off'
          if @controllers[channel.object_id] == sid
            @controllers.delete channel.object_id
            channel.push JSON.dump({
              :success => true,
              :msg => 'control off'
            })
          else
            send_result ws, false, 'you\'re not controller.'
          end
          
        when 'command'
          if sid == @controllers[channel.object_id]
            channel.push JSON.dump(params['data'])
# send_result ws, true
          else
            send_result ws, false, 'this client is not controller'
          end
        end
      }
      
      ws.onclose {
        if channel && sid
          channel.unsubscribe(sid)
          
          if (@controllers.has_key? channel.object_id) && 
             (@controllers[channel.object_id] == sid)
             
            @controllers.delete channel.object_id            
          end
        end
      }
    }
  end
}

