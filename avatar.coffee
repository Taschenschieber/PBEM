# (c) 2014 Stephan Hillebrand
#
# Offers route for displaying avatars
#
# Routes handled by this file:
# /user/:name/avatar
# /user/:name/avatar/:size

gravatar = require "gravatar"

database = require "./database"

exports.setupRoutes = (app) ->
  app.get "/user/:name/avatar", (req,res) ->
    res.redirect "/user/"+req.params.name+"/avatar/80"
    
  app.get "/user/:name/avatar/:size", (req, res) ->
    # retrieve user from database
    database.User.findOne
      name: req.params.name
    .select "email"
    .exec (err, user) ->
      if err
        console.log "ERROR 500 while retrieving avatar: "
        console.log err
        return res.status(500).send("500 Internal Server Error")
      if !user
        console.log "ERROR 404 for avatar: user "+req.params.name+" not found"
        return res.status(404).send("404 File not found")
      url = gravatar.url user.email,
        s: req.params.size
        d: "identicon"
      res.redirect url