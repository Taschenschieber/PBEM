# (c) 2014 Stephan Hillebrand
#
# This file acts as controller for all challenge-related paths. So far, these
# are mostly inconsistent, which is due to change sometime soon.
#
# Routes defined in this file: 

mkdirp = require "mkdirp"
fs = require "fs"
jade = require "jade"
moment = require "moment"
tmp = require "tmp"
ZIP = require "adm-zip" # NOTE: Does not currently work with official version
                        # of adm-zip. See package.json

avatar = require "../avatar"
common = require "../common"
database = require "../database"
email = require "../email"
error = require "../error"

exports.setupRoutes = (app) ->
  app.get "/challenges/send", (req,res) -> res.render("challenges/send.jade", assembleData(req,res))
  app.get "/challenges/list", (req,res) ->
    data = assembleData req,res
    # load challenges from database
    database.Challenge.find
      to: req.user.name
    .populate "scenario"
    .exec (err, challengers) ->
      return error.handle err if err
      data.challengers = challengers || []
      database.Challenge.find
        from: req.user.name
      .populate "scenario"
      .exec (err, challenges) ->
        return error.handle err if err
        data.challenges = challenges || []

        # create fancy dates        
        for ch in data.challengers
          ch.fancyDate = moment(ch.sent).fromNow()
        for ch in data.challenges
          ch.fancyDate = moment(ch.sent).fromNow()
        
        res.render "challenges/list.jade", data
        
  #actual logic
  app.post "/challenges/send/do", (req,res) -> 
    # validate stuff
    failed = no
    if not req.body.opponent?
      failed = yes 
      req.flash "error", "You have to select an opponent."
      # TODO worry about if the opponent actually exists
    if not req.body.timecontrol?
      failed = yes
      req.flash "error", "Time control data missing."
    if not (req.body.scenario? || req.body.dyo)
      failed = yes
      req.flash "Please select a scenario or DYO."
    if not req.user?.name?
      failed = yes
      req.flash "You are apparently not logged in."
    
    # no validation for message - that one is entirely optional.
    return res.redirect "/games/challenge" if failed
    
    
    # apparently, data is valid - now write to DB
    challenge = new database.Challenge
      from: req.user.name
      to: req.body.opponent
      timeControl: req.body.timecontrol
      scenario: req.body.scenario
      dyo: req.body.dyo
      message: req.body.message
      whoIsAttacker: req.body.whoIsAttacker
    
    #console.log challenge
    
    challenge.save (err) -> 
      if err
        req.flash "error", "Could not write to database: " + err?.message
        return res.redirect "/error"

      # saved the challenge - now, issue a notification to the challenged player
      notification = new database.Notification
        username: challenge.to
        text: challenge.from+" challenged you to play "+challenge.scenarioId+" with him."
        action: "/games/my/challenges"
        image: "/user/"+challenge.from+"/avatar/32" #32px big avatar
      notification.save (err) ->
        console.log(err || "Notification created")
        # all done... hopefully. Worry about asynchronous err handling later.
        # no error handling for notifications, it's not really worth it.
      res.redirect("/challenges/list#out")
  
  app.get "/challenges/:id/accept", (req, res) -> # TODO Authenticate!
    database.Challenge.findOne {_id: req.params.id}, (err, challenge) ->
      res.send err if (err || not res)
      # create a game out of the challenge
      game = new database.Game
        playerA: challenge.from
        playerB: challenge.to
        timeControl: challenge.timeControl
        scenario: challenge.scenario
        whoIsAttacker: challenge.whoIsAttacker
      
      game.save (err) ->
        res.send err if err
        # send notification
        new database.Notification
          username: challenge.from
          text: req.user.name + " accepted your challenge."
          action: "/game/"+game._id
          image: "/user/"+challenge.to+"/avatar/32"
        .save (err) ->
          if err
            console.log "ERROR (ignored) while writing notification:"
            console.log err
          
        challenge.remove (err) ->
          if err
            console.log "ERROR (ignored) while deleting challenge:"
            console.log err
        res.redirect "/game/" + game._id
        

  app.get "/challenges/:id/decline", (req,res) -> # TODO Authenticate
    database.Challenge.findOne {_id: req.params.id}, (err, challenge) ->
      res.render err if (err || not res)
      new database.Notification
        username: challenge.from
        text: req.user.name + " declined your challenge."
        action: "#"
        image: "/user/"+challenge.to+"/avatar/32"
      .save (err) ->
        if err
          console.log "ERROR (ignored) while saving notification:"
          console.log err
      challenge.remove (err) ->
        if err
          console.log "ERROR (ignored) while deleting challenge:"
          console.log err
        res.redirect "/games/my/challenges"
        
  app.get "/challenges/:id/takeback", (req,res) -> # TODO Authenticate
    database.Challenge.findOne {_id: req.params.id}, (err, challenge) ->
      res.render err if (err || not res)
      new database.Notification
        username: challenge.to
        text: req.user.name + " took back his challenge to you."
        action: "#"
        image: "/user/"+challenge.from+"/avatar/32"
      .save (err) ->
        if err
          console.log "ERROR (ignored) while saving notification:"
          console.log err
      challenge.remove (err) ->
        return res.render err if err
        res.redirect "/games/my/challenges"


assembleData = (req,res) ->
  # assemble a bunch of data that pages can do stuff with
  {req: req, res: res}
  