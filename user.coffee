# (c) 2014 Stephan Hillebrand.
#
# This file is responsible for handling all functions that are related to user
# profiles.
#
# Routes exported by this file:
# /user/:name

database = require "./database"
error = require "./error"
gravatar = require "gravatar"

exports.setupRoutes = (app) ->
  app.get "/user/:name", (req,res) ->
    data = {req:req,res:res}
    
    database.User.findOne
      name: req.params.name
    , (err, user) -> 
      return error.handle(req,res,err) if err
      return error.handle(req,res,"No such user!") unless user
      data.user = user
      data.avatar = gravatar.url user.email, {d: "identicon"}
      res.render "user/profile_public.jade", data
      