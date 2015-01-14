{EventEmitter} = require 'events'
Gateblu = require '../../lib/gateblu'

describe 'Gateblu', ->
  beforeEach ->
    @sut = new Gateblu({}, new EventEmitter, meshblu: FakeMeshblu)

  it 'exist', ->
    expect(@sut).to.exist

class FakeMeshblu extends EventEmitter
  @createConnection: => new FakeMeshblu

  refreshDevices: =>
    @::foo = 2

