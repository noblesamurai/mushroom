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
require 'uri'

class Mushroom::ClientSpore < Mushroom::Spore
	ERRORS = {
		200 => "OK",
		403 => "Forbidden",
		404 => "File Not Found",
		501 => "Not Implemented",
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

		if not %w(OPTIONS GET HEAD POST PUT).include? @method
			send_error @http_ver, 501
			next delete!
		end

		@fwd_headers = {}
		transition_to :headers
	end

	state :headers do
		header = buffer_to_nl.strip
		next transition_to :data if header.length.zero?
		name, value = header.split(":", 2)
		value.gsub! /^\s*/, ''

		next if name.match(/^proxy/i)	# ignore proxy-related headers
		@fwd_headers[name] = value
	end

	state :data do
		@data = if clh = @fwd_headers.keys.find {|k| k.match(/^content-?length$/i)}
			clen = @fwd_headers[clh].to_i
			not_ready! if @buffer.length < clen
			@buffer.slice! 0, clen
		end
		transition_to :outbound
	end

	state :outbound do
		uri = URI.parse(@uri)
		@remote = TCPSocket.new(uri.host, uri.port)
		@remote.write "#@method #{uri.request_uri} #@http_ver\r\n"
		@fwd_headers.each do |k,v|
			@remote.write "#{k}: #{v}\r\n"
		end
		@remote.write "\r\n#@data"
		@remote.flush

		@mushroom.spores[@remote.to_io.fileno] = Mushroom::RemoteSpore.new(@mushroom, @remote, @socket)

		transition_to :comm
	end

	state :comm do
		not_ready! if @buffer.length.zero?
		puts "Uh oh, tried to write more! #@buffer"
		@remote.write @buffer
		@buffer = ""
	end


	state :ssl_headers do
		header = buffer_to_nl.strip
		next transition_to :ssl_begin if header.length.zero?
		name, value = header.split(":", 2)
		value.gsub! /^\s*/, ''
	end

	state :ssl_begin do
		send_status @http_ver, 200
		send_last_header

		ctx = OpenSSL::SSL::SSLContext.new("SSLv23_server")
		keybundle = @mushroom.get_cert_for.call(@ssl_remote_uri)
		ctx.cert = OpenSSL::X509::Certificate.new(keybundle[:cert])
		ctx.key = OpenSSL::PKey::RSA.new(keybundle[:key])

		@socket = OpenSSL::SSL::SSLSocket.new(@socket, ctx)	# !!
		@socket.accept

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

