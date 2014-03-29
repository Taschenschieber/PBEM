# (c) 2014 Stephan Hillebrand
#
# This file is responsible for handling everything related to creating, playing
# and watching games.
#
# TODO Make nice route list

mkdirp = require "mkdirp"
fs = require "fs"
jade = require "jade"
moment = require "moment"
tmp = require "tmp"
ZIP = require "adm-zip" # NOTE: Does not currently work with official version
                        # of adm-zip. See package.json

avatar = require "./avatar"
common = require "./common"
database = require "./database"
elo = require "./elo"
email = require "./email"
error = require "./error"



exports.setupRoutes = (app) ->
  #static pages
  app.get "/games", (req,res) -> res.render("listActiveGames.jade", assembleData(req,res))
  app.get "/games/challenge", (req,res) -> res.render("issueChallenge.jade", assembleData(req,res))
  app.get "/games/challenge/success", (req,res) -> res.render("challengeIssued.jade", assembleData(req,res))
  app.get "/games/my/challenges", (req,res) ->
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
        
        res.render "challenges.jade", data
  
  app.get "/games/my/active", (req,res) ->
    data = assembleData req, res
    database.Game.find 
      $and: [$or: [{playerA: req.user.name}, {playerB: req.user.name}], result: "ongoing"]
    .populate "scenario"
    .exec (err, games) ->
      console.log games
      res.send err if (err)
      
      data.games = games
      res.render "mygames.jade", data
  
  
  
  app.get "/game/:id", (req,res) ->
    data = assembleData req,res
    database.Game.findOne 
      _id: req.params.id
    .populate "scenario"
    .exec (err, game) ->
      res.send err if (err || !game)
      console.log game.scenario
      # find out whose turn it is
      if game.whoseTurn == "A"
        data.activePlayer = game.playerA
      else if game.whoseTurn == "B"
        data.activePlayer = game.playerB
      else
        data.activePlayer = ""
      
      data.bulkName = getBulkFileName game
      
      # do some date formatting
      for log in game.logs
        log.prettyDate = moment(log.date).fromNow()
        log.prettyFirstPhase = getPhaseByID log.firstPhase, yes
        log.prettyLastPhase = getPhaseByID log.lastPhase, yes
        
      data.game = game

      # get player profiles
      database.User.find
        $or: [{name: game.playerB}, {name: game.playerA}]
      , (err, users) ->
        for user in users
          if user.name == game.playerA
            data.avatarA = "/user/"+user.name+"/avatar"
            data.avatarAsmall = data.avatarA+"/32"
          if user.name == game.playerB
            data.avatarB = "/user/"+user.name+"/avatar"
            data.avatarBsmall = data.avatarB + "/32"
          
          res.render "game.jade", data
          
  app.get "/game/:id/resign", (req, res) ->
    game = database.Game.findOne
      _id: req.params.id
    .exec (err, game) ->
      return error.handle err if err
      if not game
        req.flash "error", "The game you want to resign from does not exist."
        return res.redirect "/games"
        
      result = ""
      result = "winB" if req.user.name == game.playerA
      result = "winA" if req.user.name == game.playerB
      
      if result is ""
        req.flash "error", "You have no access to this game."
        return res.redirect "/games"
        
      game.result = result
        
      game.save (err) ->
        if err
          req.flash "error", "There was an error while writing to the database."
        else
          req.flash "info", "You resigned from this game."
        
        loadPlayersAndUpdateRatings game.playerA, game.playerB, (result == "winA"), (err) ->
          if err
            console.log "ERROR while calculating new ratings"
            console.log err
        
        res.redirect "/game/"+req.params.id
      
      
  app.get "/game/:id/upload", (req,res) ->
    res.render "uploadLogfile.jade", assembleData(req, res)
  
  app.post "/game/:id/upload/do", (req,res) ->
    # create database document in order to have an ID
    log = new database.Log 
      sentBy: req.user.name
      empty: false
      message: req.body.message
      firstPhase: req.body.firstPhase
      lastPhase: req.body.lastPhase
    
    
    database.Game.findOne {_id: req.params.id}
      .populate "scenario" # needed for e-mail handler
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
          path = __dirname + "/pub/logfiles/#{game._id}/#{log._id}.vlog"
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
                  email.sendLogMail game, (err, response) ->
                    console.log err if err
                    console.log "Mail transport with response", response if response
                  notificationTarget = game.playerA
                  if game.whoseTurn == "B"
                    notificationTarget = game.playerB
                  new database.Notification
                    username: notificationTarget
                    text: "It's your turn in #{game.scenario.title}!"
                    action: "/game/#{game.id}"
                    image: "/avatar/#{req.user.name}"
                  .save (err) ->
                    console.log err if err
                  res.redirect "/game/" + game._id

      
  app.get "/games/world/active/", (req,res) ->
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
      res.redirect("/games/challenge/success")
  
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
        
  # automatically download entire game, specified by id
  # NOTE: "perma" does nothing except determining how the resulting file will
  # be called on the client side.
  app.get "/game/:id/:perma.zip", (req, res) -> 
    database.Game.findOne {_id: req.params.id}
      .populate "scenario"
      .select "scenario logs playerA playerB whoIsAttacker result started _id"
      .exec (err, game) ->
        return error.handle err if err
        unless game
          console.log "404 - "+req.path
          req.flash "error", "The game you requested does not exist."
          return res.redirect "/games"
        
        console.log "Packing game into ZIP"

        data = # data for JADE rendering goes here
          game: game
          date: moment().format("YYYY-MM-DD")
          errors: []
        zip = new ZIP()
        i = 1
        
        for log in game.logs
          inName = __dirname+"/pub/logfiles/#{req.params.id}/#{log.id}.vlog"
          # add trailing zeroes - will create problems when more than 999 logs
          # are in one match.
          # TODO figure something out
          num = ("00"+i).substr(0, 3)
          outName = "#{num}-#{getPhaseByID log.firstPhase}-to-#{getPhaseByID log.lastPhase}.vlog"
          
          # adm-zip does not offer standard node.js error handling
          try
            zip.addLocalFile inName, "", outName
          catch err
            console.log "404 - Failed to retrieve #{inName}"
            console.log err
            data.errors.push "The log file #{outName} is missing in this folder,
              it could not be retrieved due to a database error. Please contact
              the server admin to fix this error.\r\n\r\n"
            
          console.log "#{inName} -> #{outName}"
          i = i+1
            
        # add readme
        jade.renderFile "views/download/bulk.jade", data, (err, html) ->
          unless err
            zip.addFile "readme.html", new Buffer(html), ""
          else
            console.log err
            
          # ZIP created
          console.log "ZIP packed"
          res.set "Content-Type", "application/zip"
          res.send zip.toBuffer()          

getBulkFileName = (game) ->
  return game?.scenario?.title?.replace /\W*/g, ""
        

  
assembleData = (req,res) ->
  # assemble a bunch of data that pages can do stuff with
  {req: req, res: res}
  
  
getPhaseByID = (id, html) ->
  switch id
    when 1  
      a = "RPh"
      b = "blue"
    when 2  
      a = "PFPh"
      b = "orange"
    when 3 
      a = "MPh"
      b = "green"
    when 4 
      a = "DFPh"
      b = "violet"
    when 5 
      a = "AFPh"
      b = "orange"
    when 6 
      a = "RtPh"
      b = "black"
    when 7  
      a = "APh"
      b = "black"
    when 8  
      a = "CCPh"
      b = "red"
    else
      a = "???"
      b = "black"
      
  if html 
    return "<span style='color:"+b+"; font-weight: bold;'>"+a+"</span>"
  else
    return a

loadPlayersAndUpdateRatings = (nameA, nameB, aWon, done) ->
  database.User.findOne
    name: nameA
  .select "rating password" # not selecting password apparently causes crash
  .exec (err, userA) ->
    return done err if err
    return done new Error "No such user: "+nameA unless userA
    database.User.findOne
      name: nameB
    .select "rating password"
    .exec (err, userB) ->
      return done err if err
      return done new Error "No such user: "+nameB unless userB
      ratingAdjustments userA, userB, aWon, (err) ->
        done err

  
# aWon = true when player A won
ratingAdjustments = (playerA, playerB, aWon, done) ->
  # 1000 is default rating
  ratingA = playerA.rating?.points || 1000
  ratingB = playerB.rating?.points || 1000
  
  newRatingA = elo.newr ratingA, ratingB, aWon
  newRatingB = elo.newr ratingB, ratingA, !aWon
  
  console.log "Rating change: #{ratingA} to #{newRatingA}"
  console.log "Rating change: #{ratingB} to #{newRatingB}"
  
  playerA.rating.points = newRatingA
  playerA.rating.games = (playerA.rating.games || 0) + 1
  
  playerB.rating.points = newRatingB
  playerB.rating.games = (playerB.rating.games || 0) + 1
  
  playerA.save (err) ->
    playerB.save (err2) ->
      done err || err2
  
  