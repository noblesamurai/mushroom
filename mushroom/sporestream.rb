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

require 'mushroom/mushroom'

class Mushroom::SporeStream
	class Aspect
		def initialize(stream, id)
			@stream, @id = stream, id
			@buffer = []
		end

		def write(data)
			@buffer << [Time.now, data]
			@stream.write_handler.call(@id, data) if @stream.write_handler
		end

		attr_reader :buffer
	end

	def initialize(aspects)
		@aspects = Array.new(aspects) {|i| Aspect.new(self, i)}
		@write_handler = nil
	end

	def method_missing(sym, *a, &b)
		return @aspects[$1.ord - ?a.ord] if sym.match(/^aspect_([a-z])$/) and a.length.zero? and not b
		super
	end

	attr_reader :aspects
	attr_accessor :write_handler
end
