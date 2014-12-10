logger = require('winston')

Irc = require('./Irc')
ERROR_CODES = Irc.ERROR_CODES

class User
  constructor: (@server, @socket) ->
    @serverName = 'localhost'
    @serverVersion = '0.1.0-alpha1'
    @nick = null
    @user = null
    @realname = null
    @hostname = @socket.address().address
    @channels = {}

    @address = @socket.address().address
    @port = @socket.address().port

    @registered = false

  getFullHost: ->
    "#{@nick}!#{@user}@#{@hostname}"

  register: ->
    return if @registered
    return unless @user && @nick && @realname

    @sendNumeric(ERROR_CODES.RPL_WELCOME, "Welcome to coffircd #{@getFullHost()}")
    @sendNumeric(ERROR_CODES.RPL_YOURHOST, "Your host is #{@serverName}, running version #{@serverVersion}")
    @sendNumeric(ERROR_CODES.RPL_CREATED, "This server was created at some point")
    @sendNumeric(ERROR_CODES.RPL_MYINFO, "#{@serverName} #{@serverVersion}")

    @registered = true

  hasInvite: (channel) ->
    false

  sendWithMessage: (command, args..., message) ->
    msg = [command].concat(args)
    msg += ' :' + message if message
    @_sendRaw(msg)

  sendNumeric: (code, pieces...) ->
    logger.debug "Sending numeric code #{code} to #{@nick} with args #{pieces.join(' ')}"
    @_sendRaw ":#{@serverName} #{('000' + code).slice(-3)} #{@nick || '*'} #{pieces.join(' ')}"

  sendCommandFromUser: (user, command, args..., message) ->
    msg = [':' + user.getFullHost(), command].concat(args).join(' ')
    msg += ' :' + message if message
    @_sendRaw msg

  sendError: (errorCode, args..., message) ->
    @sendNumeric(errorCode, args.concat(':' + message).join(' '))

  addChannel: (channel) ->
    @channels[Irc.normalize(channel)] = channel

  partChannel: (channel, msg) ->
    name = Irc.normalize(channel)
    ch = @channels[name]
    return unless ch
    ch.part(channel, msg) if ch
    delete channels[name]

  join: (channel) ->
    channel.join(this)
    @channels[Irc.normalize(channel.name)] = channel

  quit: (msg) ->
    (channel.quit(this, msg)) for _, channel of @channels
    @channels = {}

  privmsg: (sender, msg, target = @nick) ->
    @sendCommandFromUser(sender, 'PRIVMSG', target, msg)

  # Public: remove the link between this user and the given channel name. 
  removeChannel: (name) ->
    ch = @channels[Irc.normalize(name)]
    if ch
      ch.part(this)
      delete @channels[Irc.normalize(name)]

  _prefix: ->
    ':' + @nick + '!' + @name + '@' + @hostname

  _sendRaw: (msg, handler) ->
    logger.debug "Sending #{@nick}: #{msg}"
    @socket.write(msg + "\r\n", handler)

module.exports = User
