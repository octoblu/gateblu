var skynet = require('skynet');

var configManager = require('./src/config-manager');
var config = configManager.loadConfig();

var skynetConnection = skynet.createConnection({ server : config.server, port : config.port, uuid: config.uuid, token: config.token });

skynetConnection.on('notReady', function(){
  if (!config.uuid) {
    skynetConnection.register({type: 'gateway'}, function(data){
      skynetConnection.identify({uuid: data.uuid, token: data.token});
    });
  }
});

var messageManager = require('./src/message-manager')(config, skynetConnection);

skynetConnection.on('ready', function(readyResponse){
    config.uuid = readyResponse.uuid;
    config.token = readyResponse.token;
    configManager.saveConfig(config);
});

skynetConnection.on('message', function(message){
   if( messageManager[message.topic] ) {
       messageManager[message.topic](message.payload);
   }
});


