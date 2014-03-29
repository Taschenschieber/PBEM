# (c) 2014 Stephan Hillebrand
#
# This file acts as controller for all routes in /game and /games, except for
# those related to challenges. 
#
# There might be some restructuring soon to make paths more consistent.
#
# Routes defined in this file:
#

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
logic = require "./logic"

exports.setupRoutes = (app) ->
  app.get "/games", (req,res) -> res.redirect "/games/me/active"
  
  app.get "/games/:name/:state", (req,res) ->
    data = assembleData req, res
    query = {}
    
    if req.params.name == "me"
      data.name = name = req.user.name
      query.$or = [{playerA: name}, {playerB: name}] 
    else if req.params.name == "all"
      data.name = ""
    else
      data.name = name = req.params.name
      query.$or = [{playerA: name}, {playerB: name}] 
    
    data.state = "archived"
    unless req.params.state == "archive"
      query["result"] = "ongoing"
      data.state = "active"

    console.log query
    database.Game.find query
    .populate "scenario"
    .select "_id playerA playerB scenario activePlayer whoIsAttacker whoseTurn result"
    .exec (err, games) ->
      console.log games
      res.send err if (err)
      
      data.games = games
      res.render "games/list.jade", data
  
  app.get "/games/:name/archive", (req, res) ->
    
  
  
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
        log.prettyFirstPhase = logic.getPhaseByID log.firstPhase, true
        log.prettyLastPhase = logic.getPhaseByID log.lastPhase, true
      
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
      
      if req.user.name == game.playerA
        game.resign "A"
      else if req.user.name == game.playerB
        game.resign "B"
      else
        req.flash "error", "You are not a participant in this game!"
        return res.redirect "/game/#{req.params.id}"
        
      game.save (err) ->
        if err
          req.flash "error", "There was an error while writing to the database."
        else
          req.flash "info", "You resigned from this game."
        
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
    
    # TODO move this to logic
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
          path = "./pub/logfiles/#{game._id}/#{log._id}.vlog"
          console.log "Saving to: ", path
          console.log "Tempfile: ", req.files.logfile.path
          fs.readFile req.files.logfile.path, (err, data) ->
            return res.send err if err
            console.log "Making dir: ", "./pub/logfiles/"+game._id
            mkdirp "./pub/logfiles/"+game._id, (err) ->
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
          inName = "./pub/logfiles/#{req.params.id}/#{log.id}.vlog"
          # add trailing zeroes - will create problems when more than 999 logs
          # are in one match.
          # TODO figure something out
          num = ("00"+i).substr(0, 3)
          outName = "#{num}-#{logic.getPhaseByID log.firstPhase}-to-#{logic.getPhaseByID log.lastPhase}.vlog"
          
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
  