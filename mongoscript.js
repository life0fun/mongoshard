//
// mongo mongoscript.js
//
// mongo 192.168.13.7:9999/foo
//
//------------------------------------------------
// how to use mongo script
//------------------------------------------------
//db = connect('localhost:27017/location')
//admin = db.getSisterDB('admin')
//printjson(db.locs.findOne({venue:{$exists:true}}))
//db.locs.find({latlng:{$near:[42.283,-87.953]}, venue:{$exists:true}, 
//		etm:{$gt:new Date(2011,7,28,8,0,0), $lt:new Date(2011, 7, 28, 11, 00, 00)}}).forEach(printjson)
//db.locs.find({latlng:{$near:[42.283,-87.953]}, venue:{$exists:true}, 
//		etm:{$gt:'1314536400000', $lt:'1314547200000'}}).forEach(printjson)
//printjson(db.getLastErrorObj())

//------------------------------------------------
// mongo ISODate ISODate("2011-11-14T21:43:35.370Z")
//------------------------------------------------
// 1. db.locs.insert({latlng:[1,2], stm:new Date()})
//    db.locs.find()
//    { "_id" : ObjectId("x"), "latlng" : [ 1, 2 ], "stm" : ISODate("2011-11-14T21:43:35.370Z") }
// 2. In both javascript and mongo shell
//      db.locs.find({stm:{$gte:new Date(2011, 10, 14, 15, 43, 35, 370)}}) # 14 = timezone(u.s center)
//    In Javascript only, use static string avoid timezone issue !!!
//      db.locs.find({stm:{$gte:new Date("2011-11-14 21:43:35.370Z")}}) # ending Z is must have!
// 3. Date is epoch based, so you can not search any date before 1970
// 4. To query time range, use $where, and expression is &&. both JS and shell
//	    db.locs.find({$where:'this.stm.getHours() >= 16 && this.stm.getHours() <= 21'})
//	    db.locs.find(latlng:{$near:[1,2], $maxDistance:1}, {$where:'this.stm.getHours() >= 15 && this.stm.getHours() <= 21'})

//------------------------------------------------
// how to shard.(mongod, config server, and mongos points to config server dns name, not ip addr, for easy migration)
// 1. config replSet, start mongod server with replSet name and port.
//    mongod --rest --replSet myset --port 20000 --dbpath ~/data/myset
//    mongo dirt.am.colorcloud.com:20000
//    config = {_id:'myset', members:[{_id:0, host:'dirt.am.colorcloud.com:20000'}, {_id:1, host:'ecomm.am.colorcloud.com:20000'}, {_id:2, host:'node.am.colorcloud.com:20000', arbiterOnly:true}]}
//    rs.initiate(config)
//    rs.status()
// 2. run mongod shard server. mongod --port 10002 --dbpath /data/shard/
// 3. run mongod on config server. mongod --port 10001 --configsvr --dbpath /data/configsvr 
// 4. run mongos, point to configdb. mongos --port 10000 --configdb localhost:10001
// 5. connect to mongos from client and issue db  mongo localhost:10000/admin
// 6. add shard db.runCommand({addshard:'localhost:10002', name:'dirt'})
//    if shards consist of replicaSet, shard can be added by specifying replicaSetName/serverHostName:port
//      db.runCommand({addshard: "replSet1/colorcloud:10000"});
//    Note that all servers inside a repl set must be added when addshard.
// 6. you can connect to shard with mongo --port 10002
// 7. list all shards, printjson(db.runCommand({listshards:1})) db.printShardingStatus()
// 8. enable shard.  db.runCommand({enableSharding: 'location'})
// 8. shard locs collection with key=latlng, define a key, partition your data(collection) based on key. 
//      db.runCommand({shardcollection:'location.locs', key:{latlng:1}})
// 9. use location db.locs.ensureIndex({latlng:'2d'}, {unique: true})
//
// 10. insert some entries. db.locs.insert({latlng:[12.34, 56.78], name:'colorcloud'})
// 11. move chunk. db.runCommand({moveChunk:"location1.locs",find:{name:"colorcloud2"},to:"shard0001"}) 
// 8. split a chunk: db.runCommand({split:<collection>, middle:{email: prefix}});
//   
//------------------------------------------------
// http://blog.serverdensity.com/automating-partitioning-sharding-and-failover-with-mongodb/
// http://blog.serverdensity.com/notes-from-a-production-mongodb-deployment/
// http://www.taobaodba.com/html/525_525.html
//------------------------------------------------
// shard on my cluster: each shard contains 1+ server, <- replica set, shard is a replica set.
// 1. config replSet
//      mongod --rest --shardsvr --replSet myset --dbpath .   # --rest(enable admin), --shardsvr(enable sharding)
//      mongod --rest --replSet myset --port 20000 --dbpath ~/data/myset
//      mongo dirt.am.colorcloud.com:20000
//      config = {_id:'myset', members:[
//              {_id:0, host:'dirt.am.colorcloud.com:20000', priority : 2},  <- which order they become primary during failover.
//              {_id:1, host:'ecomm.am.colorcloud.com:20000'}, 
//              {_id:2, host:'node.am.colorcloud.com:20000', arbiterOnly:true}]}
//    rs.initiate(config)   <-- init replicatSet setname/server, this can be done on either sharding server.
//    rs.status()
// 2. mongod --port 10002 --dbpath $HOME/data/shard
// 3. mongod --port 10001 --configsvr --dbpath $HOME/data/config
// 4. mongos --port 10000 --configdb node.am.colorcloud.com:10001 --chunkSize 1
// 5. mongo node.am.colorcloud.com:10000/admin
// 6. db.runCommand({addshard:'ecomm.am.colorcloud.com:10002', name:'ecomm'})
//    db.runCommand({addshard:'myset/ecomm.am.colorcloud.com:20000', name:'ecomm'})  # add a shard server from a myset
//    db.runCommand({addshard:'dirt.am.colorcloud.com:10002', name:'dirt'})
// 7. db.printShardingStatus(); printjson(db.runCommand({listshards:1})) 
// 8. shard key can not be array!!
//    db.runCommand({enableSharding: 'location'})
//    db.runCommand({shardcollection:'location.locs', key:{latlng:1}})
// 9. use location; db.locs.ensureIndex({latlng:'2d'}, {unique: true})
// 10. db.locs.insert({latlng:10, name:'colorcloud'})
//	   db.locs.insert({latlng:11, name:'colorcloud1'})
//	   db.locs.insert({latlng:12, name:'colorcloud2'})
// 11. chunk ops(Move, split) must be based on shard key
//		db.runCommand({moveChunk:"location.locs",find:{latlng:10},to:"ecomm"}) 
//		db.runCommand({split:'location.locs', middle:{latlng: 11}})
//		db.runCommand({moveChunk:"location.locs",find:{latlng:10},to:"dirt"}) 
//   
//------------------------------------------------


//------------------------------------------------
// drawback of mongo, can not use db.locs.find({latlng:{'$near':[42.28,-88]})
// db.runCommand({geoNear:'locs', near:[42.28, -88.0]
//------------------------------------------------

//------------------------------------------------
// connect to mongos routing server, and connect to admin
//------------------------------------------------
admin = connect('node.am.colorcloud.com:10000/admin')
config = admin.getSisterDB('config'); 
printjson(admin.runCommand({listshards:1}))
admin.printShardingStatus()
printjson(admin.runCommand({addshard:'ecomm.am.colorcloud.com:10002', name:'ecomm', allowLocal:true}))
printjson(admin.runCommand({addshard:'dirt.am.colorcloud.com:10002', name:'dirt', allowLocal:true}))
admin.printShardingStatus()
admin.runCommand({enableSharding: 'location'})
admin.runCommand({shardcollection:'location.locs', key:{imei:1}})
locdb = connect('node.am.colorcloud.com:10000/location')
locdb.locs.ensureIndex({imei:1})
locdb.locs.find()
printjson(locdb.locs.getIndexes())

//------------------------------------------------
// how to profile query
//------------------------------------------------
// 1. Always run explain on queries
//    db.collection.find().explain()
// 2. BSON ID contains the creation of time the obj being created. 
//      ObjectId("505bd76785ebb509fc183733").getTimestamp();
// 3. Always profile
//    db.setProfilingLevel(1, 100)  // any query longer than 100ms
//    db.setProfilingLevel(2)       // profile all queries
//
//   the profile result saved in capped collection in system.profile
//    db.system.profile.find()
//    show profile
//
// 4. useful commands
//   db.currentOp()
//   db.killOp(opid)
//   db.serverStatus()
//   db.stats()
//   db.collection.stats()
