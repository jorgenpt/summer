require 'socket'
require 'yaml'
require 'active_support/hash_with_indifferent_access'
require 'active_support/core_ext/object/try'

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
          message = @connection.gets
          if message
            parse(message)
          else
            break
          end
        end
      end
    end

    private

    def load_config
      @config = HashWithIndifferentAccess.new(YAML::load_file(File.dirname($0) + "/config/summer.yml"))
      @config[:channels] ||= []
      @config[:channels] << @config.delete(:channel) if @config[:channel]
    end

    def connect!
      @connection = TCPSocket.open(server, port)
      response("USER #{config[:nick]} #{config[:nick]} #{config[:nick]} #{config[:nick]}")
      response("NICK #{config[:nick]}")
    end


    # Will join channels specified in configuration.
    def startup!
      nickserv_identify if @config[:nickserv_password]
      config[:channels].each do |channel|
        join(channel)
      end
      @started = true
      really_try(:did_start_up) if respond_to?(:did_start_up)
    end

    def nickserv_identify
      privmsg("nickserv", "register #{@config[:nickserv_password]} #{@config[:nickserv_email]}")
      privmsg("nickserv", "identify #{@config[:nickserv_password]}")
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
      puts "<< #{message.to_s.strip}"
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
          really_try("#{$1}_command", parse_sender(sender), channel, $2)
        # Plain and boring message
        else
          sender = parse_sender(sender)
          method, channel = channel == me ? [:private_message, sender[:nick]]  : [:channel_message, channel]
          really_try(method, sender, channel, message)
        end
      # Joins
      elsif raw == "JOIN"
        really_try(:join, parse_sender(sender), channel)
      elsif raw == "PART"
        really_try(:part, parse_sender(sender), channel, words[3..-1].clean)
      elsif raw == "QUIT"
        really_try(:quit, parse_sender(sender), words[2..-1].clean)
      elsif raw == "KICK"
        really_try(:kick, parse_sender(sender), channel, words[3], words[4..-1].clean)
        join(channel) if words[3] == me && config[:auto_rejoin]
      elsif raw == "MODE"
        really_try(:mode, parse_sender(sender), channel, words[3], words[4..-1].clean)
      elsif raw == "TOPIC"
        really_try(:topic, parse_sender(sender), channel, words[3..-1].clean)
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

    def log(message)
      File.open(config[:log_file]) { |file| file.write(message) } if config[:log_file]
    end

  end

end
