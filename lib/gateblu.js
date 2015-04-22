'use strict';

var util         = require('util');
var _            = require('lodash');
var debug        = require('debug')('gateblu:index');
var EventEmitter = require('events').EventEmitter;

var Gateblu = function(config, deviceManager, dependencies) {
  var self = this;
  dependencies = dependencies || {};
  var meshblu = dependencies.meshblu || require('meshblu');

  var skynetConnection = meshblu.createConnection({ uuid: config.uuid, token: config.token, server: config.server, port: config.port });

  deviceManager.on('stderr', function(data, device){
    self.emit('stderr', data, device);
  });

  deviceManager.on('stdout', function(data, device){
    self.emit('stdout', data, device);
  });

  deviceManager.on('update', function(devices){
    self.emit('update', devices);
  });

  self.refreshDevice = function(device, callback) {
    deviceManager.stopDevice(device.uuid, function(){
      deviceManager.startDevice(device);
    });
  }

  var refreshDevicesImmediate = function(callback) {
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

  self.refreshDevices = _.debounce(refreshDevicesImmediate, 1000);

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

  deviceManager.on('start', function(device) {
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
    deviceManager.deviceExists(device, function(error, device) {
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
    self.refreshDevices(function(error){
      if (error) {
        self.emit('error', error);
      }
    });
  });

  skynetConnection.on('config', function(data) {
    debug('config', data);

    if (data.uuid === config.uuid) {
      self.emit('gateblu:orig:config', data);
      self.refreshDevices(function(error){
        if (error) {
          self.emit('error', error);
        }
      });
      return;
    }
    self.emit('device:config', data);
  });

  skynetConnection.on('unregistered', function(device) {
    debug('unregistered', device);
    self.emit('unregistered', device);
  });

  skynetConnection.on('message', function(message) {
    debug('message received: ', message);
    if (message.topic === 'refresh') {
      self.refreshDevices(function(error){
        if(!error) {
          return;
        }

        self.emit('gateblu:error', error);
      });
      return;
    }
    if (message.topic === 'refresh-device') {
      self.refreshDevice({uuid: message.deviceUuid, token: message.deviceToken});
      return;
    }
    if (message.topic === 'device-status') {
      self.emit('device:status', {online: message.payload.online, uuid: message.fromUuid});
      return;
    }
    if (message.topic === 'device-start') {
      debug('device-start', message);
      self.startDevice(message.payload, _.noop)
      return;
    }
    if (message.topic === 'device-stop') {
      self.stopDevice(message.deviceUuid, _.noop)
      return;
    }
  });

  self.cleanup = _.once(function() {
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

  self.stopDevice = function(uuid) {
    debug('stopDevice', uuid);
    skynetConnection.whoami({}, function(gatebluData) {
      debug('stopDevice:whoami', gatebluData);

      var devices = _.cloneDeep(gatebluData.devices);
      var deviceToStop = _.findWhere(devices, {uuid: uuid});

      debug('stopDevice:deviceToStop', deviceToStop);

      if( !deviceToStop) {
        return;
      }

      deviceToStop.stop = true;
      skynetConnection.update({uuid: config.uuid, devices: devices});
    });
  };

  self.startDevice = function(device) {
    device = self.getConnectorData(device);
    device.stop = false;

    debug('startDevice', device);
    skynetConnection.whoami({}, function(gatebluData) {
      debug('startDevice:whoami', gatebluData);

      var devices = _.reject(gatebluData.devices, {uuid: device.uuid});
      debug('device to start', device, 'devices', devices);
      devices.push(device);
            
      skynetConnection.update({uuid: config.uuid, devices: devices});
    });
  };

  self.deleteDevice = function(uuid, token) {
    skynetConnection.whoami({}, function(gatebluData) {
      debug('deleteDevice:whoami', gatebluData);
      var devices = _.reject(gatebluData.devices, {uuid: uuid});
      skynetConnection.update({uuid: config.uuid, devices: devices});
    });
    skynetConnection.unregister({uuid: uuid, token: token});
  };

  self.getConnectorData = function(device) {
    return _.pick(device, 'uuid','token', 'connector', 'type');
  };

};

util.inherits(Gateblu, EventEmitter);
module.exports = Gateblu;
