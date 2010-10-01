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

require 'mushroom/states'
require 'openssl'

class Mushroom::ClientSpore < Mushroom::Spore
	ERRORS = {
		200 => "OK",
		403 => "Forbidden",
		404 => "File Not Found",
		505 => "HTTP Version Not Supported",
	}
	state_machine! :request

	def initialize(mushroom, socket)
		super(mushroom, socket)
		@buffer = ""
	end

	def read_ready!
		begin
			@buffer += @socket.readpartial 8192
		rescue EOFError
			delete!
			return
		end

		handle
	end

	def send_status ver, num
		@socket.write "#{%w(HTTP/1.0 HTTP/1.1).include?(ver) ? ver : "HTTP/1.1"} #{num} #{ERRORS[num]}\r\n"
	end

	def send_header name, val
		@socket.write "#{name}: #{val}\r\n"
	end

	def send_error ver, num
		send_status ver, num
		send_header "Content-Length", 0
	end

	def buffer_to_nl
		not_ready! if @buffer.index(?\n).nil?
		@buffer.slice!(0, @buffer.index(?\n) + 1)[0..-2]
	end

	state :request do
		method, uri, http_ver = buffer_to_nl.split(" ", 3)

		if not %w(HTTP/1.0 HTTP/1.1).include? http_ver
			send_error http_ver, 505
			next delete!
		end

		if method == "CONNECT"
			uri, port = uri.split(":", 2)
			port = port.to_i

			if port != 443
				send_error http_ver, 403
				next delete!
			end

			next transition_now :ssl_begin, uri, port
		end
		
		p method, uri, http_ver
		transition_to :headers
	end

	state :ssl_begin do
		ctx = OpenSSL::SSL::SSLContext.new("SSLv23_server")
		ctx.cert = OpenSSL::X509::Certificate.new(@mushroom.x509)
		ctx.key = OpenSSL::PKey::RSA.new(@mushroom.rsakey)

		@socket = OpenSSL::SSL::SSLSocket.new(@socket, ctx)	# !!
		@socket.connect

		remote = TCPSocket.new(uri, port)
		@sslrem = OpenSSL::SSL::SSLSocket.new(remote.to_io)
		@sslrem.connect
		@mushroom.spores[@sslrem.to_i] = Mushroom::RemoteSpore.new(@mushroom, @sslrem, @socket)

		# BILATERAL COMMUNICATIONS WITH THE PRESIDENT Y'KNOW WHAT I'M SAYIN'
		transition_to :ssl_comm
	end

	state :ssl_comm do
		@sslrem.write @buffer
		@buffer = ""
	end
end

