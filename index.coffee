'use strict';
_            = require 'lodash'
debug        = require('debug')('gateblu:index')
packageJSON  = require './package.json'
{EventEmitter2} = require 'eventemitter2'

class Gateblu extends EventEmitter2
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

    @async.eachSeries devicesToAdd, (device, cb) =>
      @subscribe device
      @deviceManager.addDevice device, cb
    , callback

  addToRefreshQueueImmediately: (callback=->) =>
    @queue?.push {}

  clearCache: =>
    @previousHash = null
    @oldDevices = null

  createConnection: =>
    debug 'createConnection', @config
    @meshbluConnection = @meshblu.createConnection @config

    @meshbluConnection.on 'notReady', (data) =>
      debug 'notReady', data
      @emit 'notReady', data

    @meshbluConnection.on 'disconnect', =>
      debug 'disconnected'
      @emit 'disconnected'

    @meshbluConnection.on 'ready', (data) =>
      debug 'ready', data
      @clearCache()
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
        return cb new Error(result?.error?.message) if result?.error?
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
        callback null, result?.device
    , 500

  ensureType: (callback=->) =>
    debug 'ensureType'
    @meshbluConnection.whoami {}, (data) =>
      return callback() if data.type?
      debug 'no type set, updating'
      @meshbluConnection.update type: 'device:gateblu', (result) =>
        return callback new Error(result?.error?.message) if result?.error?
        callback()

  refreshConfig: (callback=->) =>
    @whoami (error, data) =>
      return callback error if error?

      hash = data.meshblu?.hash
      debug 'refreshConfig compare hash', @previousHash, hash, @previousHash == hash
      return callback() if @previousHash? && @previousHash == hash
      @previousHash = hash if hash?
      @emit 'config', data
      @async.series [
        @async.apply @updateDevicePermissions, data.devices
        @async.apply @refreshDevices, data.devices
      ], callback

  refreshConfigWorker: (task, callback=->) =>
    @refreshConfig callback

  refreshDevices: (devices, callback=->) =>
    devices ?= []
    debug 'refreshDevices', _.pluck devices, 'uuid'
    @async.mapSeries devices, @getMeshbluDevice, (error, devices) =>
      return callback error if error?
      return callback() if _.eq devices, @oldDevices

      @devices = _.compact devices
      @async.series [
        @async.apply @emitRefreshDevices
        @async.apply @updateGateblu
        @async.apply @generateDeviceTokens
        @async.apply @addDevices
        @async.apply @startDevices
        @async.apply @removeDevices
        @async.apply @stopDevices
      ], (error) =>
        return callback error if error?

        @oldDevices = _.cloneDeep @devices
        callback()

  register: (options={}, callback=->) =>
    debug 'registering'
    options.type = 'device:gateblu'
    @meshbluConnection.register options, (data) =>
      if data?.error?
        @emit 'error', new Error(data?.error?.message)
        return callback new Error(data?.error?.message)

      debug 'registered', data
      @meshbluConnection.identify
        uuid: data.uuid
        token: data.token
      , =>
        callback null, data

  emitRefreshDevices: (callback=->) =>
    @emit 'refreshDevices', deviceUuids: _.pluck @devices, 'uuid'
    callback()

  removeDevices: (callback=->) =>
    devicesToRemove = _.reject @oldDevices, (device) =>
      _.findWhere @devices, uuid: device.uuid

    debug 'devicesToRemove', devicesToRemove

    @async.eachSeries devicesToRemove, (device, cb) =>
      @unsubscribe device
      @deviceManager.removeDevice device, cb
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
    @meshbluConnection.subscribe uuid: device.uuid, token: device.token, types: ['received', 'broadcast'], (result) =>
      return @emit 'error', new Error(result?.error?.message) if result?.error?

  updateDevicePermissions: (devices, callback=->) =>
    @async.eachSeries devices, (device, cb) =>
      return cb() unless device.token?
      @meshbluConnection.device uuid: device.uuid, token: device.token, (result) =>
        return cb new Error(result?.error?.message) if result?.error?

        data = _.pick result.device, 'uuid', 'sendAsWhitelist', 'receiveAsWhitelist', 'configureWhitelist', 'discoverWhitelist'
        data.token = device.token
        data.sendAsWhitelist ?= []
        data.receiveAsWhitelist ?= []
        data.configureWhitelist ?= []
        data.discoverWhitelist ?= []

        data.sendAsWhitelist.push @config.uuid
        data.receiveAsWhitelist.push @config.uuid
        data.configureWhitelist.push @config.uuid
        data.discoverWhitelist.push @config.uuid

        @meshbluConnection.update data, (result) =>
          return cb new Error(result?.error?.message) if result?.error?
          cb()
    , callback

  updateGateblu: (callback=->) =>
    data =
      uuid: @config.uuid
      devices: _.map @devices, (device) => _.pick device, 'uuid', 'connector', 'type', 'stop'
      version: packageJSON.version

    @meshbluConnection.update data, (result) =>
      return callback new Error(result?.error?.message) if result?.error?
      callback()

  unsubscribe: (device) =>
    @meshbluConnection.unsubscribe uuid: device.uuid, token: device.token, types: ['received', 'broadcast'], (result) =>
      return @emit 'error', new Error(result?.error?.message) if result?.error?

  whoami: (callback=->) =>
    @meshbluConnection.whoami {}, (result) =>
      return callback new Error(result?.error?.message) if result?.error?
      callback null, result

module.exports = Gateblu
