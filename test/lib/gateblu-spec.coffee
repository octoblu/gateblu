{EventEmitter} = require 'events'
Gateblu = require '../../lib/gateblu'

describe 'Gateblu', ->
  beforeEach ->
    @fakeConnection = new EventEmitter
    class FakeMeshblu
      createConnection: sinon.stub()

    @fakeMeshblu = new FakeMeshblu
    @fakeMeshblu.createConnection.returns(@fakeConnection)

    @sut = new Gateblu {}, new EventEmitter, meshblu: @fakeMeshblu

  describe 'when receiving a device-start', ->
    beforeEach ->
      @sut.startDevice = sinon.stub()
      @fakeConnection.emit 'message',
        topic: 'device-start'
        payload: '36c690a3-0f61-4b1e-8922-ba0e8c56ddfc'

    it 'should call startDevice', ->
      expect(@sut.startDevice).to.have.been.calledWith '36c690a3-0f61-4b1e-8922-ba0e8c56ddfc'

  describe 'when receiving a device-stop', ->
    beforeEach ->
      @sut.stopDevice = sinon.stub()
      @fakeConnection.emit 'message', topic: 'device-stop', deviceUuid: '36c690a3-0f61-4b1e-8922-ba0e8c56ddfc'

    it 'should call stopDevice', ->
      expect(@sut.stopDevice).to.have.been.calledWith '36c690a3-0f61-4b1e-8922-ba0e8c56ddfc'

  describe 'when receiving a refresh', ->
    beforeEach ->
      @sut.refreshDevices = sinon.stub()
      @fakeConnection.emit 'message', topic: 'refresh'

    it 'should call refreshDevices', ->
      expect(@sut.refreshDevices).to.have.been.called

  describe 'when receiving a refresh-device', ->
    beforeEach ->
      @sut.refreshDevice = sinon.stub()
      @fakeConnection.emit 'message', topic: 'refresh-device', deviceUuid: 'a-uuid', deviceToken: 'a-token'

    it 'should call refreshDevice', ->
      expect(@sut.refreshDevice).to.have.been.calledWith uuid: 'a-uuid', token: 'a-token'

  describe 'when receiving a device-status', ->
    beforeEach ->
      @sut.emit = sinon.stub()
      @fakeConnection.emit 'message', topic: 'device-status', fromUuid: 'a-uuid', payload: {online: true}

    it 'should emit device:status with uuid and token', ->
      expect(@sut.emit).to.have.been.calledWith 'device:status', online: true, uuid: 'a-uuid'
