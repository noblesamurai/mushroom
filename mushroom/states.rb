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

class Class
	def state_machine!(start)
		include StateMachine
		@_statemachine_default = start
		@_statemachine_states = {}
	end
end

module StateMachine
	module Extends
		def state(name, &method)
			if method
				@_statemachine_states[name] = method
			else
				@_statemachine_states[name]
			end
		end

		def default_state
			@_statemachine_default
		end
	end

	def self.included(mc)
		mc.extend Extends
	end

	def handle(*args)
		@state ||= self.class.default_state
		raise NameError, "state \"#@state\" not defined" if self.class.state(@state).nil?

		@_statemachine_notready = Object.new
		catch @_statemachine_notready do
			instance_exec *args, &self.class.state(@state)
		end
	end

	def transition_to(state)
		@state = state
	end

	def transition_now(state, *args)
		transition_to state
		handle *args
	end

	def not_ready!
		throw @_statemachine_notready
	end
end

