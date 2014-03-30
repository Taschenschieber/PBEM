# (c) 2014 Stephan Hillebrand
# 
# This file contains all route handlers for AJAX requests.
#
# Routes handled by this file:
# /ajax/scenario/:text - perform a scenario search

database = require "./database"
Scenario = database.Scenario

exports.setupRoutes = (app) ->
  app.get "/ajax/scenario/:text", (req,res) ->
    text = req.params.text
    console.log "Find scenarios: ", text
    Scenario.find
      $or: [title: 
        $regex: text
        $options: "i"    # i = case insensitive
      ,
        number: text
      ]
    .limit 3
    .exec (err, scenarios) ->
      console.log err if err
      console.log scenarios
      if not scenarios
        res.status(404).send "No such data"
      else res.send scenarios
  
  app.get "/ajax/user/:text", (req,res) ->
    text = req.params.text
    database.User.find 
      name:
        $regex: text
        $options: "i"
    .limit 3
    .select "name _id id attacker defender"
    .exec (err, users) ->
      console.log err if err
      if err || not users
        res.status(404).send "No such user"
      else
        res.send users
  
  app.get "/ajax/profile/:field/:value", (req, res) ->      
    console.log "FOO"

    field = decodeURI req.params.field
    value = decodeURI req.params.value
    
    #validate
    unless value.match /[a-zA-Z0-9]+/
      return res.send(403, req.user?.profile?[field] || " ")
      
    if field in ["gamesquad", "thegeek", "facebook", "gplus", "twitter", "xmpp"]
      oldval = req.user?.profile?[field] || ""
      req.user.profile[field] = value
    
    else if field in ["onNewLog", "onNewLogWithLog", "onKibitz", "onChallenge"]
      oldval = req.user?.notifications?[field] || false
      if value == "on"
        value = true
      else
        value = false
      req.user.notifications[field] = value
     
    else # field is invalid
      return res.send 403, oldval
    
    req.user.save (err) ->
      if err
        console.log err
        return res.send 500, oldval  
      return res.send 200, value
    