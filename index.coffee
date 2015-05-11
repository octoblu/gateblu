'use strict';
_            = require 'lodash'
async        = require 'async'
debug        = require('debug')('gateblu:index')
{EventEmitter} = require 'events'

class Gateblu extends EventEmitter
  constructor: (@config, @deviceManager, dependencies={}) ->
    @meshblu = dependencies.meshblu || require 'meshblu'
    @createConnection()

  addDevices: =>
    devicesToAdd = _.reject @devices, (device) =>
      _.findWhere @oldDevices, uuid: device.uuid

    debug 'devicesToAdd', devicesToAdd

    _.each devicesToAdd, (device) =>
      @deviceManager.addDevice device
      @subscribe device

  createConnection: =>
    debug 'createConnection', @config
    @meshbluConnection = @meshblu.createConnection
      uuid: @config.uuid
      token: @config.token
      server: @config.server
      port: @config.port

    @meshbluConnection.on 'notReady', (data) =>
      debug 'notReady', data
      @register() unless @config.uuid?

    @meshbluConnection.on 'ready', (data) =>
      debug 'ready', data
      @config.uuid = data.uuid
      @config.token = data.token
      @refreshConfig()

    @meshbluConnection.on 'config', (data) =>
      return @refreshConfig() if data.uuid == @config.uuid

  getMeshbluDevice: (device, callback) =>
    debug 'meshblu.device', device
    @meshbluConnection.devices uuid: device.uuid, token: device.token, (result) =>
      return callback new Error(result.error?.message) if result.error?
      debug 'got device', result
      callback null, _.extend _.first(result.devices), device

  refreshConfig: =>
    @meshbluConnection.whoami {}, (data) =>
      @emit 'gateblu:config', @config
      @refreshDevices data.devices

  refreshDevices: (devices) =>
    devices ?= []
    debug 'refreshDevices', devices
    async.mapSeries devices, @getMeshbluDevice, (error, devices) =>
      console.error error if error?
      @devices = _.compact devices
      @addDevices()
      @removeDevices()
      @stopDevices()
      @startDevices()
      @oldDevices = _.cloneDeep @devices

  register: =>
    debug 'registering'
    @meshbluConnection.register type: 'device:gateblu', (data) =>
      debug 'registered', data
      @meshbluConnection.identify
        uuid: data.uuid
        token: data.token

  removeDevices: =>
    devicesToRemove = _.reject @oldDevices, (device) =>
      _.findWhere @devices, uuid: device.uuid

    debug 'devicesToRemove', devicesToRemove

    _.each devicesToRemove, (device) =>
      @deviceManager.removeDevice device
      @unsubscribe device

  startDevices: =>
    devicesToStart = _.reject @devices, (device) =>
      _.findWhere @oldDevices, uuid: device.uuid, stop: true

    debug 'devicesToStart', devicesToStart

    _.each devicesToStart, (device) =>
      @deviceManager.startDevice device

  stopDevices: =>
    devicesToStop = _.reject @devices, (device) =>
      _.findWhere @oldDevices, uuid: device.uuid, stop: true

    debug 'devicesToStop', devicesToStop

    _.each devicesToStop, (device) =>
      @deviceManager.stopDevice device

  subscribe: (device) =>
    @meshbluConnection.subscribe uuid: device.uuid, token: device.token

  unsubscribe: (device) =>
    @meshbluConnection.unsubscribe uuid: device.uuid, token: device.token

module.exports = Gateblu
