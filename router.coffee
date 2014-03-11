flash = require "connect-flash"
express = require "express"
common = require "./common"
notifications = require "./notification-loader"
app = express()

database = common.database

auth = common.auth
games = require "./games"

  
error = (err,req,res,next) -> res.send("ERROR: ", err, "STACKTRACE: ", err.stack)
error404 = (req,res,next) -> res.render("404.jade")
  
app.configure () ->
  app.locals.pretty = true # serve readable html files
  app.use express.cookieParser()
  app.use express.bodyParser()
  app.use express.session 
    secret: "fthagn"
  app.use auth.passport.initialize()
  app.use auth.passport.session()
  app.use notifications.populate # needs to be called after Passport
  app.use flash()
  app.use app.router
  app.use express.static __dirname + "/pub"
  #app.use error
  #app.use error404
  


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
    return res.send err? || "Unknown error" if err || not notification?
    database.deleteNotification req.params.id, () ->
      return
    res.redirect notification.action?  "/"

app.listen(80)
app.listen(8080)
console.log "Server listening at 80+8080"

assembleData = (req,res) ->
  # assemble a bunch of data that pages can do stuff with
  {req: req, res: res}