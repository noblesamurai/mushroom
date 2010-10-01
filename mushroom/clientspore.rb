class Mushroom::ClientSpore < Mushroom::Spore
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

		p @buffer
	end

	def delete!
		@mushroom.spores.delete @socket.to_i
		begin
			@socket.close
		rescue; end
	end
end

