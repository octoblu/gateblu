var skynet = require('skynet');
var _ = require('lodash');

module.exports = function(configManager) {
    var config = configManager.loadConfig();
    var skynetConnection = skynet.createConnection({ uuid: config.uuid, token: config.token });
    var deviceManager = require('./device-manager')(config);

    if (!config.uuid) {
        skynetConnection.register({type: 'gateway'}, function(data){
            skynetConnection.identify({uuid: data.uuid, token: data.token});
        });
    }

    skynetConnection.on('ready', function(readyResponse){
        console.log('ready');
        config.uuid = readyResponse.uuid;
        config.token = readyResponse.token;
        configManager.saveConfig(config);
    });

    skynetConnection.on('message', function(message){
       if( deviceManager[message.topic] ) {
           deviceManager[message.topic](message.payload);
       }
    });
};