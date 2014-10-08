var skynet = require('skynet');

module.exports = function(config) {
  var skynetConnection = skynet.createConnection({ uuid: config.uuid, token: config.token });
  var deviceManager = require('./device-manager')(config);

  if (!config.uuid) {
    skynetConnection.register({type: 'gateway'}, function(data){
      skynetConnection.identify({uuid: data.uuid, token: data.token});
    });
  }

  skynetConnection.on('ready', function(data){
    deviceManager.refreshDevices(data.devices);
  });

  skynetConnection.on('message', function(message){
   if( deviceManager[message.topic] ) {
     deviceManager[message.topic](message.payload);
   }
 });
};
