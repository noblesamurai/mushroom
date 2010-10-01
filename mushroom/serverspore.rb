class Mushroom::ServerSpore < Mushroom::Spore
	def initialize(mushroom, socket)
		super(mushroom, socket)
	end

	def read_ready!
		socket = @mushroom.server.accept
		@mushroom.spores[socket.to_i] = ClientSpore.new(@mushroom, socket)
	end
end

