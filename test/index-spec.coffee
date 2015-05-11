{EventEmitter} = require 'events'
Gateblu = require '../index'
_ = require 'lodash'

describe 'Gateblu', ->
  beforeEach ->
    @fakeConnection = new EventEmitter
    class FakeMeshblu
      createConnection: sinon.stub()

    @fakeMeshblu = new FakeMeshblu
    @fakeMeshblu.createConnection.returns(@fakeConnection)
    @deviceManager = new EventEmitter

  describe 'is an EventEmitter', ->
    beforeEach ->
      @sut = new Gateblu {}, @deviceManager, meshblu: @fakeMeshblu

    it 'should have an on method', ->
      expect(@sut.on).to.exist

  describe 'on: notReady', ->
    describe 'when unregistered and no uuid', ->
      beforeEach ->
        @sut = new Gateblu {}, @deviceManager, meshblu: @fakeMeshblu
        @sut.register = sinon.spy()
        @fakeConnection.emit 'notReady'

      it 'should call @register', ->
        expect(@sut.register).to.have.been.called

    describe 'when unregistered and config has a uuid', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.register = sinon.spy()
        @fakeConnection.emit 'notReady'

      it 'should not call @register', ->
        expect(@sut.register).not.to.have.been.called

  describe 'on: ready', ->
    describe 'as if the gateway was just registered and identified', ->
      beforeEach ->
        @config = {}
        @sut = new Gateblu @config, @deviceManager, meshblu: @fakeMeshblu
        @sut.refreshConfig = sinon.spy()
        @fakeConnection.emit 'ready', uuid: 'spork', token: 'york'

      it 'should set config.uuid', ->
        expect(@config.uuid).to.equal 'spork'

      it 'should set config.token', ->
        expect(@config.token).to.equal 'york'

      it 'should call refreshConfig on meshblu', ->
        expect(@sut.refreshConfig).to.have.been.called

  describe 'on: config', ->
    describe 'gateway config', ->
      beforeEach ->
        @config = uuid: 'bjork'
        @sut = new Gateblu @config, @deviceManager, meshblu: @fakeMeshblu
        @sut.refreshConfig = sinon.spy()
        @fakeConnection.emit 'config', uuid: 'bjork', token: 'york'

      it 'should call refreshConfig', ->
        expect(@sut.refreshConfig).to.have.been.called

    describe 'device config', ->
      beforeEach ->
        @config = uuid: 'stork'
        @sut = new Gateblu @config, @deviceManager, meshblu: @fakeMeshblu
        @sut.refreshConfig = sinon.spy()
        @fakeConnection.emit 'config', uuid: 'dork', token: 'york'

      it 'should not call refreshConfig', ->
        expect(@sut.refreshConfig).not.to.have.been.called

  describe 'register', ->
    beforeEach ->
      @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
      @fakeConnection.register = sinon.stub().yields {}
      @fakeConnection.identify = sinon.spy()
      @sut.register()

    it 'should call fakeMeshblu.register with type', ->
      expect(@fakeConnection.register).to.have.been.calledWith type: 'device:gateblu'

    it 'should call fakeConnection.identify', ->
      expect(@fakeConnection.identify).to.have.been.called

  describe 'refreshConfig', ->
    beforeEach ->
      @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
      @fakeConnection.whoami = sinon.stub().yields some: 'thing', devices: []
      @sut.emit = sinon.spy()
      @sut.refreshDevices = sinon.spy()
      @sut.refreshConfig()

    it 'should call meshblu.whoami', ->
      expect(@fakeConnection.whoami).to.have.been.calledWith {}

    it 'should emit the data returned', ->
      expect(@sut.emit).to.have.been.calledWith 'gateblu:config', uuid: 'guid'

    it 'should call refreshDevices', ->
      expect(@sut.refreshDevices).to.have.been.calledWith []

  describe 'refreshDevices', ->
    describe 'when called for the first time', ->
      beforeEach ->
        @devices = [uuid: 'device']
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.getMeshbluDevice = sinon.stub().yields null, uuid: 'device'
        @sut.addDevices = sinon.spy()
        @sut.removeDevices = sinon.spy()
        @sut.stopDevices = sinon.spy()
        @sut.startDevices = sinon.spy()
        @sut.refreshDevices @devices

      it 'should call getMeshbluDevice', ->
        expect(@sut.getMeshbluDevice).to.have.been.calledWith uuid: 'device'

      it 'should set @devices', ->
        expect(@sut.devices).to.deep.equal @devices

      it 'should set @oldDevices', ->
        expect(@sut.oldDevices).to.deep.equal @devices

      it 'should call addDevices', ->
        expect(@sut.addDevices).to.have.been.called

      it 'should call stopDevices', ->
        expect(@sut.stopDevices).to.have.been.called

      it 'should call startDevices', ->
        expect(@sut.startDevices).to.have.been.called

      it 'should call removeDevices', ->
        expect(@sut.removeDevices).to.have.been.called

  describe 'addDevices', ->
    describe 'when there are no changes', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}]
        @sut.devices = _.cloneDeep @sut.oldDevices
        @deviceManager.addDevice = sinon.spy()
        @sut.subscribe = sinon.spy()
        @sut.addDevices()

      it 'should not call deviceManager.addDevice', ->
        expect(@deviceManager.addDevice).not.to.have.been.called

      it 'should not call subscribe', ->
        expect(@sut.subscribe).not.to.have.been.called

    describe 'when there is fewer device', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}]
        @sut.devices = [{uuid: 'fork'}, {uuid: 'chork'}]
        @deviceManager.addDevice = sinon.spy()
        @sut.subscribe = sinon.spy()
        @sut.addDevices()

      it 'should call deviceManager.addDevice', ->
        expect(@deviceManager.addDevice).to.have.been.calledWith uuid: 'chork'

      it 'should call subscribe', ->
        expect(@sut.subscribe).to.have.been.calledWith uuid: 'chork'

    describe 'when there are two fewer devices', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}]
        @sut.devices = [{uuid: 'fork'}, {uuid: 'chork'}, {uuid: 'mork'}]
        @deviceManager.addDevice = sinon.spy()
        @sut.subscribe = sinon.spy()
        @sut.addDevices()

      it 'should call deviceManager.addDevice', ->
        expect(@deviceManager.addDevice).to.have.been.calledWith uuid: 'chork'
        expect(@deviceManager.addDevice).to.have.been.calledWith uuid: 'mork'

      it 'should call subscribe', ->
        expect(@sut.subscribe).to.have.been.calledWith uuid: 'chork'
        expect(@sut.subscribe).to.have.been.calledWith uuid: 'mork'

  describe 'removeDevices', ->
    describe 'when there are no changes', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}]
        @sut.devices = _.cloneDeep @sut.oldDevices
        @deviceManager.removeDevice = sinon.spy()
        @sut.unsubscribe = sinon.spy()
        @sut.removeDevices()

      it 'should not call deviceManager.removeDevice', ->
        expect(@deviceManager.removeDevice).not.to.have.been.called

      it 'should not call unsubscribe', ->
        expect(@sut.unsubscribe).not.to.have.been.called

    describe 'when there is fewer device', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}, {uuid: 'chork'}]
        @sut.devices = [{uuid: 'fork'}]
        @deviceManager.removeDevice = sinon.spy()
        @sut.unsubscribe = sinon.spy()
        @sut.removeDevices()

      it 'should call deviceManager.removeDevice', ->
        expect(@deviceManager.removeDevice).to.have.been.calledWith uuid: 'chork'

      it 'should call unsubscribe', ->
        expect(@sut.unsubscribe).to.have.been.calledWith uuid: 'chork'

    describe 'when there are two fewer devices', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}, {uuid: 'chork'}, {uuid: 'mork'}]
        @sut.devices = [{uuid: 'fork'}]
        @deviceManager.removeDevice = sinon.spy()
        @sut.unsubscribe = sinon.spy()
        @sut.removeDevices()

      it 'should call deviceManager.removeDevice', ->
        expect(@deviceManager.removeDevice).to.have.been.calledWith uuid: 'chork'
        expect(@deviceManager.removeDevice).to.have.been.calledWith uuid: 'mork'

      it 'should call unsubscribe', ->
        expect(@sut.unsubscribe).to.have.been.calledWith uuid: 'chork'
        expect(@sut.unsubscribe).to.have.been.calledWith uuid: 'mork'


  describe 'startDevices', ->
    describe 'when there are no changes', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork', stop: true}]
        @sut.devices = _.cloneDeep @sut.oldDevices
        @deviceManager.startDevice = sinon.spy()
        @sut.startDevices()

      it 'should not call deviceManager.startDevice', ->
        expect(@deviceManager.startDevice).not.to.have.been.called

    describe 'when there is a starting device', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}, {uuid: 'chork'}]
        @sut.devices = [{uuid: 'chork', stop: false}]
        @deviceManager.startDevice = sinon.spy()
        @sut.startDevices()

      it 'should call deviceManager.startDevice', ->
        expect(@deviceManager.startDevice).to.have.been.calledWith uuid: 'chork', stop: false

    describe 'when there are two starting devices', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}, {uuid: 'chork'}, {uuid: 'mork'}]
        @sut.devices = [{uuid: 'fork'}, {uuid: 'chork', stop: false}, {uuid: 'mork', stop: false}]
        @deviceManager.startDevice = sinon.spy()
        @sut.startDevices()

      it 'should call deviceManager.startDevice', ->
        expect(@deviceManager.startDevice).to.have.been.calledWith uuid: 'chork', stop: false
        expect(@deviceManager.startDevice).to.have.been.calledWith uuid: 'mork', stop: false

  describe 'stopDevices', ->
    describe 'when there are no changes', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork', stop: true}]
        @sut.devices = _.cloneDeep @sut.oldDevices
        @deviceManager.stopDevice = sinon.spy()
        @sut.stopDevices()

      it 'should not call deviceManager.stopDevice', ->
        expect(@deviceManager.stopDevice).not.to.have.been.called

    describe 'when there is a stopped device', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}, {uuid: 'chork'}]
        @sut.devices = [{uuid: 'chork', stop: true}]
        @deviceManager.stopDevice = sinon.spy()
        @sut.stopDevices()

      it 'should call deviceManager.stopDevice', ->
        expect(@deviceManager.stopDevice).to.have.been.calledWith uuid: 'chork', stop: true

    describe 'when there are two stopped devices', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @sut.oldDevices = [{uuid: 'fork'}, {uuid: 'chork'}, {uuid: 'mork'}]
        @sut.devices = [{uuid: 'fork'}, {uuid: 'chork', stop: true}, {uuid: 'mork', stop: true}]
        @deviceManager.stopDevice = sinon.spy()
        @sut.stopDevices()

      it 'should call deviceManager.stopDevice', ->
        expect(@deviceManager.stopDevice).to.have.been.calledWith uuid: 'chork', stop: true
        expect(@deviceManager.stopDevice).to.have.been.calledWith uuid: 'mork', stop: true

  describe 'getMeshbluDevice', ->
    describe 'when the device does not exist', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @fakeConnection.devices = sinon.stub().yields error: {}
        @sut.getMeshbluDevice uuid: '123', token: '456', (@error) =>

      it 'should have an error', ->
        expect(@error).to.exist

    describe 'when the device does exist', ->
      beforeEach ->
        @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
        @fakeConnection.devices = sinon.stub().yields devices: [{uuid: '123', stuff: []}]
        @sut.getMeshbluDevice uuid: '123', token: '456', (@error, @result) =>

      it 'should not have an error', ->
        expect(@error).not.to.exist

      it 'should return a result merged with the original device (to preserve token)', ->
        expect(@result).to.deep.equal uuid: '123', token: '456', stuff: []

  describe 'subscribe', ->
    beforeEach ->
      @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
      @fakeConnection.subscribe = sinon.spy()
      @sut.subscribe uuid: 'devid', token: 'tokin'

    it 'should call subscribe on meshblu', ->
      expect(@fakeConnection.subscribe).to.have.been.calledWith uuid: 'devid', token: 'tokin'

  describe 'unsubscribe', ->
    beforeEach ->
      @sut = new Gateblu uuid: 'guid', @deviceManager, meshblu: @fakeMeshblu
      @fakeConnection.unsubscribe = sinon.spy()
      @sut.unsubscribe uuid: 'devid', token: 'tokin'

    it 'should call unsubscribe on meshblu', ->
      expect(@fakeConnection.unsubscribe).to.have.been.calledWith uuid: 'devid', token: 'tokin'
