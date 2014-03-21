common = require "./common"
mkdirp = require "mkdirp"
fs = require "fs"
error = require "./error"

gravatar = require "gravatar"
database = common.database

exports.setupRoutes = (app) ->
  #static pages
  app.get "/games", (req,res) -> res.render("listActiveGames.jade", assembleData(req,res))
  app.get "/games/challenge", (req,res) -> res.render("issueChallenge.jade", assembleData(req,res))
  app.get "/games/challenge/success", (req,res) -> res.render("challengeIssued.jade", assembleData(req,res))
  app.get "/games/my/challenges", (req,res) ->
    data = assembleData req,res
    # load challenges from database
    database.findChallengesFor req.user.name, (err, challengers) ->
      return res.redirect "/error" if err
      data.challengers = challengers || []
      database.findChallengesFrom req.user.name, (err, challenges) ->
        return res.redirect "/error" if err
        data.challenges = challenges || []
        res.render "challenges.jade", data
  
  app.get "/games/my/active", (req,res) ->
    data = assembleData req, res
    database.Game.find {$or: [{playerA: req.user.name}, {playerB: req.user.name}]}, (err, games) ->
      res.send err if (err)
      
      data.games = games
      res.render "mygames.jade", data
  
  
  
  app.get "/game/:id", (req,res) ->
    data = assembleData req,res
    database.Game.findOne {_id: req.params.id}, (err, game) ->
      res.send err if (err || !game)
      # find out whose turn it is
      if game.whoseTurn == "A"
        data.activePlayer = game.playerA
      else if game.whoseTurn == "B"
        data.activePlayer = game.playerB
      else
        data.activePlayer = ""
      
      data.game = game
      # get player profiles
      database.User.find
        $or: [{name: game.playerB}, {name: game.playerA}]
      , (err, users) ->
        for user in users
          if user.name == game.playerA
            data.avatarA = gravatar.url user.email, {d: "identicon"}
          else
            data.avatarB = gravatar.url user.email, {d: "identicon"}
        # get scenario information, if available
        database.Scenario.findOne
          number: game.scenarioId
        , (err, sc) ->
          return error.handle err if err
          data.scenario = sc || {}
          
          data.avatarA = 
          res.render "game.jade", data
      
  app.get "/game/:id/upload", (req,res) ->
    res.render "uploadLogfile.jade", assembleData(req, res)
  
  app.post "/game/:id/upload/do", (req,res) ->
    # create database document in order to have an ID
    log = new database.Log 
      sentBy: req.user.name
      empty: false
    
    
    database.Game.findOne {_id: req.params.id}
      .exec (err, game) ->
        if err || not game
          return res.send err
         
        # ensure the current user is allowed to upload to this match
        unless(req?.user?.name? and (req.user.name == game.playerA || req.user.name == game.playerB))
          return error.handle(new Error("You are not allowed to post logs to this game."))
          
        game.logs.push log
        previousPlayer = game.whoseTurn || "" # needed to revert after error
        if(req.user.name == game.playerA)
          game.whoseTurn = "B"
        else
          game.whoseTurn = "A"
        
        game.save (err) ->
          return res.send err if err
          console.log log._id
          path = __dirname + "/pub/logfiles/"+game._id+"/"+log._id+".vlog"
          console.log "Saving to: ", path
          console.log "Tempfile: ", req.files.logfile.path
          fs.readFile req.files.logfile.path, (err, data) ->
            return res.send err if err
            console.log "Making dir: ", __dirname + "/pub/logfiles/"+game._id
            mkdirp __dirname + "/pub/logfiles/"+game._id, (err) ->
              if err
                # oh bollocks! Delete log from DB to ensure consistency
                # well... eventual consistency
                if game.logs.indexOf log >= 0
                  game.logs.splice(game.logs.indexOf(log), 1)
                  
                game.whoseTurn = previousPlayer
                game.save (err) ->
                  #do nothing
                  console.log " "
                return res.send err
              fs.writeFile path, data, (err2) ->
                if err2
                  # oh bollocks! Delete log from DB to ensure consistency
                  # well... eventual consistency
                  if game.logs.indexOf log >= 0
                    game.logs.splice(game.logs.indexOf(log), 1)
                    
                  game.whoseTurn = previousPlayer
                  game.save (err) ->
                    #do nothing
                    console.log " "
                  return res.send err2
                else
                  res.redirect "/game/" + game._id
                  # and done. TODO Add a notification here.
                  # TODO Add e-mail sending here
      
  app.get "/games/world/active/:page", (req,res) ->
    data = assembleData req, res
    database.Game.find {active: true}
         #.sort "-started"
         #.skip (req.params.page-1)*10
         #.limit 10
         .exec (err, games) ->
            return res.send err if err
            data.games = games
            console.log games
            res.render "allGames.jade", data
      
      
  #actual logic
  app.post "/do/games/challenge/issue", (req,res) -> 
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
    challenge = new database.Challenge {
      from: req.user.name
      to: req.body.opponent
      timeControl: req.body.timecontrol
      scenarioId: req.body.scenario
      dyo: req.body.dyo
      message: req.body.message
    }
    
    #console.log challenge
    
    challenge.save (err) -> 
      if err
        req.flash "error", "Could not write to database: " + err?.message
        return res.redirect "/error"

      # saved the challenge - now, issue a notification to the challenged player
      database.createNotification challenge.to, "You have been challenged to a match!", "/games/my/challenges", (err) ->
        console.log(err || "Notification created")
        # all done... hopefully. Worry about asynchronous err handling later.
        # no error handling for notifications, it's not really worth it.
      res.redirect("/games/challenge/success")
  
  app.get "/challenges/:id/accept", (req, res) -> # TODO Authenticate!
    database.Challenge.findOne {_id: req.params.id}, (err, challenge) ->
      res.render err if (err || not res)
      # create a game out of the challenge
      game = new database.Game
        playerA: challenge.from
        playerB: challenge.to
        timeControl: challenge.timeControl
        scenarioId: challenge.scenarioId
      
      game.save (err) ->
        res.send err if err
        # send notification
        database.createNotification challenge.to, req.user.name + " accepted your challenge!", "/game/"+game._id, (err) ->
          console.log err if err
        res.redirect "/game/" + game._id
       

  app.get "/challenges/:id/decline", (req,res) -> # TODO Authenticate
    database.Challenge.findOne {_id: req.params.id}, (err, challenge) ->
      res.render err if (err || not res)
      database.createNotification challenge.from, req.user.name + " declined your challenge. :(", "#", (err) ->
        console.log err if err
      challenge.remove (err) ->
        return res.render err if err
        res.redirect "/games/my/challenges"
        
  app.get "/challenges/:id/takeback", (req,res) -> # TODO Authenticate
    database.Challenge.findOne {_id: req.params.id}, (err, challenge) ->
      res.render err if (err || not res)
      database.createNotification challenge.to, req.user.name + " took back his challenge to you.", "#", (err) ->
        console.log err if err
      challenge.remove (err) ->
        return res.render err if err
        res.redirect "/games/my/challenges"

  
assembleData = (req,res) ->
  # assemble a bunch of data that pages can do stuff with
  {req: req, res: res}