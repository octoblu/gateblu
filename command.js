var commander = require('commander');
var fs = require('fs'); 
commander
  .version(0.1)
  .option('-u, --uuid [uuid]',  'Meshblu UUID')
  .option('-c, --config [configPath]', 'Path to config file')
  .option('-t, --token [token]',  'Meshblu Token')
  .option('--tmp-path [tmpPath]',  'Ephemeral path')
  .option('--device-path [devicePath]',  'Where are my devices')
  .option('--server [server]', 'Meshblu Server')
  .option('--port [port]', 'Meshblu Port' )
  .option('--node-path [nodePath]',  'Path for node')
  .parse(process.argv);

  var configOptions = {}; 
  
  if(commander.config){
	  configOptions = JSON.parse(fs.readFileSync(commander.config)); 
	  console.log('Config Options', configOptions);
  } else {
	if (!commander.uuid || !commander.token || !commander.tmpPath || !commander.devicePath || !commander.nodePath) {
		commander.help()
	} 
	else {
		configOptions = {
		  uuid       : commander.uuid,
		  token      : commander.token,
		  devicePath : commander.devicePath,
		  nodePath   : commander.nodePath || '',
		  tmpPath    : commander.tmpPath || '',
		  server     : commander.server || 'meshblu.octoblu.com',
		  port       : commander.port || '80'
	  };
	}
  }

var GateBlu = require('./index');

var gateblu = new GateBlu(configOptions);
process.on('exit', gateblu.cleanup);
process.on('SIGINT', gateblu.cleanup);
process.on('uncaughtException', gateblu.cleanup);

