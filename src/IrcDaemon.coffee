logger = require('winston')
net = require('net')

BufferedSocket = require('./BufferedSocket')
Channel = require('./Channel')
CommandExecutor = require('./CommandExecutor')
Irc = require('./Irc')
User = require('./User')

ERROR_CODES = Irc.ERROR_CODES

class IrcDaemon
	# Public: creates a daemon instance configured as per +options+.
	#
	# options - The object of options that should be used for configuring the daemon. Keys should include:
	#		  serverName    - The name of the server as it should be seen by IRC clients (e.g. the domain name of the server).
  #			listenAddress - The address the server should listen on (e.g. 127.0.0.1, somesite.tld, etc).
  #			listenPort    - The port the server should listen on.
  #     authTimeout   - The amount of time (in milliseconds) each client should have to authenticate before being 
  #                     disconnected. If anything other than a positive Number, a timeout will be not enforced.
  #     start         - True if the server should start immediately, false otherwise. Default: true.
	constructor: (@options) ->
		@users = {}
		@sockets = {}
		@channels = {}
		@handler = new CommandExecutor(this)

		@start() unless options.start is false

	# Public: Retrieve a User by nickname. The nickname will be normalized so that a user will be retrieved if it has 
	# the same canonicalized nick as that provided.
  #
  # nick - The nickname of the user that should be retrieved.
	#
	# Returns the +User+ with normalized nick +nick+, or null if no +User+ by the specified nick is known.
	getUser: (nick) ->
		@users[Irc.normalize(nick)]

 	# Public: Disconnect and remove a user. If a +User+ is provided, that user will be removed. If a nickname (+String+) 
 	# is specified, the user with the specified nickname will be removed (equivalent to +removeUser(getUser(nick))+).
 	# 
 	# user - The User to be removed, or the nickname of a user to be removed.
 	#
 	# Returns true if the user was both found and removed, false otherwise.
	removeUser: (user) ->
		usr = @users[Irc.normalize(user.nick)]
		if usr
			usr.getSocket().destroy()
			delete @users[Irc.normalize(user.nick)]
		!!usr

	# Public: Bind to the port and address specified in the constructor, and start accepting connections.
	start: ->
		port = @options.listenPort || 6667
		host = @options.listenAddress || null
		@server = net.createServer(@_acceptUser.bind(this))
		@server.listen(port, host)
		logger.info "Server started on port #{port} (host: #{host})"

	# Public: Create a channel with a given name. This is a shortcut for +addChannel(new Channel(name))+.
	# 
	# name - The name of the channel that should be created on this server.
	#
	# Returns the created channel.
	createChannel: (name) ->
		@channels[Irc.normalize(name)] = new Channel(this, name)

  # Public: get the +Channel+ on this server that has the normalized name +name+.
  # 
  # name - The name of the channel that should be retrieved.
  #
  # Returns the +Channel+ with a name of +name+, or +null+ if no such channel could be found.
	getChannelByName: (name) ->
		@channels[Irc.normalize(name)]

	# Public: Disconnect the specified user from the socket. This has the effect of both removing the user from the server
	# and killing the connection to the client.
	#
	# user - The +User+ that should be disconnected.
  #
  # Returns nothing.
	disconnect: (user) ->
		@_removeUserBySocket(user.socket)

	# Internal: Accept a connection, bind the necessary events on it, and do some bookkeeping.
	#
	# socket - The socket that should be turned into a User and added to the server.
	#
	# Returns nothing.
	_acceptUser: (socket) ->
		# Set the User as a property of the socket (kind of eww...) so that we can efficiently find the User when socket 
		# events happen.
		bufferedSocket = new BufferedSocket(socket)
		socket._coffircd_user = new User(this, bufferedSocket)
		bufferedSocket._coffircd_user = socket._coffircd_user

		logger.info "Received connection from #{socket.address().address}:#{socket.remotePort}"

		if @options.authTimeout > 0
			setTimeout(@_verifyUserRegistered(socket), @options.authTimeout)

		# Setup event handling for the user socket
		@_bindSocketEvents(bufferedSocket)

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

		socket.on 'line', (line) =>
			@_log 'debug', socket, "recv: #{line}"

			user = @_getUserBySocket(socket)

			command = @_parseCommand(line)

			if user.registered or command.command in ['NICK', 'USER']
				@handler.handle(user, command.command, command.arguments)
			else
				logger.info "Ignoring command '#{command.command}' from unregistered user"
				user.sendNumeric ERROR_CODES.ERR_UNKNOWNCOMMAND, "Unrecognized command: #{command.command}"

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
