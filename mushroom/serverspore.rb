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

class Mushroom::ServerSpore < Mushroom::Spore
	def initialize(mushroom, socket)
		super(mushroom, socket)
	end

	def read_ready!
		socket = @mushroom.server.accept
		@mushroom.spores[socket.to_i] = ClientSpore.new(@mushroom, socket)
	end
end

