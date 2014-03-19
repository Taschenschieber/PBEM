flash = require "connect-flash"
express = require "express"

redis = require "redis"
RedisStore = require("connect-redis")(express)
store = new RedisStore

common = require "./common"
notifications = require "./notification-loader"
config = require "./config"




app = express()

database = common.database

auth = common.auth
games = require "./games"

  
error = (err,req,res,next) -> res.send("ERROR: ", err, "STACKTRACE: ", err.stack)
error404 = (req,res,next) -> res.render("404.jade")
  
app.configure () ->
  # static files go first
  app.use express.static __dirname + "/pub"
  
  # middleware settings now
  app.locals.pretty = true # serve readable html files
  
  # middleware that does not require authentication
  app.use express.cookieParser()
  app.use express.bodyParser
    uploadDir: "./uploads"
  app.use express.session 
    secret: config.session.secret
    store: new RedisStore
  app.use flash()
    
  # authentication
  app.use auth.passport.initialize()
  app.use auth.passport.session()
  
  # middleware that requires authentication
  app.use notifications.populate
  app.use app.router
  

# static routes
app.get "/", (req,res) -> res.render("index.jade", assembleData(req,res))
app.get "/login", (req,res) -> res.render("login.jade", assembleData(req,res))


app.get "/signup", (req,res) -> res.render("signup.jade", assembleData(req,res))
app.get "/error", (req,res) -> res.render("error.jade", assembleData(req,res))

# Login handler
auth.setupRoutes app
games.setupRoutes app

# notifications
app.get "/notifications/:id", (req,res) ->
  database.getNotification req.params.id, (err, notification) ->
    if err || not notification?
      return res.send err || "Unknown error"
    action = notification.action || "/" # so it is accessible after deletion

    database.deleteNotification req.params.id, () ->
      return
    res.redirect action

app.listen(8080)
console.log "Server listening at 8080"

assembleData = (req,res) ->
  # assemble a bunch of data that pages can do stuff with
  {req: req, res: res}