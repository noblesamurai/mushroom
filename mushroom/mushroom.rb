class Mushroom
	class AlreadyDoingThatError < StandardError; end
	class NotDoingThatError < StandardError; end

	class Spore
		def initialize(mushroom, socket)
			@mushroom, @socket = mushroom, socket
		end

		def to_io; @socket.to_io; end
	end

	def initialize(opts={})
		@port = opts[:port] || 7726
	end

	def start!
		raise AlreadyDoingThatError if @started

		@started = true
		@server = TCPServer.new(@port)
		@spores = {@server.to_i => ServerSpore.new(self, @server)}
		@thread = Thread.start { _loop }
	end

	def stop!
		raise AlreadyDoingThatError if not @started
	
		@thread.kill
		@server.close
		@started, @server, @thread, @spores = false
	end

	def join
		raise NotDoingThatError if not @started
		@thread.join
	end

	attr_accessor :server, :spores

	private

	def _loop
		IO.select(@spores.values).first.each &:read_ready! while @started
	end
end
