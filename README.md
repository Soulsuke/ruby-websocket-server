# ruby-websocket-server

A simple ruby websocket server using TCPSocket.  

This is merely an implementation of the WebSocket protocol server side. May
become a gem whenever I'll have the time to polish it up, but since I couldn't
find anything like this anywhere else, I thought to share it as it is.  

It is designed to automatically handle ping requests sending back a pong.  

It doesn't (yet) expose events. It only allows to handle the received binary or
textual data.  

Multipart messages are already handled, and only FIN messages are exposed.  

Usage:  
```ruby
server = WebsocketServer.new 4000

loop do
  server.accept do |type, message|
    case type
      when :binary
        # Handle binary data
      when :text
        # Handle text data
    end

    # Send over a text reply to the client:
    server.send "reply"

    # If you want to manually close the connection with the client:
    server.close
  end
end
```

