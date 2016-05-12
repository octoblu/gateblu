_               = require 'lodash'
debug           = require('debug')('gateblu:index')
packageJSON     = require './package.json'
{EventEmitter2} = require 'eventemitter2'

class Gateblu extends EventEmitter2
  constructor: (@config, @deviceManager, dependencies={}) ->
    @TOKEN_TAG = 'gateblu-core'
    @meshblu = dependencies.meshblu || require 'meshblu'
    @async = dependencies.async || require 'async'
    @queue = @async.queue @refreshConfigWorker
    @addToRefreshQueue = _.throttle @addToRefreshQueueImmediately, 2000, trailing: true, leading: false

    @createConnection()

  addDevices: (callback=->) =>
    devicesToAdd = _.reject @devices, (device) =>
      _.findWhere @oldDevices, uuid: device.uuid

    debug 'devicesToAdd', devicesToAdd

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
      @addToRefreshQueue()
      @emit 'ready', data

    @meshbluConnection.on 'config', (data) =>
      return @addToRefreshQueue() if data.uuid == @config.uuid
      @emit 'device:config', data

    @meshbluConnection.on 'message', (data) =>
      data.devices = [data.devices] if _.isString data.devices
      uuids = _.clone data.devices
      if _.contains uuids, '*'
        _.pull uuids, '*'
        uuids.push data.fromUuid

      if _.contains uuids, @config.uuid
        @emit 'message', data

      intersection = _.intersection uuids, _.pluck(@devices, 'uuid')
      @emit 'device:message', data unless _.isEmpty intersection

    @meshbluConnection.on 'unregistered', (data) =>
      @addToRefreshQueue()

    @meshbluConnection.on 'error', (error) =>
      debug 'error from meshblu', error
      @emit 'error', error

  generateDeviceTokens: (callback=->) =>
    @async.eachSeries @devices, (device, done) =>
      return done() if device.token?
      @meshbluConnection.revokeTokenByQuery tag: @TOKEN_TAG, =>
        @meshbluConnection.generateAndStoreToken uuid: device.uuid, tag: @TOKEN_TAG, (result) =>
          if result?.error?
            return done new Error(result?.error?.message)
          device.token = result?.token
          done()
    , callback

  getMeshbluDevice: (device, callback=->) =>
    debug 'meshblu.device', device
    return callback null unless device.uuid?
    _.delay =>
      @meshbluConnection.device uuid: device.uuid, (result) =>
        return callback new Error('getMeshbluDevice request failed') unless result?
        return callback null, result.device if result.device?
        return callback new Error('getMeshbluDevice received invalid response') unless result.error?
        return callback null if result.error.code == 404
        return callback null if result.error == 'Forbidden'
        return callback new Error(result.error.message)
    , 500

  refreshConfig: (callback=->) =>
    @whoami (error, data) =>
      if error?
        return callback error
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
      deviceUuids = _.pluck devices, 'uuid'
      oldDeviceUuids = _.pluck @oldDevices, 'uuid' if @oldDevices?
      return callback() if _.eq deviceUuids, oldDeviceUuids

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
        if error?
          return callback error
        @oldDevices = _.cloneDeep devices
        callback()

  emitRefreshDevices: (callback=->) =>
    @emit 'refreshDevices', deviceUuids: _.pluck @devices, 'uuid'
    callback()

  removeDevices: (callback=->) =>
    devicesToRemove = _.reject @oldDevices, (device) =>
      return _.findWhere @devices, uuid: device.uuid

    debug 'devicesToRemove', devicesToRemove

    @async.eachSeries devicesToRemove, (device, done) =>
      @unsubscribe device
      @deviceManager.removeDevice device, done
    , callback

  startDevices: (callback=->) =>
    devicesToStart = _.filter @devices, (device) ->
      return device.stop == false || !device.stop?

    debug 'devicesToStart', _.pluck devicesToStart, 'uuid'

    @async.eachSeries devicesToStart, (device, callback) =>
      @deviceManager.startDevice device, callback
    , callback

  stopDevices: (callback=->) =>
    devicesToStop = _.where @devices, stop: true

    debug 'devicesToStop', devicesToStop

    @async.eachSeries devicesToStop, (device, done) =>
      @deviceManager.stopDevice device, done
    , callback

  subscribe: (device) =>
    { uuid, token } = device
    types = ['received', 'broadcast']
    @meshbluConnection.subscribe {uuid, token, types}, (result) =>
      if result?.error?
        return @emit 'error', new Error(result?.error?.message)

  updateDevicePermissions: (devices, callback=->) =>
    @async.eachSeries devices, (device, done) =>
      return done() unless device.token?
      { uuid, token } = device
      @meshbluConnection.device { uuid, token }, (result) =>
        if result?.error?
          return done new Error(result?.error?.message)

        whitelistedKeys = ['uuid', 'sendAsWhitelist', 'receiveAsWhitelist', 'configureWhitelist', 'discoverWhitelist']
        data = _.pick result.device, whitelistedKeys
        data.token = token
        data.sendAsWhitelist ?= []
        data.receiveAsWhitelist ?= []
        data.configureWhitelist ?= []
        data.discoverWhitelist ?= []

        data.sendAsWhitelist.push @config.uuid
        data.receiveAsWhitelist.push @config.uuid
        data.configureWhitelist.push @config.uuid
        data.discoverWhitelist.push @config.uuid

        @meshbluConnection.update data, (result) =>
          if result?.error?
            return done new Error(result?.error?.message)
          done()
    , callback

  updateGateblu: (callback=->) =>
    data =
      uuid: @config.uuid
      version: packageJSON.version

    @meshbluConnection.update data, (result) =>
      if result?.error?
        return callback new Error(result?.error?.message)
      callback()

  unsubscribe: (device) =>
    { uuid, token } = device
    types = ['received', 'broadcast']
    @meshbluConnection.unsubscribe { uuid, token, types }, (result) =>
      if result?.error?
        return @emit 'error', new Error(result?.error?.message)

  whoami: (callback=->) =>
    @meshbluConnection.whoami {}, (result={}) =>
      if result.error?
        return callback new Error(result.error?.message)
      callback null, result

module.exports = Gateblu
