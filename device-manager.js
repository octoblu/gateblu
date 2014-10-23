var util = require('util');
var EventEmitter = require('events').EventEmitter;
var fs = require('fs-extra');
var path = require('path');
var rimraf = require('rimraf');
var forever = require('forever-monitor');
var exec = require('child_process').exec;
var _ = require('lodash');
var async = require('async');
var request = require('request');

var DeviceManager = function (config) {
  var self = this;
  var deviceProcesses = [];

  self.refreshDevices = function (devices, callback) {
    async.map(devices || [], self.deviceExists, function (error, devices) {
      if (error) {
        return callback(error);
      }

      devices = _.compact(devices);
      self.emit('update', devices);
      self.installDevices(devices, callback);
    });
  };

  self.deviceExists = function (device, callback) {
    var authHeaders, deviceUrl;
    if (!device.connector) {
      _.defer(callback);
      return;
    }

    authHeaders = {skynet_auth_uuid: device.uuid, skynet_auth_token: device.token};
    deviceUrl = 'http://' + config.server + ':' + config.port + '/devices/' + device.uuid;

    request({url: deviceUrl, headers: authHeaders, json: true}, function (error, response, body) {
      if (error || response.statusCode !== 200) {
        return callback(error, null);
      }

      callback(null, _.extend(body, device));
    });
  };

  self.installDevices = function (devices, callback) {
    var connectors = _.compact(_.uniq(_.pluck(devices, 'connector')));

    async.series([
      function (callback) {
        self.installConnectors(connectors, callback);
      },
      function (callback) {
        fs.mkdirp(config.devicePath, callback);
      },
      function (callback) {
        async.eachSeries(devices, self.setupAndStartDevice, callback);
      }
    ], callback);
  };


  self.installConnectors = function (connectors, callback) {
    async.series([
      function (callback) {
        fs.mkdirp(config.tmpPath, callback);
      },
      function (callback) {
        async.each(connectors, self.installConnector, callback);
      }
    ], callback);
  };

  self.installConnector = function (connector, callback) {
    var cachePath, connectorPath, npmCommand, cmd;

    cachePath = config.tmpPath;
    connectorPath = path.join(cachePath, 'node_modules', connector);
    npmCommand = 'install';
    if (fs.existsSync(connectorPath)) {
      npmCommand = 'update';
    }
    cmd = '"' + path.join(config.nodePath, 'npm') + '" --prefix=. ' + npmCommand + ' ' + connector;

    exec(cmd, {cwd: cachePath}, callback);
  };

  self.setupAndStartDevice = function (device, callback) {
    async.series([
      function (callback) {
        self.setupDevice(device, callback);
      },
      function (callback) {
        self.startDevice(device, callback);
      },
    ], callback);
  };

  self.setupDevice = function (device, callback) {
    var connectorPath, deviceConfig, devicePath, cachePath, meshbluConfig, meshbluFilename;
    try {
      devicePath = path.join(config.devicePath, device.uuid);
      deviceConfig = _.extend({}, device, {server: config.server, port: config.port});
      cachePath = config.tmpPath;
      connectorPath = path.join(cachePath, 'node_modules', device.connector);
      meshbluFilename = path.join(devicePath, 'meshblu.json');
      meshbluConfig = JSON.stringify(deviceConfig, null, 2);

      rimraf.sync(devicePath);
      fs.copySync(connectorPath, devicePath);
      fs.writeFileSync(meshbluFilename, meshbluConfig);

      _.defer(function () {
        callback();
      });
    } catch (error) {
      _.defer(function () {
        callback(error);
      });
    }
  };

  self.startDevice = function (device, callback) {
    var devicePath = path.join(config.devicePath, device.uuid);
    var child = new (forever.Monitor)('start', {
      max: 3,
      silent: true,
      options: [],
      cwd: devicePath,
      logFile: devicePath + '/forever.log',
      outFile: devicePath + '/forever.stdout',
      errFile: devicePath + '/forever.stderr',
      command: path.join(config.nodePath, 'npm')
    });

    child.on('exit', function () {
      self.emit('error', 'The device exited after 3 restarts');
    });

    child.on('stderr', function(data) {
      self.emit('stderr', data.toString(), device);
    });

    child.on('stdout', function(data) {
      self.emit('stdout', data.toString(), device);
    });

    child.start();
    deviceProcesses[device.uuid] = child;

    self.emit('start', device);
    callback();
  };

  self.stopDevice = function (uuid, callback) {
    var deviceProcess = deviceProcesses[uuid];

    if (!deviceProcess) {
      return callback();
    }

    deviceProcess.stop();
    deviceProcess.on('stop', function() {
      callback(null, uuid);
    });

  };

  self.stopDevices = function(callback) {
    async.each( _.keys(deviceProcesses), self.stopDevice, callback );
  }

};

util.inherits(DeviceManager, EventEmitter);
module.exports = DeviceManager;
