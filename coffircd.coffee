IrcDaemon = require './src/IrcDaemon'
logger = require('winston')

logger.level = 'debug'

logger.add(logger.transports.File, { filename: 'coffircd.log' });

daemon = new IrcDaemon(6667)
daemon.start()
