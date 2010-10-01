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
		end

		def to_io; @socket.to_io; end
		def to_i; to_io.to_i; end

		def delete!
			@mushroom.spores.delete to_i
			begin
				@socket.flush
				@socket.close
			rescue; end
		end
	end

	def initialize(opts={})
		@port = opts[:port] || 7726
		@x509 = opts[:x509] || nil
		@rsakey = opts[:rsakey] || nil
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

	attr_accessor :server, :port, :spores, :x509, :rsakey

	private

	def _loop
		while @started
			ready = IO.select(@spores.values).first
			ready.each do |r|
				begin
					r.read_ready!
				rescue => e
					p e
					r.delete!
				end
			end
		end
	end
end
