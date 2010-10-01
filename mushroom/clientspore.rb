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

	def send_last_header
		@socket.write "\r\n"
	end

	def send_error ver, num
		send_status ver, num
		body = "<html><head><title>#{num} #{ERRORS[num]}</title></head><body><h1>#{num} #{ERRORS[num]}</body></html>"
		send_header "Content-Length", body.length
		send_last_header
		@socket.write body
	end

	def buffer_to_nl
		not_ready! if @buffer.index(?\n).nil?
		@buffer.slice!(0, @buffer.index(?\n) + 1)[0..-2]
	end

	state :request do
		@method, @uri, @http_ver = buffer_to_nl.strip.split(" ", 3)

		p [@method, @uri, @http_ver]

		if not %w(HTTP/1.0 HTTP/1.1).include? @http_ver
			send_error @http_ver, 505
			next delete!
		end

		if @method == "CONNECT"
			uri, port = @uri.split(":", 2)
			port = port.to_i

			if port != 443
				send_error @http_ver, 403
				next delete!
			end

			@ssl_remote_uri, @ssl_remote_port = uri, port
			next transition_to :ssl_headers
		end

		transition_to :headers
	end

	state :ssl_headers do
		header = buffer_to_nl.strip
		next transition_to :ssl_begin if header.length.zero?
		name, value = header.split(":", 2)
		value.gsub! /^\s*/, ''
		p({name => value})
	end

	state :ssl_begin do
		send_status @http_ver, 200
		send_last_header

		puts "forming context"
		ctx = OpenSSL::SSL::SSLContext.new("SSLv23_server")
		ctx.cert = OpenSSL::X509::Certificate.new(@mushroom.x509)
		ctx.key = OpenSSL::PKey::RSA.new(@mushroom.rsakey)

		puts "going to accept"
		puts "here goes"
		ssls = OpenSSL::SSL::SSLSocket.new(@socket, ctx)	# !!
		r = ssls.accept
		puts "ACCEPTED"
		ssls.write "HTTP/1.1 200 OK\r\nContent-length: 10\r\n\r\n01234501234\r\n"
		ssls.close

		puts "outbounding to #{@ssl_remote_uri}:#{@ssl_remote_port}"
		remote = TCPSocket.new(@ssl_remote_uri, @ssl_remote_port)
		@sslrem = OpenSSL::SSL::SSLSocket.new(remote.to_io)
		@sslrem.connect
		@mushroom.spores[@sslrem.to_io.fileno] = Mushroom::RemoteSpore.new(@mushroom, @sslrem, @socket)

		# BILATERAL COMMUNICATIONS WITH THE PRESIDENT Y'KNOW WHAT I'M SAYIN'
		transition_to :ssl_comm
	end

	state :ssl_comm do
		not_ready! if @buffer.length.zero?
		@sslrem.write @buffer
		@buffer = ""
	end
end

