EventEmitter = require('events').EventEmitter

normalizeLineBreaks = (str) ->
	str.replace("\r\n", "\n").replace("\r", "\n")

class BufferedSocket
	constructor: (@socket) ->
		@emitter = new EventEmitter
		@buffer = ''
		this._registerLineReader()

	address: ->
		@socket.address()

	end: ->
		@socket.end()

	destroy: ->
		@socket.destroy()

	write: (data, handler) ->
		@socket.write(data, handler)

	on: (event, handler) ->
		if event is 'readLine'
			@emitter.addListener(event, handler)
		else
			@socket.addListener(event, handler)

	_registerLineReader: ->
		@socket.on 'data', (data) =>
			# Normalize the new data to use \n, then push it onto the buffer
			@buffer += normalizeLineBreaks(data.toString())

			# Split the buffer out into lines
			lines = @buffer.split("\n")
			
			# If the buffer has a line break in it, we'll get at least 2 lines
			return unless lines.length > 1

			# The last line is an incomplete line, so we can't flush it yet
			(@emitter.emit 'readLine', line.trim()) for line in lines.slice(0, lines.length - 1)

			# We do need to buffer the last line though
			@buffer = lines[lines.length - 1]

module.exports = BufferedSocket
