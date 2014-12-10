net = require('net')
logger = require('winston')

BufferedSocket = require('./BufferedSocket')
Channel = require('./Channel')
CommandExecutor = require('./CommandExecutor')
Irc = require('./Irc')
User = require('./User')

ERROR_CODES = require('./Irc').ERROR_CODES

class IrcDaemon
	constructor: (@port, @host = null) ->
		@users = {}
		@sockets = {}
		@channels = {}
		@handler = new CommandExecutor(this)

	hasUser: (nick) ->
		return !!@users[nick]

	removeUser: (user) ->
		usr = @users[Irc.normalize(user.nick)]
		if usr
			usr.getSocket().destroy()
			delete @users[Irc.normalize(user.nick)]

	acceptUser: (socket) ->
		# Book keeping
		bufferedSocket = new BufferedSocket(socket)
		socket._coffircd_user = new User(this, bufferedSocket)
		bufferedSocket._coffircd_user = socket._coffircd_user

		logger.info "Received connection from #{socket.address().address}:#{socket.remotePort}"

		# Give the user 10 seconds to register
		setTimeout @_verifyUserRegistered(socket), 10000

		# Setup event handling for the user socket
		@_bindSocketEvents bufferedSocket

	start: ->
		@server = net.createServer @acceptUser.bind(this)
		@server.listen(@port, @host)
		logger.info "Server started on port #{@port} (host: #{@host})"

	createChannel: (name) ->
		@channels[Irc.normalize(name)] = new Channel(this, name)

	getChannelByName: (name) ->
		@channels[Irc.normalize(name)]

	getUserByNick: (nick) ->
		@users[Irc.normalize(nick)]

	disconnect: (user) ->
		@_removeUserBySocket(user.socket)

	_getUserBySocket: (socket) ->
		socket._coffircd_user

	_verifyUserRegistered: (socket) ->
		return =>
			user = @_getUserBySocket(socket)
			unless user and user.registered
				@_log 'info', socket, 'disconnect due to auth timeout'
				@_removeUserBySocket(socket)

	_removeUserBySocket: (socket) ->
		fd = socket._handle
		user = @users[fd]
		delete @users[fd] if user
		delete @sockets[user.getNick()] if user
		socket.destroy()

	_parseCommand: (line) ->
		# Commands are typically of the format: "cmd arg1 arg2 :some message with spaces"
		[commandWithArgs, message] = line.split(' :', 2)
		commandPieces = commandWithArgs.split(' ')
		commandPieces.push(message) if message
		{command: commandPieces.shift().toUpperCase(), arguments: commandPieces}

	_bindSocketEvents: (socket) ->
		socket.on 'close', (hasError) =>
			@_removeUserBySocket(socket)

		socket.on 'readLine', (line) =>
			@_log 'debug', socket, "recv: #{line}"

			user = @_getUserBySocket(socket)

			command = @_parseCommand(line)

			unless user.registered or command.command in ['NICK', 'USER']
				logger.info "Ignoring command '#{command.command}' from unregistered user"
				user.sendNumeric ERROR_CODES.ERR_UNKNOWNCOMMAND, "Unregognized command: #{command.command}"
				return

			if @handler.handles(command.command)
				target = command.command
			else
				target = 'unknown'

			@handler[target](user, command.arguments, command.command)

		socket.on 'error', (err) =>
			@_removeUserBySocket(socket)
			logger.info 'Unexpected error on server socket', err

	_log: (level, socket, msg) ->
		socket = socket.socket if socket.socket
		address = socket.address()
		if address
			msg = "#{address.address}:#{address.port} -- #{msg}"
		logger[level](msg)

module.exports = IrcDaemon
