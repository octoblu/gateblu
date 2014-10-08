var configDefaults = require('./config-defaults.json');
var fs   = require('fs-extra');
var path = require('path');
var _ = require('lodash');

var HOME_DIR     = process.env.HOME || process.env.HOMEPATH || process.env.USERPROFILE;
var CONFIG_PATH  = path.join(HOME_DIR, '.config/gatenu');
var DEFAULT_FILE = path.join(CONFIG_PATH, 'meshblu.json');

module.exports = {
    loadConfig : function( configPath ) {
        var config;
        configPath = configPath || CONFIG_PATH;

        if( !fs.existsSync(configPath) ) {
            return configDefaults;
        }

        config = JSON.parse(fs.readFileSync(path.join(configPath, 'meshblu.json')));
        return _.defaults(config, configDefaults);
    },
    saveConfig : function(config, configPath) {
        configPath = configPath || CONFIG_PATH;

        fs.mkdirpSync(configPath);

        return fs.writeFileSync( path.join(configPath, 'meshblu.json'), JSON.stringify(config, null, 2));
    }
};
