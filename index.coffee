'use strict';
_            = require 'lodash'
debug        = require('debug')('gateblu:index')
{EventEmitter} = require 'events'

class Gateblu extends EventEmitter
  constructor: (@config, @deviceManager, dependencies={}) ->
    @meshblu = dependencies.meshblu || require 'meshblu'
    @async = dependencies.async || require 'async'
    @queue = @async.queue(@refreshConfigWorker)
    @addToRefreshQueue = _.throttle @addToRefreshQueueImmediately, 5000, trailing: true, leading: false

    @createConnection()

  addDevices: (callback=->) =>
    devicesToAdd = _.reject @devices, (device) =>
      _.findWhere @oldDevices, uuid: device.uuid

    debug 'devicesToAdd', devicesToAdd

    @async.eachSeries devicesToAdd, (device, callback) =>
      @subscribe device
      @deviceManager.addDevice device, callback
    , callback

  addToRefreshQueueImmediately: (callback=->) =>
    @queue?.push {}

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
      @addToRefreshQueue()
      @emit 'ready', data

    @meshbluConnection.on 'config', (data) =>
      return @addToRefreshQueue() if data.uuid == @config.uuid

  getMeshbluDevice: (device, callback) =>
    debug 'meshblu.device', device
    return callback null unless device.uuid?
    _.delay =>
      @meshbluConnection.devices uuid: device.uuid, token: device.token, (result) =>
        return callback null if result.error?.code == 404
        return callback new Error(result.error?.message) if result.error?
        debug 'got device', result
        callback null, _.extend _.first(result.devices), device
    , 500

  refreshConfig: (callback=->) =>
    @meshbluConnection.whoami {}, (data) =>
      @emit 'gateblu:config', @config
      @refreshDevices data.devices, =>
        callback()

  refreshConfigWorker: (task, callback=->) =>
    @refreshConfig callback

  refreshDevices: (devices, callback=->) =>
    devices ?= []
    debug 'refreshDevices', devices
    @async.mapSeries devices, @getMeshbluDevice, (error, devices) =>
      console.error error if error?
      @devices = _.compact devices
      @async.series [
        (callback) => @addDevices -> callback()
        (callback) => @startDevices -> callback()
        (callback) => @removeDevices -> callback()
        (callback) => @stopDevices -> callback()
      ], =>
        @oldDevices = _.cloneDeep @devices
        debug 'refreshDevices', 'in callback', @devices, @oldDevices
        callback()

  register: =>
    debug 'registering'
    @meshbluConnection.register type: 'device:gateblu', (data) =>
      debug 'registered', data
      @meshbluConnection.identify
        uuid: data.uuid
        token: data.token

  removeDevices: (callback=->) =>
    devicesToRemove = _.reject @oldDevices, (device) =>
      _.findWhere @devices, uuid: device.uuid

    debug 'devicesToRemove', devicesToRemove

    @async.eachSeries devicesToRemove, (device, callback) =>
      @unsubscribe device
      @deviceManager.removeDevice device, callback
    , callback

  startDevices: (callback=->) =>
    devicesToStart = _.filter @devices, (device) ->
      device.stop == false || !device.stop?

    debug 'devicesToStart', devicesToStart

    @async.eachSeries devicesToStart, (device, callback) =>
      @deviceManager.startDevice device, callback
    , callback

  stopDevices: (callback=->) =>
    devicesToStop = _.where @devices, stop: true

    debug 'devicesToStop', devicesToStop

    @async.eachSeries devicesToStop, (device, callback) =>
      @deviceManager.stopDevice device, callback
    , callback

  subscribe: (device) =>
    @meshbluConnection.subscribe uuid: device.uuid, token: device.token, types: ['received', 'broadcast']

  unsubscribe: (device) =>
    @meshbluConnection.unsubscribe uuid: device.uuid, token: device.token, types: ['received', 'broadcast']

module.exports = Gateblu
