var configManager = require('./config-manager');

device = {name: 'test-subdevice', connector: 'meshblu-blink1', uuid: 'f105d101-4ea8-11e4-9133-338b9914afd1', token: '000xfoik6yptoi529egexh80t3rcc8fr'}

var deviceManager = require('./device-manager')(configManager.loadConfig());
deviceManager.setupDevice(device, deviceManager.startDevice);