'use strict';

var skynet       = require('skynet');
var util         = require('util');
var _            = require('lodash');
var debug        = require('debug')('gateblu:index');
var EventEmitter = require('events').EventEmitter;
var DeviceManager = require('./device-manager');

var Gateblu = function(config) {
  var self = this;
  var skynetConnection = skynet.createConnection({ uuid: config.uuid, token: config.token, server: config.server, port: config.port });
  var deviceManager = new DeviceManager({
    uuid: config.uuid,
    token: config.token,
    devicePath: config.devicePath,
    tmpPath: config.tmpPath,
    nodePath: config.nodePath,
    server:  config.server,
    port:    config.port
  });

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
    callback = callback || _.noop
    skynetConnection.whoami({}, function(data){
      debug('whoami: ', data);
      self.emit('gateblu:orig:config', data);

      deviceManager.refreshDevices(data.devices, function(){
        self.emit('refresh');
        callback();
      });
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
    debug('notReady', data);
    if (!config.uuid) {
      skynetConnection.register({}, function(data){
        skynetConnection.identify({uuid: data.uuid, token: data.token});
      });
    }
  });

  skynetConnection.on('ready', function(data){
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
    deviceManager.stopDevice(data.uuid);
    refreshDevices();
  });

  skynetConnection.on('message', function(message){
    debug('message received: ', message);
    if (message.topic === 'refresh') {
      refreshDevices();
    }
    if (message.topic === 'device-status') {
      self.emit('device:status', {online: message.payload.online, uuid: message.fromUuid});
    }
    if( deviceManager[message.topic] ) {
      deviceManager[message.topic](message.payload);
    }
  });

  this.cleanup = _.once(function() {
    debug('cleanup');
    process.stdin.resume();

    deviceManager.stopDevices(function(error, uuids){
      process.exit();
    });
  });

  this.stopDevice = deviceManager.stopDevice;
  this.startDevice = deviceManager.startDevice;
  this.deleteDevice = function(uuid, token) {
    debug('deleteDevice', uuid);
    deviceManager.stopDevice(uuid);
    skynetConnection.unregister({uuid: uuid, token: token}, function() {
      refreshDevices();
    });
  };
  this.stopDevices = deviceManager.stopDevices;
};

util.inherits(Gateblu, EventEmitter);
module.exports = Gateblu;
