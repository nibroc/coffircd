Irc = require('./Irc')
ERROR_CODES = Irc.ERROR_CODES

logger = require('winston')

class Channel
  constructor: (@server, @name, @key) ->
    @users = {}
    @modes = {}

  join: (user) ->
    return if @users[Irc.normalize(user.nick)]

    @users[Irc.normalize(user.nick)] = user

    # Notify everyone (including the joiner) that the user joined
    (u.sendCommandFromUser(user, 'JOIN', @name)) for _, u of @users
    
    # Let the user know the user list of the channel
    # TODO: this should be refactored into the 'NAMES' command

    #  RPL_NAMREPLY format: "( "=" / "*" / "@" ) <channel> :[ "@" / "+" ] <nick> *( " " [ "@" / "+" ] <nick> )
    # "@" is used for secret channels, "*" for private channels, and "=" for others (public channels).
    if @hasMode('s')
      channelPrefix = '@'
    else if @hasMode('p')
      # TODO: Make sure private is actually +p
      channelPrefix = '*'
    else
      channelPrefix = '='

    user.sendNumeric(ERROR_CODES.RPL_NAMREPLY, channelPrefix, @name, ':' + @getUserNicksWithModePrefixes().join(' '))

    # RPL_ENDOFNAMES format: <channel> :End of NAMES list
    user.sendNumeric(ERROR_CODES.RPL_ENDOFNAMES, @name, ':End of NAMES list')

    user.join(this)

  quit: (user, msg) ->
    user = @users[Irc.normalize(user.nick)]
    return unless user
    delete @users[Irc.normalize(user.nick)]
    user.removeChannel(this.name)
    @eachUser (u) -> u.sendCommandFromUser(user, 'QUIT', msg)

  part: (user, msg) ->
    user = @users[Irc.normalize(user.nick)]
    return unless user
    @eachUser (u) -> u.sendCommandFromUser(user, 'PART', @name, msg)
    delete @users[Irc.normalize(user.nick)]
    user.removeChannel(this.name)

  privmsg: (sender, msg) ->
    @eachUser (user) =>
      user.privmsg(sender, msg, @name) if user.nick isnt sender.nick

  eachUser: (fn) ->
    (fn(u)) for _, u of @users

  getUsers: ->
    @users

  hasUser: (user) ->
    nick = user.nick || user
    @users[Irc.normalize(nick)]

  # Public: get nicknames of all users in the channel with all of their names (possibly) suffixed with 
  # their channel mode as per #getModePrefixForUser.
  # Returns an array of all nicknames in the channel with mode prefixes
  getUserNicksWithModePrefixes: ->
    (@getModePrefixForUser(u) + u.nick) for _, u of @users

  # Public: get the mode prefix for the specified user. For example, if the user has mode +o, the character @
  # will be returned. Similarly, if the user is voiced (and not op'd), + will be returned.
  #
  # user - the user whose mode prefix is being retrieved
  #
  # Returns the mode prefix for the specified user (either '@', '+', or the empty string)
  getModePrefixForUser: (user) ->
    # TODO: this rather needs to be implemented...
    ''

  hasMode: (mode) ->
    @modes[mode]

module.exports = Channel
