require 'socket'
require 'yaml'
require 'active_support'

Dir[File.dirname(__FILE__) + '/ext/*.rb'].each { |f| require f }

require File.dirname(__FILE__) + "/summer/handlers"

module Summer
  class Connection
    include Handlers
    attr_accessor :connection, :ready, :started, :config, :server, :port
    def initialize(server, port=6667, dry=false)
      @ready = false
      @started = false

      @server = server
      @port = port

      load_config
      connect!
      
      unless dry
        loop do
          startup! if @ready && !@started
          parse(@connection.gets)
        end
      end
    end

    private

    def load_config
      @config = HashWithIndifferentAccess.new(YAML::load_file(File.dirname($0) + "/config/summer.yml"))
    end

    def connect!
      @connection = TCPSocket.open(server, port)      
      response("USER #{config[:nick]} #{config[:nick]} #{config[:nick]} #{config[:nick]}")
      response("NICK #{config[:nick]}")
    end


    # Will join channels specified in configuration.
    def startup!
      (@config[:channels] << @config[:channel]).compact.each do |channel|
        join(channel)
      end
      @started = true
      call(:did_start_up) if respond_to?(:did_start_up)
    end

    # Go somewhere.
    def join(channel)
      response("JOIN #{channel}")
    end

    # Leave somewhere
    def part(channel)
      response("PART #{channel}")
    end


    # What did they say?
    def parse(message)
      puts "<< #{message.strip}"
      words = message.split(" ")
      sender = words[0]
      raw = words[1]
      channel = words[2]
      # Handling pings
      if /^PING (.*?)\s$/.match(message)
        response("PONG #{$1}")
      # Handling raws
      elsif /\d+/.match(raw)
        send("handle_#{raw}", message) if raws_to_handle.include?(raw)
      # Privmsgs
      elsif raw == "PRIVMSG"
        message = words[3..-1].clean
        # Parse commands
        if /^!(\w+)\s*(.*)/.match(message) && respond_to?("#{$1}_command")
          call("#{$1}_command", parse_sender(sender), channel, $2)
        # Plain and boring message
        else
          method = channel == me ? :private_message : :channel_message
          call(method, parse_sender(sender), channel, message)
        end
      # Joins
      elsif raw == "JOIN"
        call(:join, parse_sender(sender), channel)
      elsif raw == "PART"
        call(:part, parse_sender(sender), channel, words[3..-1].clean)
      elsif raw == "QUIT"
        call(:quit, parse_sender(sender), words[2..-1].clean)
      elsif raw == "KICK"
        call(:kick, parse_sender(sender), channel, words[3], words[4..-1].clean)
      elsif raw == "MODE"
        call(:mode, parse_sender(sender), channel, words[3], words[4..-1].clean)
      end

    end

    def parse_sender(sender)
      nick, hostname = sender.split("!")
      { :nick => nick.clean, :hostname => hostname }
    end

    # These are the raws we care about.
    def raws_to_handle
      ["422", "376"]
    end

    def privmsg(message, to)
      response("PRIVMSG #{to} :#{message}")
    end

    # Output something to the console and to the socket.
    def response(message)
      puts ">> #{message.strip}"
      @connection.puts(message)
    end

    def me
      config[:nick]
    end

  end

end
