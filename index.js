var skynet = require('skynet');
var util = require('util');
var EventEmitter = require('events').EventEmitter;

var Gatenu = function(config) {
  var self = this;
  var skynetConnection = skynet.createConnection({ uuid: config.uuid, token: config.token });
  var deviceManager = require('./device-manager')({
    uuid: config.uuid,
    token: config.token,
    devicePath: config.devicePath,
    tmpPath: config.tmpPath,
    nodePath: config.nodePath
  });

  skynetConnection.on('notReady', function(data) {
    console.error('notReady', data);
    if (!config.uuid) {
      skynetConnection.register({type: 'gatenu'}, function(data){
        skynetConnection.identify({uuid: data.uuid, token: data.token});
      });
    }
  });

  var refreshDevices = function() {
    skynetConnection.whoami({}, function(data){
      deviceManager.refreshDevices(data.devices);
    });
  }

  skynetConnection.on('ready', function(data){
    config.uuid  = data.uuid;
    config.token = data.token;
    self.emit('config', config);
    refreshDevices();
  });

  skynetConnection.on('message', function(message){
    if (message.topic === 'refresh') {
      refreshDevices();
    }
    if( deviceManager[message.topic] ) {
      deviceManager[message.topic](message.payload);
    }
  });
}

util.inherits(Gatenu, EventEmitter);
module.exports = Gatenu;
