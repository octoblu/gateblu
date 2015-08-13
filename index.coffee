'use strict';
_            = require 'lodash'
debug        = require('debug')('gateblu:index')
packageJSON  = require './package.json'
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

    debug 'devicesToAdd', devicesToAdd?.uuid

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
      @ensureType =>
        @addToRefreshQueue()
        @emit 'ready', data

    @meshbluConnection.on 'config', (data) =>
      @addToRefreshQueue() if data.uuid == @config.uuid

    @meshbluConnection.on 'unregistered', (data) =>
      @addToRefreshQueue()

  generateDeviceTokens: (callback=->) =>
    @async.eachSeries @devices, (device, cb) =>
      @meshbluConnection.generateAndStoreToken uuid: device.uuid, (result) =>
        device.token = result?.token
        cb()
    , callback

  getMeshbluDevice: (device, callback=->) =>
    debug 'meshblu.device', device
    return callback null unless device.uuid?
    _.delay =>
      @meshbluConnection.device uuid: device.uuid, (result) =>
        return callback null if result.error?.code == 404
        return callback new Error(result.error?.message) if result.error?
        debug 'got device', result?.device?.uuid
        callback null, _.extend result.device, device
    , 500

  ensureType: (callback=->) =>
    debug 'ensureType'
    @meshbluConnection.whoami {}, (data) =>
      return callback() if data.type?
      debug 'no type set, updating'
      @meshbluConnection.update type: 'device:gateblu', =>
        callback()

  refreshConfig: (callback=->) =>
    @meshbluConnection.whoami {}, (data) =>
      hash = data.meshblu?.hash
      debug 'refreshConfig compare hash', @previousHash, hash, @previousHash == hash
      return callback() if @previousHash? && @previousHash == hash
      @previousHash = hash if hash?
      @emit 'gateblu:config', @config
      @async.series [
        @async.apply @updateDevicePermissions, data.devices
        @async.apply @refreshDevices, data.devices
      ], =>
        callback()

  refreshConfigWorker: (task, callback=->) =>
    @refreshConfig callback

  refreshDevices: (devices, callback=->) =>
    devices ?= []
    debug 'refreshDevices', _.pluck devices, 'uuid'
    @async.mapSeries devices, @getMeshbluDevice, (error, devices) =>
      console.error error if error?

      return callback() if _.eq devices, @oldDevices

      @devices = _.compact devices
      @async.series [
        @async.apply @updateGateblu
        @async.apply @generateDeviceTokens
        @async.apply @addDevices
        @async.apply @startDevices
        @async.apply @removeDevices
        @async.apply @stopDevices
      ], =>
        @oldDevices = _.cloneDeep @devices
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

    debug 'devicesToStart', _.pluck devicesToStart, 'uuid'

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

  updateDevicePermissions: (devices, callback=->) =>
    @async.eachSeries devices, (device, cb) =>
      return cb() unless device.token?
      @meshbluConnection.device uuid: device.uuid, token: device.token, (result) =>
        data = _.pick result.device, 'uuid', 'token', 'sendAsWhitelist', 'receiveAsWhitelist', 'configureWhitelist', 'discoverWhitelist'
        data.sendAsWhitelist ?= []
        data.receiveAsWhitelist ?= []
        data.configureWhitelist ?= []
        data.discoverWhitelist ?= []

        data.sendAsWhitelist.push @config.uuid
        data.receiveAsWhitelist.push @config.uuid
        data.configureWhitelist.push @config.uuid
        data.discoverWhitelist.push @config.uuid

        @meshbluConnection.update data, => cb()
    , callback

  updateGateblu: (callback=->) =>
    data =
      uuid: @config.uuid
      devices: _.map @devices, (device) => _.pick device, 'uuid', 'connector', 'type'
      version: packageJSON.version

    @meshbluConnection.update data, (response) =>
      callback()

  unsubscribe: (device) =>
    @meshbluConnection.unsubscribe uuid: device.uuid, token: device.token, types: ['received', 'broadcast']

module.exports = Gateblu
