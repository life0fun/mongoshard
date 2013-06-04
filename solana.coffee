#!/usr/bin/env coffee
#
# FSQ = require('fsq')
# client = FSQ.create(
# client.ready()

EventEmitter = require('events').EventEmitter
path = require 'path'
ctx = require 'zeromq'

FSQ = require './fsq'
M = require './mongonode'

class Node extends EventEmitter
	constructor: (@_ID) ->

class SOLANA extends Node
	constructor: (@dbname) ->
		@mongo = M.create('location')
		@fsq = FSQ.create('locationstream')
		console.log 'creating solana...'

	# factory pattern
	@create: (dbname, option) ->
		sol = new SOLANA(dbname)
		if typeof options is 'object'
			for own key, value of options
				sol[key] = value
		return sol
	
############################
# zeromq socket
############################

	ready: (host, port) ->
		host ?= 'localhost'
		port ?= 5555
		@sock.bind( "tcp://"+host+":"+port, (err) -> console.log err if err )
		console.log @_ID + ' listening on :', host, port
		self = this
		tof = do (self) ->
			-> # return a func, wrap with the passed in sock
				self.sendMsg 'SRV', [ 'hello from cli']
		#setTimeout tof, 1000

	parseMsg: (args) ->
		msg = []
		for arg in args
			msg.push arg.toString()
		return msg

	bindEvent: ->
		@sock.on 'message', (addr, data) =>
			msg = @parseMsg arguments
			# func created by => can access this property where they are defined.
			@processMsg(msg)

		process.on 'SIGINT', () =>
			@sock.close()

	# process msg sent to worker
	processMsg: (msg) ->
		from = msg.shift()
		console.log 'client recvd rep <<< ', msg.toString()
		@sendMsg from, msg

	sendMsg: (addr, msg) ->
		msg.unshift addr  #prepend dest addr first
		console.log 'cli >>> ', msg
		@sock.send.apply @sock, msg


############################
#  query fsq and insert to mongo
############################

	formatLocation: (v) ->
		loc = {}
		loc.latlng = [ v.location.lat, v.location.lng ]
		loc.name = v.name
		loc.addr = v.location.address
		loc.cat = v.categories[0].name
		return loc

	addLocation: (cl, v) =>  # the func invoked as callback, hence need fat arrow.
		loc = @formatLocation v
		loc.imei = cl.imei
		console.log loc
		@mongo.addLocObj loc

	searchVenues: (c) ->
		@fsq.searchVenues c, @addLocation

	mapClusters: (clusterl) ->
		for c in clusterl
			do (c) =>
				@searchVenues c

exports.create = SOLANA.create
sol = new SOLANA('location')
cl = [ {imei:'1234', lat:'42.288', lng:'-88.000'} ]
sol.mapClusters cl
