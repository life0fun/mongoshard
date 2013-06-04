//
// 1. start mongodb /Volume/Build/mongodb/mongod --dbpath /Volumes/Build/mongodb/data/db/
// 2. node mongotest.js
//

var sys          = require('sys'),
    http         = require('http'),
    query        = require('querystring'),
    EventEmitter = require('events').EventEmitter,
    Buffer       = require('buffer').Buffer,
    Server       = require('node-mongodb-native/lib/mongodb').Server,
    Db           = require('node-mongodb-native/lib/mongodb').Db,
    Connection   = require('node-mongodb-native/lib/mongodb').Connection,
    BSON         = require('node-mongodb-native/lib/mongodb').BSONNative;

//http://ipinfodb.com/ip_locator.php?ip=128.192.53.46
var MongoDBClient = module.exports.MongoDBClient = function(){
    EventEmitter.call(this);

    this.host = process.env['MONGO_NODE_DRIVER_HOST'] != null ? process.env['MONGO_NODE_DRIVER_HOST'] : 'localhost';
    this.port = process.env['MONGO_NODE_DRIVER_PORT'] != null ? process.env['MONGO_NODE_DRIVER_PORT'] : Connection.DEFAULT_PORT;

    this.db = new Db('node-mongo-examples', new Server(this.host, this.port, {}), {native_parser:true});
    return this;
};
// Prototype Inheritance
sys.inherits(MongoDBClient, EventEmitter);

// the open API
MongoDBClient.prototype.test = function(){
    this.db.open(function(err, db) {
        db.dropDatabase(function(err, result) {
            // create test collection
            db.collection('test', function(err, collection) {
            // Erase all records from the collection, if any
            collection.remove(function(err, collection) {
                // Insert 3 records into test collection
                for(var i = 0; i < 3; i++) {
                     collection.insert({'a':i});
                }
        
                collection.count(function(err, count) {
                     sys.puts("There are " + count + " records in the test collection.:");
                     // find return a cursor, the same as query(cursor)
                     collection.find(function(err, cursor) {
                         // iterate over the cursor
                         cursor.each(function(err, item) {
                              if(item != null) {
                                  sys.puts(sys.inspect(item));
                                  sys.puts("created at " + new Date(item._id.generationTime) + "\n")
                              }
                              // Null signifies end of iterator
                              if(item == null) {                
                                  // Destory the collection
                                  collection.drop(function(err, collection) {
                                    db.close();
                                  });
                              }
                        });
                    });          
                });
            });      
        });
    });
  });
}

// uncomment out for unit test
var dbclient = new MongoDBClient();
dbclient.test()
