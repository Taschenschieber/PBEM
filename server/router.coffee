flash = require "connect-flash"
express = require "express"
fs = require "fs"
redis = require "redis"
RedisStore = require("connect-redis")(express)
store = new RedisStore

common = require "./common"
notifications = require "./notification-loader"
config = require "./config"
user = require "./user"
ajax = require "./ajax"
error = require "./error"
games = require "./games"
database = require "./database"
auth = require "./auth"
avatar = require "./avatar"

app = express()

error = (err,req,res,next) -> res.send("ERROR: ", err, "STACKTRACE: ", err.stack)
error404 = (req,res,next) -> res.status(404).render "404.jade", {req:req,res:res}
  
app.configure () ->
  # static files go first
  app.use express.static "./pub"
  
  # middleware settings
  app.locals.pretty = true # serve readable html files
  
  # middleware that does not require authentication
  app.use express.cookieParser()
  app.use express.bodyParser
    uploadDir: "./uploads"
  app.use express.session 
    secret: config.session.secret
    store: new RedisStore
    
  # authentication
  app.use auth.passport.initialize()
  app.use auth.passport.session()
  
  # middleware that requires authentication
  app.use notifications.populate
  app.use flash()
  app.use app.router
  
  app.use error404
  
  # NOTE: For some weird reason, notifications.populate fails when called 
  # immediately before app.router.
  # For the time being, flash() should be called between the two.
  

# static routes
app.get "/", (req,res) -> res.render("index.jade", assembleData(req,res))
app.get "/login", (req,res) -> res.render("login.jade", assembleData(req,res))


app.get "/signup", (req,res) -> res.render("signup.jade", assembleData(req,res))
app.get "/error", (req,res) -> res.render("error.jade", assembleData(req,res))

app.get "/help/:topic", (req,res) ->
  topic = req.params.topic
  if fs.existsSync "./views/help/"+topic+".jade"
    res.render "help/"+topic+".jade", {req:req,res:res}
  # no err handling necessary, middleware will catch it
  
app.get "/help", (req,res) ->
  res.redirect "/help/index"

# Login handler
auth.setupRoutes app
games.setupRoutes app
user.setupRoutes app
notifications.setupRoutes app
ajax.setupRoutes app
avatar.setupRoutes app

app.listen(8080)
console.log "Server listening at 8080"

assembleData = (req,res) ->
  # assemble a bunch of data that pages can do stuff with
  {req: req, res: res}