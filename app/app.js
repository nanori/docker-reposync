var app_port=8080

var RETHINKDB_HOST = process.env.RETHINKDB_HOST
var RETHINKDB_PORT = process.env.RETHINKDB_PORT

var bodyParser = require('body-parser')

const exec = require('child_process').exec;
const spawn = require('child_process').spawn;
const fs = require('fs');
const express = require('express');

var app = express();
app.use( bodyParser.json() ); 
app.use(require('morgan')('combined'))
var router = express.Router();

var connection = null;
r = require('rethinkdb')
r.connect({ host: RETHINKDB_HOST, port: RETHINKDB_PORT }, function(err, conn) {
        if(err) throw err;
        connection = conn;
        r.db('test').tableCreate('reposync',  {primaryKey: 'repoid'}).run(connection, function(err, result) {
            console.log(JSON.stringify(result, null, 2));
        })
});

app.get('/health', function (req, res) {
   res.send("ok")
});

app.route('/repository/:id')
   .get(function (req, res) {
         r.table('reposync').get(req.params['id']).run(connection, function(err, result) {
                if (err) throw err;
                res.send(JSON.stringify(result, null, 2));
        });
   })
   .delete(function (req, res) {
         r.table('reposync').get(req.params['id']).delete().run(connection, function(err, result) {
                if (err) throw err;
                res.send(JSON.stringify(result, null, 2));
        });
   });

app.get('/repository/sync/:id', function (req, res) {
   var repo = null
   r.table('reposync').get(req.params['id']).run(connection, function(err, result) {
      if (err) throw err;
      repo = JSON.stringify(result, null, 2);
      out = fs.openSync('/tmp/' + result.repoid + '.log', 'a');
      err = fs.openSync('/tmp/' + result.repoid + '.log', 'a');
      process_args = ["-n", result.repoid,
                      "-b", result.breed,
                      "-r", result.repomirror,
                      "-d", result.download_path];
      if (result.proxy && result.proxy != "" ){
        process_args.push("-p")
        process_args.push(result.proxy)
      }
      reposyn_process = spawn("/app/reposync.sh", process_args, {
         detached: true,
         stdio: [ 'ignore', out, err ]
      });

      r.table('reposync').get(req.params['id']).update({status: "Sync in progress"}).run(connection, function(err, result) {
      });
      reposyn_process.on('close' , (code) => {
         if (code == 0 ) {
            var now = new Date();
            var jsonDate = now.toJSON();
            r.table('reposync').get(req.params['id']).update({status: "Synchronized", lastupdate: jsonDate}).run(connection, function(err, result) {
            });
         } else {
            r.table('reposync').get(req.params['id']).update({status: `Sync error (${code})`}).run(connection, function(err, result) {
            });
         }
      });
      res.send("ok");
   });
});


app.route('/repository')
        .get(function (req, res) {
                repolist = r.table('reposync').run(connection, function(err, cursor) {
                        cursor.toArray(function(err, result) {
                                if (err) throw err;
                                repolist = JSON.stringify(result, null, 2);
                                res.send(repolist);
                        });
                });
        })
        .post(function (req, res) {
                var repo = req.body;
                repo.lastupdate = 'Never';
                repo.status = 'Added';
                r.table('reposync').insert(req.body).run(connection, function(err, result) {
                        if (err) throw err;
                        res.statusCode = 201;
                        res.send(JSON.stringify(result, null, 2));
                });
        });
        
app.listen(app_port, function () {
        console.log('App listening on port ' + app_port + '!');
});


