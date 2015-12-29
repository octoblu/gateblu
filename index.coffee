_            = require 'lodash'
debug        = require('debug')('gateblu:index')
packageJSON  = require './package.json'
{EventEmitter2} = require 'eventemitter2'



class Gateblu extends EventEmitter2


  constructor: (@config, @deviceManager, dependencies={}) ->
    @TOKEN_TAG='gateblu-core'
    @meshblu = dependencies.meshblu || require 'meshblu'
    @async = dependencies.async || require 'async'
    @queue = @async.queue(@refreshConfigWorker)
    @addToRefreshQueue = _.throttle @addToRefreshQueueImmediately, 2000, trailing: true, leading: false
    @loggerUuid = process.env.GATEBLU_LOGGER_UUID || '427e5737-633e-4ad3-944d-984d258fe4fa'

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

  sendLogMessage: (key, msg, topic) =>
    @meshbluConnection.message
      devices: [ @loggerUuid ]
      payload:
        gatebluUuid: @config.uuid
        "#{key}": msg
        topic: topic
        source: 'gateblu'

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
      @sendLogMessage 'connected', true, 'meshblu-connection-ready'
      @ensureType =>
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

  generateDeviceTokens: (callback=->) =>
    @async.eachSeries @devices, (device, cb) =>
      @meshbluConnection.revokeTokenByQuery tag: @TOKEN_TAG, =>
        @meshbluConnection.generateAndStoreToken uuid: device.uuid, tag: @TOKEN_TAG, (result) =>
          if result?.error?
            @sendLogMessage 'error', result?.error?.message, 'generate-device-tokens'
            return cb new Error(result?.error?.message)
          device.token = result?.token
          cb()
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
        return callback new Error(result.error.message)
    , 500

  ensureType: (callback=->) =>
    debug 'ensureType'
    @meshbluConnection.whoami {}, (data) =>
      return callback() if data.type?
      debug 'no type set, updating'
      @meshbluConnection.update type: 'device:gateblu', (result) =>
        if result?.error?
          @sendLogMessage 'error', result?.error?.message, 'ensure-type-update'
          return callback new Error(result?.error?.message)
        callback()

  refreshConfig: (callback=->) =>
    @whoami (error, data) =>
      if error?
        @sendLogMessage 'error', error, 'whoami-refresh-config'
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
      if error?
        @sendLogMessage 'error', error, 'map-devices'
        return callback error
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
          @sendLogMessage 'error', error, 'refresh-devices'
          return callback error

        @oldDevices = _.cloneDeep devices
        callback()

  register: (options={}, callback=->) =>
    debug 'registering'
    options.type = 'device:gateblu'
    @meshbluConnection.register options, (data) =>
      if data?.error?
        @sendLogMessage 'error', data?.error?.message, 'register'
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
      if result?.error?
        @sendLogMessage 'error', result?.error?.message, 'subscribe'
        return @emit 'error', new Error(result?.error?.message)

  updateDevicePermissions: (devices, callback=->) =>
    @async.eachSeries devices, (device, cb) =>
      return cb() unless device.token?
      @meshbluConnection.device uuid: device.uuid, token: device.token, (result) =>
        if result?.error?
          @sendLogMessage 'error', result?.error?.message, 'device-permissions'
          return cb new Error(result?.error?.message)

        whitelistedKeys = ['uuid', 'sendAsWhitelist', 'receiveAsWhitelist', 'configureWhitelist', 'discoverWhitelist']
        data = _.pick result.device, whitelistedKeys
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
          if result?.error?
            @sendLogMessage 'error', result?.error?.message, 'update-permissions'
            return cb new Error(result?.error?.message)
          cb()
    , callback

  updateGateblu: (callback=->) =>
    data =
      uuid: @config.uuid
      devices: _.map @devices, (device) => _.pick device, 'uuid', 'connector', 'type', 'stop'
      version: packageJSON.version

    @meshbluConnection.update data, (result) =>
      if result?.error?
        @sendLogMessage 'error', result?.error?.message, 'update-gateblu'
        return callback new Error(result?.error?.message)
      callback()

  unsubscribe: (device) =>
    @meshbluConnection.unsubscribe uuid: device.uuid, token: device.token, types: ['received', 'broadcast'], (result) =>
      if result?.error?
        @sendLogMessage 'error', result?.error?.message, 'unsubscribe'
        return @emit 'error', new Error(result?.error?.message)

  whoami: (callback=->) =>
    @meshbluConnection.whoami {}, (result) =>
      if result?.error?
        @sendLogMessage 'error', result?.error?.message, 'whoami'
        return callback new Error(result?.error?.message)
      callback null, result

module.exports = Gateblu
