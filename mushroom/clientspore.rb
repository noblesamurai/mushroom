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

	def pushback method, *args
		send "pushback_#{method}", *args
	end

	def pushback_delivery content
		@remote_buffer += content
		handle
	end

	def pushback_gone!
		@remote_gone = true
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
		body = "<html><head><title>#{num} #{ERRORS[num]}</title></head><body><h1>#{num} #{ERRORS[num]}</h1></body></html>"
		send_header "Content-Length", body.length
		send_last_header
		@socket.write body
	end

	def buffer_to_nl(buf=:@buffer)
		not_ready! if instance_variable_get(buf).index(?\n).nil?
		instance_variable_get(buf).slice!(0, instance_variable_get(buf).index(?\n) + 1)[0..-2]
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

			if port != 443 and !@mushroom.promiscuous_connect
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

		@fwd_headers = []
		transition_to :headers
	end

	state :headers do
		header = buffer_to_nl.strip
		next transition_to :data if header.length.zero?
		name, value = header.split(":", 2)
		value.gsub! /^\s*/, ''

		next if name.match(/^proxy/i)	# ignore proxy-related headers
		@fwd_headers << [name, value]
	end

	state :data do
		@data = if clh = @fwd_headers.find {|k,v| k.match(/^content-?length$/i)}
			clen = clh.last.to_i
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

		@remote_gone, @remote_buffer = false, ""
		@remote_spore = @mushroom.spores[@remote.to_io.fileno] = Mushroom::RemotePushbackSpore.new(@mushroom, @remote, self)

		transition_to :recv_status
	end

	state :recv_status do
		http_resp, http_code, http_reason = buffer_to_nl(:@remote_buffer).strip.split(" ", 3)
		@socket.write "#{http_resp} #{http_code} #{http_reason}\r\n"
		@socket.write "Connection: close\r\nProxy-Connection: close\r\n"
		@recv_length = nil
		transition_to :recv_headers
	end

	state :recv_headers do
		header = buffer_to_nl(:@remote_buffer).strip
		if header.length.zero?
			@socket.write "\r\n"
			next transition_to :recv_data
		end

		name, value = header.split(":", 2)
		value.gsub! /^\s*/, ''

		next if name.match(/^proxy/i) or name.match(/^connection$/i)
		@recv_length = value.to_i if name.match(/^content-?length$/i)
		@socket.write "#{name}: #{value}\r\n"
	end

	state :recv_data do
		next transition_to :recv_done if @recv_length.nil? or @recv_length.zero?
		not_ready! if @remote_buffer.length.zero?
		data = @remote_buffer
		@remote_buffer = ""

		@socket.write data
		@socket.flush
		@recv_length -= data.length
	end

	state :recv_done do
		@remote_spore.delete! rescue false
		delete!

		# If we don't declare ourselves as not ready, the
		# statemachine will think we continue to have things
		# to do here.
		not_ready!
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

		@sslrem = TCPSocket.new(@ssl_remote_uri, @ssl_remote_port)

		if @ssl_remote_port == 443
			# Masquerade SSL.
			ctx = OpenSSL::SSL::SSLContext.new("SSLv23_server")
			keybundle = @mushroom.get_cert_for.call(@ssl_remote_uri)
			ctx.cert = OpenSSL::X509::Certificate.new(keybundle[:cert])
			ctx.key = OpenSSL::PKey::RSA.new(keybundle[:key])

			@socket = OpenSSL::SSL::SSLSocket.new(@socket, ctx)	# !!
			@socket.accept

			@sslrem = OpenSSL::SSL::SSLSocket.new(@sslrem.to_io)
			@sslrem.connect
		end

		@mushroom.spores[@sslrem.to_io.fileno] = Mushroom::RemoteForwarderSpore.new(@mushroom, @sslrem, @socket)

		# BILATERAL COMMUNICATIONS WITH THE PRESIDENT Y'KNOW WHAT I'M SAYIN'
		transition_to :ssl_comm
	end

	state :ssl_comm do
		not_ready! if @buffer.length.zero?
		@sslrem.write @buffer
		@buffer = ""
	end
end

