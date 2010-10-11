# Copyright 2010 Noble Samurai
# 
# mushroom is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# mushroom is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with mushroom.  If not, see <http://www.gnu.org/licenses/>.

class Mushroom
	class AlreadyDoingThatError < StandardError; end
	class NotDoingThatError < StandardError; end

	class Spore
		def initialize(mushroom, socket)
			@mushroom, @socket = mushroom, socket
			@i = @socket.to_io.to_i
		end

		def to_io; @socket.to_io; end
		def to_i; @i; end

		def delete!
			@mushroom.spores.delete to_i
			@socket.flush rescue false
			@socket.close rescue false
		end
	end

	OPTIONS_DEFAULTS = {
		:port 					=> 7726,
		:get_cert_for			=> nil,
		:promiscuous_connect	=> false,
		:stream_receiver		=> nil,
	}

	def initialize(opts={})
		OPTIONS_DEFAULTS.each do |k,v|
			instance_variable_set "@#{k}", opts.include?(k) ? opts[k] : v
		end
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

	def new_stream!(stream)
		@stream_receiver.call stream if @stream_receiver
	end

	attr_accessor :server, :port, :spores, :get_cert_for, :promiscuous_connect

	private

	def _loop
		while @started
			ready = IO.select(@spores.values).first
			ready.each do |r|
				begin
					r.read_ready!
				rescue => e
					puts "Encountered: #{e.inspect} at #{e.backtrace.first}"
					r.delete!
				end
			end
		end
	end
end
