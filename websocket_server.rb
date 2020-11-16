require "digest"
require "socket"



class WebsocketServer

  #############################################################################
  ### Attributes                                                            ###
  #############################################################################
  attr_reader :server
  attr_reader :connection



  #############################################################################
  ### Public methods                                                        ###
  #############################################################################

  # Constructor.
  # Takes the socket port as parameter.
  def initialize( port )
    # Setup the server:
    @server = TCPServer.new port
  end



  # Starts listening for connections on the websocket, handles handshake and
  # reads data.
  # Takes a block to handle the received data.
  def accept( &block )
    # Start by accepting a connection:
    @connection = @server.accept

    # The first request ever should be the handshake:
    http_request = ""
    while line = @connection.gets and line != "\r\n" do
      http_request += line
    end
    
    # If it contains a secret key, use it to send the appropriate
    # handshake response:
    if matches = http_request.match( /^Sec-WebSocket-Key: (\S+)/ ) then
      @connection.write "HTTP/1.1 101 Switching Protocols\n" +
        "Upgrade: websocket\n" +
        "Connection: Upgrade\n" +
        "Sec-WebSocket-Accept: " +
          Digest::SHA1.base64digest(
            [ matches[ 1 ], "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" ].join
          ) +
          "\n\n"
    
    # If it doesn't, close the connection and move on:
    else
      @connection.close
      return
    end

    # Now, let's start reading the real data from the websocket:
    loop do
      type, data = read true

      # Stop on connection closing:
      break if type == :closed

      # Make sure the block can handle the textual or binary data:
      if [ :text, :binary ].include? type then
        yield type, data
      end
    end
  end



  # Sends data via the websocket.
  def send( data )
    # Data to send over:
    to_send = [ 0b10000001 ]

    # Payload size to use:
    size = "#{data}".size

    # Standard payload:
    if size < 126 then
      @connection.write [ 0b10000001, size, "#{data}" ].pack "CCA#{size}"

    # 16bit extended payload size:
    elsif size <= 65535 then
      @connection.write [ 0b10000001, 126, size, "#{data}" ].pack "CCCA#{size}"

    # 32 bit extended payload size:
    else
      @connection.write [ 0b10000001, 127, size, "#{data}" ].pack "CCCA#{size}"
    end
  end



  # Disconnect the websocket
  def close
    @connection.close
  end



  #############################################################################
  ### Private methods                                                       ###
  #############################################################################

  private

  # Gets a bytes as a string, always having 8 characters:
  def get_byte
    byte = @connection.getbyte.to_s 2
    byte = "0" * (8 - byte.length) + byte
  end



  # Reads data from the websocket.
  # Returns the type and the data read:
  def read( can_repeat )
    # Read the first byte containing final and opcode flags:
    byte = get_byte
    final = byte[ 0 ].to_i
    opcode = byte[ 4..7 ].to_i 2

    # Read the second byte containing the masked flag and payload size:
    byte = get_byte
    masked = byte[ 0 ].to_i
    payload_size = byte[ 1..7 ].to_i 2

    # If payload size is 126 or 127, we gotta use the extended payload size:
    if 126 == payload_size then
      payload_size = 2.times.map { get_byte }.join( "" ).to_i 2
    elsif 127 == payload_size then
      payload_size = 8.times.map { get_byte }.join( "" ).to_i 2
    end

    # Support variables:
    mask = nil

    # If the data is masked, get the mask:
    if masked then
      mask = 4.times.map { @connection.getbyte }
    end

    # Get the data:
    data = payload_size.times.map { @connection.getbyte }

    # Unmask the data if needed:
    if masked then
      data = data.each_with_index.map { |byte, i| byte ^ mask[ i % 4 ] }
    end

    # If the message wasn't final and we can repeat, read the next one(s):
    if 0 == final and can_repeat then
      c_type = nil
      c_data = nil

      # Keep reading until we'll get a final continuated result:
      while c_type != :cont_1 do
        c_type, c_data = read false
        data += c_data
      end 
    end

    # Conditional return:
    case opcode
      # Continuation data:
      when 0
        return :"cont_#{final}", data

      # Textual data:
      when 1
        return :text, data.pack( "C*" ).force_encoding( "utf-8" )

      # Binary data:
      when 2
        return :binary, data

      # Close connection:
      when 8
        return :closed, nil

      # Pong request:
      when 9
        pong
        return :ping, nil

      # Every other case:
      else
        return opcode, data
    end
  end



  # Sends a pong message.
  def pong
    to_send = [ 0b10001010, 0, "" ]
    @connection.write to_send.pack "CCA0"
  end

end

