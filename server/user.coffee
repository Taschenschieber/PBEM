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
# /user/me - profile for logged in user (editable)
# /user/message/:id - read message
# /user/message/:id/delete - delete message from inbox/outbox
# /users/best - High Score List

flash = require "connect-flash"
moment = require "moment"
passport = require "passport"

auth = require "./auth"
database = require "./database"
error = require "./error"
avatar = require "./avatar"

exports.setupRoutes = (app) ->
  app.get "/users", auth.loggedIn, (req, res) ->
    data = {req:req,res:res}
    res.render "user/overview.jade", data
    
  app.get "/users/messenger", auth.loggedIn, (req,res) ->
    data = {req:req,res:res}
    # fancy dates
    for msg in req.user.inbox
      msg.fancyDate = moment(msg.sent).fromNow()
    for msg in req.user.outbox
      msg.fancyDate = moment(msg.sent).fromNow()

    res.render "user/messenger.jade", data
    
  app.get "/user/me", auth.loggedIn, (req,res) ->
    data = {req:req, res: res, user: req.user}
    res.render "user/me.jade", data

  app.get "/user/:name", auth.loggedIn, (req,res) ->
    data = {req:req,res:res}
    
    database.User.findOne
      name: req.params.name
    , (err, user) -> 
      return error.handle(err, req, res) if err
      return error.handle("No such user!", req, res) unless user
      data.user = user
      data.avatar = "/user/"+user.name+"/avatar"
      res.render "user/profile_public.jade", data
      
  app.get "/user/message/:msgid", auth.loggedIn, (req, res) ->
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
    
    
  app.get "/user/message/:msgid/delete", auth.loggedIn, (req,res) ->
    saveChanges = (user) ->
      user.save (err) ->
        return error.handle err if err
        req.flash "info", "Message deleted."
        res.redirect "/users/messenger"
  
    for msg in req.user.inbox
      if msg.id is req.params.msgid
        index = req.user.inbox.indexOf msg
        if index >= 0
          req.user.inbox.splice(index, 1)
          return saveChanges(req.user)
          
    for msg in req.user.outbox
      if msg.id is req.params.msgid
        index = req.user.outbox.indexOf msg
        if index >= 0
          req.user.outbox.splice(index, 1)
          return saveChanges(req.user)
    
    req.flash "error", "This message does not exist."
    res.redirect "/users/messenger"
    
      
  app.post "/users/messenger/do/send", auth.loggedIn, (req, res) ->
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
          
  app.get "/users/best", auth.loggedIn, (req,res) ->
    data = {req: req, res: res}
    database.User
    .find {}
    .sort "-rating.points"
    .limit 10
    .select "name rating password" # NOTE not selecting password causes error
    .exec (err, bestRatings) ->
      console.log bestRatings
      return error.handle err if err
      data.bestRatings = bestRatings
      
      res.render "user/best.jade", data
        
  app.get "/users/find", auth.loggedIn, (req, res) ->
    data = {req:req, res:res}
    database.User
      .find {}
      .sort "+name"
      .select "name activated banned rating"
      .exec (err, users) ->
        return error.handle err if err
        data.users = users
        
        # NOTE: Some performance improvement is possible here by generating
        # gravatar URLS here directly and passing them to the view. So far,
        # the view will use the /user/<name>/avatar/32 route, which leads to
        # a new DB query for every single user.
        # 
        # For the sake of possible changes to the avatar system in the future,
        # we'll use the less performant alternative for the time being.
        res.render "user/find.jade", data
        
        