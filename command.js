var commander = require('commander');

commander
  .version(0.1)
  .option('-u, --uuid [uuid]',  'Meshblu UUID')
  .option('-t, --token [token]',  'Meshblu Token')
  .option('--tmp-path [tmpPath]',  'Ephemeral path')
  .option('--device-path [devicePath]',  'Where are my devices')
  .option('--node-path [nodePath]',  'Path for node')
  .parse(process.argv);

if (!commander.uuid) {
  commander.help()
}

var gatenu = require('./index')({
  uuid       : commander.uuid,
  token      : commander.token,
  devicePath : commander.devicePath,
  nodePath   : commander.nodePath,
  tmpPath    : commander.tmpPath
});
