logger = require('winston')

Irc = require('./Irc')
ERROR_CODES = Irc.ERROR_CODES

class CommandExecutor
  constructor: (@server) ->

  NICK: (user, args) ->
    #args: nick
    console.log(args)
    if args.length isnt 1
      return user.sendError(ERROR_CODES.NICK_MISSING_NICK, 'nick must be provided')
    user.nick = args[0]
    user.sendWithMessage('NICK', user.nick)
    user.register()

  USER: (user, args) ->
    # args: user, hostname, unused, realname
    if args.length isnt 4
      return user.sendError(ERROR_CODES.ERR_NEEDMOREPARAMS, 'USER', 'Wrong number of parameters')
    if user.registered
      return user.sendError(ERROR_CODES.ERR_ALREADYREGISTRED, 'You are already registered')
    user.user = args[0]
    user.realname = args[3]
    user.register()

  unknown: (user, args, command) ->
    logger.info "Received unknown command: #{command}"

  handles: (command) ->
    typeof this[command] is 'function'

  handle: (user, command, args) ->
    this[command](user, args, command) if this[command]

  JOIN: (user, args) ->
    # JOIN ( <channel> *( "," <channel> ) [ <key> *( "," <key> ) ] ) / "0"
    # Responses: ERR_NEEDMOREPARAMS, ERR_BANNEDFROMCHAN, ERR_INVITEONLYCHAN,
    # ERR_BADCHANNELKEY, ERR_CHANNELISFULL, ERR_BADCHANMASK, ERR_NOSUCHCHANNEL, ERR_TOOMANYCHANNELS,
    # ERR_TOOMANYTARGETS, ERR_UNAVAILRESOURCE, RPL_TOPIC
    if args.length is 0 or args.length > 2
      user.sendError(ERROR_CODES.ERR_NEEDMOREPARAMS, 'JOIN', 'Wrong number of parameters')
    else
      if args[0] is '0'
        # TODO Quit all channels the user is in
      else
        channels = args[0].split(',')
        keys = (args[1] || '').split(',')
        (@_joinChannel user, channel, keys[idx]) for idx, channel of channels

  PART: (user, args) ->
    channels = (args[0] || '').split(',')
    message = (args[1] || '')
    if channels.length is 0
      user.sendError(ERROR_CODES.ERR_NEEDMOREPARAMS, 'PART', 'Wrong number of parameters')
    else
      channels.forEach (channelName) =>
        channel = @server.getChannelByName(channelName)
        if channel
          if channel.hasUser(user)
            channel.part(user, message)
          else
            user.sendError(ERROR_CODES.ERR_NOTONCHANNEL, 'PART', channelName, "You are not in the channel #{channelName}")
        else
          user.sendError(ERROR_CODES.ERR_NOSUCHCHANNEL, 'PART', channelName, "The channel #{channelName} does not exist")

  PRIVMSG: (user, args) ->
    # PRIVMSG <nick|channel> :<text to be sent>
    # Responses: ERR_NORECIPIENT, ERR_NOTEXTTOSEND, ERR_CANNOTSENDTOCHAN, ERR_NOTOPLEVEL, ERR_WILDTOPLEVEL, 
    # ERR_TOOMANYTARGETS, ERR_NOSUCHNICK, RPL_AWAY
    target = args[0]
    msg = args[1]
    if !target || target.length is 0
      user.sendError(ERROR_CODES.ERR_NORECIPIENT, 'No recepient given (PRIVMSG)')
    else if !msg || msg.length is 0
      user.sendError(ERROR_CODES.ERR_NOSUCHNICK, 'No recepient given (PRIVMSG)')
    else
      sendTarget = @_getChannelOrUserByName(target)
      if sendTarget
        sendTarget.privmsg(user, msg)
      else
        user.sendError(ERROR_CODES.ERR_NOSUCHNICK, target, 'No such nick/channel')

  QUIT: (user, args) ->
    user.quit(args[0] || '')
    @server.disconnect(user)

  # TODO: this should be on IrcDaemon
  _getChannelOrUserByName: (name) ->
    if @_isNameChannel(name) then @server.channels[Irc.normalize(name)] else @server.users[Irc.normalize(name)]

  # TODO: This should be on Irc
  _isNameChannel: (name) ->
    name && name.substr(0, 1) is '#'

  _joinChannel: (user, channelName, key = null) ->
    logger.info "#{user.nick} attempting to join #{channelName} with key '#{key}'"
    
    channel = @server.getChannelByName(channelName) || @server.createChannel(channelName, key)
    
    # if channel.key and channel.key isnt key
      # TODO: Invalid key
    # else if channel.hasMode('i') and user.hasInvite(channel)
      # TODO: Channel is invite only, and the user hasn't been invited
    # else if channel.isFull()
      # TODO: Channel is full
    # else if channel.isBanned(user)
      # TODO: User is banned from channel
    
    # Join the channel
    channel.join(user)

module.exports = CommandExecutor
