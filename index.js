var skynet = require('skynet');
var util = require('util');
var EventEmitter = require('events').EventEmitter;
var DeviceManager = require('./device-manager');

var Gatenu = function(config) {
  var self = this;
  var skynetConnection = skynet.createConnection({ uuid: config.uuid, token: config.token, server: config.server, port: config.port });
  var deviceManager = new DeviceManager({
    uuid: config.uuid,
    token: config.token,
    devicePath: config.devicePath,
    tmpPath: config.tmpPath,
    nodePath: config.nodePath
  });

  var refreshDevices = function() {
    skynetConnection.whoami({}, function(data){
      deviceManager.refreshDevices(data.devices);
    });
  }

  var updateType = function(){
    skynetConnection.update({uuid: config.uuid, type: 'device:genblu'});
  }

  deviceManager.on('start', function(device){
    self.emit('device:start', device);
  });

  skynetConnection.on('notReady', function(data) {
    console.error('notReady', data);
    if (!config.uuid) {
      skynetConnection.register({}, function(data){
        skynetConnection.identify({uuid: data.uuid, token: data.token});
      });
    }
  });

  skynetConnection.on('ready', function(data){
    config.uuid  = data.uuid;
    config.token = data.token;
    self.emit('config', config);
    updateType();
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
