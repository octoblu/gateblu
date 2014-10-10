var util = require('util');
var EventEmitter = require('events').EventEmitter;
var fs = require('fs-extra');
var path = require('path');
var rimraf = require('rimraf');
var forever = require('forever-monitor');
var exec = require('child_process').exec;
var _ = require('lodash');

var DeviceManager = function(config) {
  var self = this;

  self.refreshDevices = function(devices) {
    _.each(devices, self.setupAndStartDevice);
  }

  self.setupAndStartDevice = function(device) {
    self.setupDevice(device, function(error, device) {
      if(error){
        console.error(error.message.split('\n').length);
        console.error(error.stack);
        return;
      }
      self.startDevice(device);
    });
  }

  self.setupDevice = function(device, callback) {
    try {
      var devicePath = path.join(config.devicePath, device.uuid);
      var devicePathTmp = path.join(config.tmpPath, device.uuid);
      var deviceConfig = _.extend({}, device, { server:config.server, port: config.port});
      if (fs.existsSync(devicePath)) {
        rimraf.sync(devicePath);
      }

      if (fs.existsSync(devicePathTmp)) {
        rimraf.sync(devicePathTmp);
      }

      fs.mkdirpSync(devicePath);
      fs.mkdirpSync(devicePathTmp);

      exec('"' + path.join(config.nodePath, 'npm') + '" --prefix=. install ' + device.connector, {cwd: devicePathTmp}, function (error, stdout, stderr) {
        if (error) {
          callback(error);
          return;
        }
        fs.copySync(path.join(devicePathTmp, 'node_modules', device.connector), devicePath);
        fs.writeFileSync(path.join(devicePath, 'meshblu.json'), JSON.stringify(deviceConfig, null, 2));
        
        rimraf.sync(devicePathTmp);
        if (callback) {
          callback(null, device);
        }
      });
    } catch (error) {
      callback(error);
    }
  }

  self.startDevice = function(device) {
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
      console.log('The device exited after 3 restarts');
    });

    child.start();
    self.emit('start', device);
  }
};

util.inherits(DeviceManager, EventEmitter);
module.exports = DeviceManager;
