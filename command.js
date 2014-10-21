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
	  console.log(commander.config);
	  var commandFile = fs.readFileSync(commander.config)
  	 
  } else{
	   if (!commander.uuid || !commander.token || !commander.tmpPath || !commander.devicePath || !commander.nodePath) {
   			commander.help()
		} 
		else {
			configOptions = {
  			  uuid       : commander.uuid,
  			  token      : commander.token,
			  devicePath : commander.devicePath,
			  nodePath   : commander.nodePath,
			  tmpPath    : commander.tmpPath,
			  server     : commander.server || 'meshblu.octoblu.com',
			  port       : commander.port || '80'
		  };
		}
  }

var gatenu = require('./index')(configOptions);
