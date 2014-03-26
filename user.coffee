# (c) 2014 Stephan Hillebrand.
#
# This file is responsible for handling all functions that are related to user
# profiles.
#
# Routes exported by this file:
# /users - overview page
# /users/messenger - Messenger. Duh.
# /users/messenger/do/send - send a message. POST.
# /user/:name - profile for :name
# /user/message/:id - read message


database = require "./database"
error = require "./error"
gravatar = require "gravatar"
moment = require "moment"
flash = require "connect-flash"

exports.setupRoutes = (app) ->
  app.get "/users", (req, res) ->
    data = {req:req,res:res}
    res.render "user/overview.jade", data
    
  app.get "/users/messenger", (req,res) ->
    data = {req:req,res:res}
    res.render "user/messenger.jade", data

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
      
  app.get "/user/message/:msgid", (req, res) ->
    data = {req:req,res:res}
    # try and find message
    for msg in req.user.inbox.concat(req.user.outbox)
      console.log msg.id
      console.log req.params.msgid
      if msg.id is req.params.msgid
        console.log "Found match"
        data.msg = msg
        data.fancyDate = moment(data.sent).fromNow()
        return res.render "user/message.jade", data
    req.flash "error", "The message you tried to open does not exist."
    res.redirect "/users/messenger"
      
  app.post "/users/messenger/do/send", (req, res) ->
    message = new database.Message # TODO Validate!
      to: req.body.to
      from: req.user.name
      subject: req.body.subject
      message: req.body.message
      
    recipient = database.User.findOne
      name: req.body.to
    .exec (err, user) ->
      return error.handle err if err
      return error.handle new Error("No such user") unless user
      
      user.inbox.push message
      user.save (err) ->
        return error.handle err if err
        # success, apparently
        res.redirect "/users/messenger"
        
        # save to outbox - not critical if it fails, so done after success msg
        req.user.outbox.push message
        req.user.save (err) ->
          console.log err if err
        