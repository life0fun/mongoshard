#!/usr/bin/env coffee

mongo = require 'mongodb'
Hook = require('hook.io').Hook

host = if process.env['MONGO_NODE_DRIVER_HOST'] then process.env['MONGO_NODE_DRIVER_HOST'] else 'localhost'
port = if process.env['MONGO_NODE_DRIVER_PORT'] then process.env['MONGO_NODE_DRIVER_PORT'] else mongo.Connection.DEFAULT_PORT

#host = 'ecomm.am.colorcloud.com'

# with callback, there is no global variable to store the ref, 
# need to pass ref to callback cascade
# db.open() callback is the top entry point for mongo backed-up project.
# because async db open succeed only when callback invoked.

class MongoDup   # this closure wraps API to location.locs collection
	constructor: (@srcsvr, @srcport, @dstsvr, @dstport, @dbname) ->
		@hook = new Hook({name:'mongo', debug:false})
		@srcm = new mongo.Server @srcsvr, @srcport, {}
		@dstm = new mongo.Server @dstsvr, @dstport, {}
		@srcclient = new mongo.Db @dbname, @srcm
		@dstclient = new mongo.Db @dbname, @dstm
		@srcdb = undefined
		@dstdb = undefined

		@hook.start()
		@bindEvent()
		console.log 'constructor with db: ' + @dbname

	opensrc: (cb) ->
		@srcclient.open (err, db) =>
			#funcs created with fat arrow can access `this` where they are defed
			if err
				console.log 'open db ' + @dbname + ' failed:' + err
			else
				console.log 'open src db ' + @dbname + ' successful'
				@srcdb = db  # set the db conn handle here
				cb()

	opendst: (cb) ->
		@dstclient.open (err, db) =>
			#funcs created with fat arrow can access `this` where they are defed
			if err
				console.log 'open dst db ' + @dbname + ' failed:' + err
			else
				console.log 'open dst db ' + @dbname + ' successful'
				@dstdb = db  # set the db conn handle here
				cb()

	# factory pattern, create/open database
	@create: (srcsvr, srcport, dstsvr, dstport, dbname, option) ->
		m = new MongoDup(srcsvr, srcport, dstsvr, dstport, dbname)
		if typeof options is 'object'
			for own key, value of options
				m[key] = value
		return m

	bindEvent: ->
		@hook.on 'hook::ready', () =>
			console.log 'mongo hook ready...'
			if @srcdb?
				@hook.emit 'dbopen', {}, (err, data) ->
					console.log 'mongo dbopen processed!'
			
		process.on 'SIGINT', () =>
			@client.close()

	
	wait: (callbacks, done) ->
		console.log 'waiting', callbacks
		counter = callbacks.length
		# define next func obj, which will reduce the latch, 
		# and pass it to all callback to be invoked upon callback happened.
		next = () =>
			counter -= 1
			if not counter
				done.call(this) # passing our obj as this to the function.
		for c in callbacks
			c.call(this, next)  # passing this to callback, which is our object.

	createCollection: (col, callback) ->
		#@client.createCollection col, @testAddLocation
		@client.createCollection col, callback
	
	# make index on latlng field, the field must be either a sub-object
	# or array where the first 2 elements are x,y { "latlng" : [ 42.005753, -88.102734 ] }
	indexLocation: (colname) ->
		@srcdb.collection colname, (err, collection) =>
			collection.ensureIndex {latlng:'2d'}, (err, result) ->
				console.log 'ensureIndex: ' + err + ' : ' + result

	addLoc: (locobj) ->
		console.log 'mongo addLoc:', locobj
		@srcdb.collection 'locs', (err, collection) =>
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
		@srcdb.collection 'locs', (err, collection) ->
			collection.save loc, (err, docs) ->
				console.log 'saved loc:', docs
	
	# db.collection.find({x:vx}) 
	queryLoc: (whereobj, cb) ->
		console.log 'query collection: db.col.find({x:vx})'
		limit = 10000   # fsq rate limit hourly
		@srcdb.collection 'locs', (err, collection) ->
			collection.find	whereobj, (err, cursor) ->
				cursor.each (err, doc) ->
					console.log 'query collection err:', err if err
					cb doc

	# dup, read from local db and dump to cluster
	dup: () ->
		@dstdb.collection 'locs', (err, collection) =>
			tot = 0
			cb = (doc) =>
				if doc
					delete doc._id
					tot += 1
					console.log 'tot:', tot, ' dup get record:', doc
					collection.insert doc, (err, docs) ->
						console.log 'inserted loc to dst:', docs
			@queryLoc({venue:{$exists:true}}, cb)
	
	# search a location by latlng dist and give back throu callback
	searchLocation: (loc, cb) ->
		console.log 'searchLocation:' + loc.latlng + ':' + loc.dist
		#The distance unit is the same as in your coordinate system
		#collection.find {latlng:{$near:[42.3,-88.0], $maxDistance: 0.10}}, (err, cursor) ->
		@srcdb.collection 'locs', (err, collection) =>
			collection.ensureIndex {latlng:'2d'}, (err, result) -> console.log err if err
			#collection.find {_id:'4eb577f02fb7add25200368b', latlng:{$near:loc.latlng, $maxDistance: loc.dist}}, {limit:1}, (err, cursor) =>
			#collection.find {stm:new Date("2011-11-14 21:43:35.370Z")}, {limit:1}, (err, cursor) =>
			#collection.find {stm:{$gte:new Date(2011, 10, 14, 15, 43, 35, 370)}},{limit:1}, (err, cursor) =>
			collection.find {$where:'this.stm.getHours() >= 15 && this.stm.getHours() <= 21'}, {limit:1}, (err, cursor) =>
				console.log 'db find err:' + err if err
				cursor.each (err, doc) =>
					console.log doc if doc?
					cb doc if doc?

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
		
    # callback entry for query, collection is passed in opened from col name
	testSearchLocation: () ->
		console.log 'testsearching....'
		loc = {}
		loc.latlng = [42.280, -88.000]
		loc.dist = 0.1
		@searchLocation loc, (doc) ->
			console.log 'searched:', doc

	# test insert
	testInsert: ->
		@client.open (err, db) =>  #funcs created with fat arrow can access `this` where they are defed
			console.log 'init collection inside db open callback'
			#db.system.namespaces.find { name: 'location' }, (err, col) -> console.log 'found:'
			db.dropCollection 'locs', (err, result) =>
				db.collection 'locs', @testAddLocation

	# test 
	test: ->
		console.log 'start testing...'
		cb = (docs) ->
			console.log docs
		@dup()
		#@queryLoc({venue:{$exists:true}}, cb)

exports.create = MongoDup.create

dup = MongoDup.create('localhost', 27017, 'node.am.colorcloud.com', 10000, 'location')
dup.wait([dup.opensrc, dup.opendst], dup.test)
