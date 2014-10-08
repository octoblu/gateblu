var skynet = require('skynet');
var _ = require('lodash');
var configDefaults = require('./config-defaults.json');
module.exports = function(config) {
    config = _.defaults(config, configDefaults);
    var skynetConnection = skynet.createConnection({ server : config.server, port : config.port, uuid: config.uuid, token: config.token });

    skynetConnection.on('notReady', function(){
      if (!config.uuid) {
        skynetConnection.register({type: 'gateway'}, function(data){
          skynetConnection.identify({uuid: data.uuid, token: data.token});
        });
      }
    });

    var deviceManager = require('./device-manager')(config, skynetConnection);

    skynetConnection.on('ready', function(readyResponse){
        config.uuid = readyResponse.uuid;
        config.token = readyResponse.token;
        deviceManager.saveConfig(config);
    });

    skynetConnection.on('message', function(message){
       if( deviceManager[message.topic] ) {
           deviceManager[message.topic](message.payload);
       }
    });
};