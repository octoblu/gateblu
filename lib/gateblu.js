'use strict';

var skynet       = require('skynet');
var util         = require('util');
var _            = require('lodash');
var debug        = require('debug')('gateblu:index');
var EventEmitter = require('events').EventEmitter;

var Gateblu = function(config, deviceManager) {
  var self = this;
  var skynetConnection = skynet.createConnection({ uuid: config.uuid, token: config.token, server: config.server, port: config.port });

  deviceManager.on('stderr', function(data, device){
    self.emit('stderr', data, device);
  });

  deviceManager.on('stdout', function(data, device){
    self.emit('stdout', data, device);
  });

  deviceManager.on('update', function(devices){
    self.emit('update', devices);
  });

  var refreshDevices = function(callback) {
    callback = callback || _.noop;
    skynetConnection.whoami({}, function(data){
      debug('whoami: ', data);
      self.emit('gateblu:orig:config', data);

      deviceManager.refreshDevices(data.devices, function(){
        self.emit('refresh');
        callback();
      });
    });
  };

  var refreshDevice = function(device, callback) {
    skynetConnection.devices({
      "uuid" : device.uuid
    }, function(data){

      if(!data || !data.devices || !data.devices.length) {
        return;
      }

      var device = data.devices[0];
      deviceManager.stopDevice(device.uuid, function(){
        deviceManager.startDevice(device);
      });

    });
  };


  var register = function(){
    debug("registering");
    skynetConnection.register({}, function(data){
      debug("registered", data);
      skynetConnection.identify({uuid: data.uuid, token: data.token});
    });
  };

  var updateType = function(){
    skynetConnection.update({uuid: config.uuid, type: 'device:gateblu'});
  };

  deviceManager.on('start', function(device){
    debug('start', device.uuid);
    skynetConnection.subscribe({uuid: device.uuid, token: device.token})
    self.emit('device:start', device);
  });

  skynetConnection.on('notReady', function(data) {
    console.error('notReady', data);
    debug('notReady', data, config);
    if (!config.uuid) {
      register();
      return;
    }

    var device = {uuid: config.uuid, token: config.token, connector: true};
    debug('checking if device exists', device);
    deviceManager.deviceExists(device, function(error, device){
      if(error){
        return debug(error);
      }

      if(!device) {
        self.emit('unregistered');
      }
    });
  });

  skynetConnection.on('disconnect', function(){
    debug('disconnected');
    self.emit('disconnected');
  });

  skynetConnection.on('error', function(error){
    debug('skynet error', error);
  })

  skynetConnection.on('ready', function(data){
    debug('ready', data);
    config.uuid  = data.uuid;
    config.token = data.token;
    self.emit('gateblu:config', config);
    updateType();
    debug('ready', data);
    refreshDevices(function(error){
      if (error) {
        self.emit('error', error);
      }
    });
  });

  skynetConnection.on('config', function(data){
    debug('config', data);
    if (data.uuid === config.uuid) {
      self.emit('gateblu:orig:config', data);
    } else {
      self.emit('device:config', data);
    }
  });

  skynetConnection.on('unregistered', function(data){
    debug('unregistered', data);
    if(data.uuid === config.uuid) {
      return self.emit('unregistered');
    }

    deviceManager.stopDevice(data.uuid, function(error){
      refreshDevices();
    });
  });

  skynetConnection.on('message', function(message){
    debug('message received: ', message);
    if (message.topic === 'refresh') {
      refreshDevices();
    }
    if (message.topic === 'device-status') {
      self.emit('device:status', {online: message.payload.online, uuid: message.fromUuid});
    }

    if (message.topic === 'refresh-device') {
      refreshDevice({uuid: message.deviceUuid, token: message.deviceToken});
    }

    if( deviceManager[message.topic] ) {
      deviceManager[message.topic](message.payload);
    }
  });

  this.cleanup = _.once(function() {
    debug('cleanup');
    process.stdin.resume();

    try {
      deviceManager.stopDevices(function(error, uuids){
        process.exit();
      });
    } catch (error) {
      console.error(error.message, error.stack);
      process.exit();
    }
  });

  this.stopDevice = deviceManager.stopDevice;
  this.startDevice = deviceManager.startDevice;
  this.deleteDevice = function(uuid, token) {
    debug('deleteDevice', uuid);
    skynetConnection.unregister({uuid: uuid, token: token}, function() {
      refreshDevices();
    });
  };
  this.stopDevices = deviceManager.stopDevices;
};

util.inherits(Gateblu, EventEmitter);
module.exports = Gateblu;
