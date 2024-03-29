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

## RemoteForwarderSpore
# Just forwards data back to a socket.
#

class Mushroom::RemoteForwarderSpore < Mushroom::Spore
	def initialize(mushroom, socket, front, aspect)
		super(mushroom, socket)
		@front, @aspect = front, aspect
	end

	def read_ready!
		@front.write(begin
			data = @socket.readpartial 8192
		rescue EOFError
			delete!
			return
		end)
		@aspect.write data
	end
end

