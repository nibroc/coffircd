fs = require('fs')
logger = require('winston')

IrcDaemon = require './src/IrcDaemon'

logger.level = 'debug'
logger.add(logger.transports.File, { filename: 'coffircd.log' })

logger.debug -> 'test'

config = JSON.parse(fs.readFileSync('coffircd.json', 'utf8'))
logger.debug "Loaded configuration (coffircd.json): #{JSON.stringify(config)}"

new IrcDaemon(config)
