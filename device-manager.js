var fs = require('fs-extra');
var path = require('path');
var rimraf = require('rimraf');
var forever = require('forever-monitor');
var exec = require('child_process').exec;
var _ = require('lodash');

module.exports = function(config) {
  var deviceManager = {
    setupDevice: function (device, callback) {
      setupDevice(device, callback);
    },
    startDevice: function (device) {
      startDevice(device);
    },
    refreshDevices: function(devices) {
      refreshDevices(devices);
    }
  };

  return deviceManager;

  function refreshDevices(devices) {
    _.each(devices, setupAndStartDevice);
  }

  function setupAndStartDevice(device) {
    setupDevice(device, startDevice);
  }

  function setupDevice(device, callback) {
    var devicePath = path.join(config.devicePath, device.uuid);
    var devicePathTmp = path.join(config.tmpPath, device.uuid);

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
        console.error(error);
      }
      fs.copySync(path.join(devicePathTmp, 'node_modules', device.connector), devicePath);
      fs.writeFileSync(path.join(devicePath, 'meshblu.json'), JSON.stringify(device));
      rimraf.sync(devicePathTmp);
      if (callback) {
        callback(device);
      }
    });
  }

  function startDevice(device) {
    var devicePath = path.join(config.devicePath, device.uuid);
    var child = new (forever.Monitor)('start', {
      max: 3,
      silent: true,
      options: [],
      cwd: devicePath,
      logFile: devicePath + '/forever.log',
      outFile: devicePath + '/forever.stdout',
      errFile: devicePath + '/forever.stderr',
      command: '"' + path.join(config.nodePath, 'npm') + '"'
    });

    child.on('exit', function () {
      console.log('The device exited after 3 restarts');
    });

    child.start();
  }
};
