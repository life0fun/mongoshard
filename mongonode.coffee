#!/usr/bin/env coffee

mongo = require 'mongodb'
Hook = require('hook.io').Hook

host = if process.env['MONGO_NODE_DRIVER_HOST'] then process.env['MONGO_NODE_DRIVER_HOST'] else 'localhost'
port = if process.env['MONGO_NODE_DRIVER_PORT'] then process.env['MONGO_NODE_DRIVER_PORT'] else mongo.Connection.DEFAULT_PORT

host = 'node.am.colorcloud.com'
port = 10000

# with callback, there is no global variable to store the ref, 
# need to pass ref to callback cascade
# db.open() callback is the top entry point for mongo backed-up project.
# because async db open succeed only when callback invoked.

class MongoNode   # this closure wraps API to location.locs collection
	constructor: (@dbname) ->
		@hook = new Hook({name:'mongo', debug:false})
		@server = new mongo.Server host, port, {}
		@client = new mongo.Db @dbname, @server
		@db = undefined

		@hook.start()
		@bindEvent()
		console.log 'constructor with db: ' + @dbname

	open: (cb) ->
		@client.open (err, db) =>  #funcs created with fat arrow can access `this` where they are defed
			if err
				console.log 'open db ' + @dbname + ' failed:' + err
			else
				console.log 'open db ' + @dbname + ' successful'
				@db = db  # set the db conn handle here
				cb()

	# factory pattern, create/open database
	@create: (dbname, option) ->
		m = new MongoNode(dbname)
		if typeof options is 'object'
			for own key, value of options
				m[key] = value
		return m

	bindEvent: ->
		@hook.on 'hook::ready', () =>
			console.log 'mongo hook ready...'
			if @db?
				@hook.emit 'dbopen', {}, (err, data) ->
					console.log 'mongo dbopen processed!'
			
		process.on 'SIGINT', () =>
			@client.close()

	wait: (funclist, done) ->
		counter = funclist.length
		cb = () =>
			counter -= 1
			if not counter
				done.call(this)

		for c in funclist     # exec each func in the list with the same callback, which reduce counter
			c.call(this, cb)  # once counter reached 0, done func got called. 

	createCollection: (col, callback) ->
		#@client.createCollection col, @testAddLocation
		@client.createCollection col, callback
	
	# make index on latlng field, the field must be either a sub-object
	# or array where the first 2 elements are x,y { "latlng" : [ 42.005753, -88.102734 ] }
	indexLocation: (colname) ->
		@db.collection colname, (err, collection) =>
			collection.ensureIndex {latlng:'2d'}, (err, result) ->
				console.log 'ensureIndex: ' + err + ' : ' + result

	addLoc: (locobj) ->
		console.log 'mongo addLoc:', locobj
		@db.collection 'locs', (err, collection) =>
			console.log 'db.collection err:', err if err?
			@insertCol collection, locobj
	
	# add a location
	insertCol: (collection, locobj) ->
		console.log 'mongo inserCol: ' + JSON.stringify(locobj)
		if locobj._id
			collection.save locobj, (err, docs) ->
				console.log 'mongo update err: ', err if err?
		else
			collection.insert locobj, (err, docs) ->
				console.log 'mongo insert err: ', err if err?

	# update thru save, save saw doc already had '_id' field, then update
	saveLoc: (loc) ->
		@db.collection 'locs', (err, collection) ->
			collection.save loc, (err, docs) ->
				console.log 'saved loc:', docs
	
	# this is the callback feed to db colletion upon creation for testing.
	testAddLocation: (err, collection) =>
		console.log 'adding location to collection...'
		l = {}
		l.latlng = [ 42.005753, -88.102734 ]
		l.name = 'a'
		@insertCol collection, l
		m = {}  # we are in a callback, need closure or different obj
		m.latlng = [ 42.296108, -88.003106 ]
		m.name = 'b'
		@insertCol collection, m
		n = {}
		n.latlng = [ 42.300405, -87.999999 ]
		n.name = 'c'
		@insertCol collection, n

		collection.ensureIndex {latlng:'2d'}, (err, result) ->
			console.log 'ensureIndex: ' + err + ' : ' + result
		
	formatQueryObject: (args) ->
		#The distance unit is the same as in your coordinate system
		#{latlng:{$near:[42.3,-88.0], $maxDistance: 0.10}}
		#{stm:new Date("2011-11-14 21:43:35.370Z")}
		#{stm:{$gte:new Date(2011, 10, 14, 15, 43, 35, 370)}}
		#{latlng:{$near: [1,5], $maxDistance:5}, $where:'this.stm.getHours() >= 15 && this.stm.getHours() <= 21'}
		console.log 'format args:', args
		queryobj = {}
		if args.latlng
			queryobj.latlng = {}
			queryobj.latlng.$near = args.latlng
			queryobj.latlng.$maxDistance = args.dist
		if args.where.sdate and args.where.sdate isnt '0'
			ymd = args.where.sdate.split('-')
			queryobj.stm = {}
			queryobj.stm.$gt = new Date(ymd[0], ymd[1]-1, ymd[2])  # month starts from 0
		if args.where.edate and args.where.edate isnt '0'
			ymd = args.where.edate.split('-')
			queryobj.etm = {}
			queryobj.etm.$lt = new Date(ymd[0], ymd[1]-1, ymd[2])  # month starts from 0

		hourgap = ''  # check against the end time
		if args.where.shour and args.where.shour isnt '0'
			hourgap = ' this.etm.getHours() >= ' + args.where.shour
		if args.where.ehour and args.where.ehour isnt '0'
			if hourgap isnt ''
				hourgap += ' && '
			hourgap += 'this.etm.getHours() <= ' + args.where.ehour

		if hourgap isnt ''
			queryobj.$where = hourgap

		if args.where.duration
			queryobj.dur = args.where.duration

		console.log 'formatQueryObj:', queryobj
		return queryobj

	# db.collection.find({x:vx}) 
	queryLoc: (whereobj, cb) ->
		console.log 'query collection: db.col.find({x:vx})'
		limit = 1000   # fsq rate limit hourly
		@db.collection 'locs', (err, collection) ->
			collection.find	whereobj, {'limit':limit}, (err, cursor) ->
				cursor.each (err, doc) ->
					console.log 'query collection err:', err if err
					cb doc
	
	# search a location by latlng dist and give back throu callback
	searchLocation: (queryobj, cb) ->
		console.log 'searchLocation:' + queryobj.latlng.$near
		@db.collection 'locs', (err, collection) ->
			collection.ensureIndex {latlng:'2d'}, (err, result) -> console.log err if err
			collection.find queryobj, {limit:100}, (err, cursor) ->
				console.log 'db find err:' + err if err
				cursor.each (err, doc) ->
					console.log doc if doc?
					cb doc if doc?

    # callback entry for query, collection is passed in opened from col name
	testSearchLocation: () ->
		console.log 'testsearching....'
		loc = {}
		loc.latlng = [42.280, -88.000]
		loc.dist = 0.1
		loc.where = {}
		#loc.where.sdate = '2011-6-5'
		#loc.where.edate = '2011-6-7'
		#loc.where.shour = '5'
		#loc.where.ehour = '7'
		queryobj = @formatQueryObject(loc)
		@searchLocation queryobj, (doc) ->
			console.log 'searched:', doc

	# test insert
	testInsert: ->
		@client.open (err, db) =>  #funcs created with fat arrow can access `this` where they are defed
			console.log 'init collection inside db open callback'
			#db.system.namespaces.find { name: 'location' }, (err, col) -> console.log 'found:'
			db.dropCollection 'locs', (err, result) =>
				db.collection 'locs', @testAddLocation

	# test query
	test: ->
		@testSearchLocation()

exports.create = MongoNode.create

loc = MongoNode.create('location')
loc.wait([loc.open], loc.test)
