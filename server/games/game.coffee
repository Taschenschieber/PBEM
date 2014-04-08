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
auth = require "../auth"
common = require "../common"
config = require "../config"
database = require "../database"
email = require "../email"
error = require "../error"
logic = require "./logic"

exports.setupRoutes = (app) ->
  app.get "/games", (req,res) ->
    if req.user
      res.redirect "/games/me/active"
    else
      res.redirect "/games/all/active"
  
  app.get "/games/:name/:state", (req, res) ->
    res.redirect "/games/#{req.params.name}/#{req.params.state}/1"
  
  app.get "/games/:name/:state/:page", (req,res) ->
    data = assembleData req, res
    ipp = config.design.itemsPerPage
    start = (req.params.page-1)*ipp
    query = {}
    
    if req.params.name == "me"
      data.name = name = req.user?.name
      query.$or = [{playerA: name}, {playerB: name}] 
    else if req.params.name == "all"
      data.name = ""
    else if req.params.name == "watchlist"
      data.name = "watchlist"
      query.kibitzers = req.user?.id
      data.watchlist = true
    else
      data.name = name = req.params.name
      query.$or = [{playerA: name}, {playerB: name}] 
    
    data.state = "archived"
    unless (req.params.state == "archive" || data.watchlist)
      query["result"] = "ongoing"
      data.state = "active"

    database.Game.find query
    .populate "scenario"
    .select "_id playerA playerB scenario activePlayer whoIsAttacker whoseTurn result"
    .sort "-started" # todo sort by end date when looking at archived games
    .skip start
    .limit ipp
    .exec (err, games) ->
      res.send err if (err)
      
      data.games = games
      data.page = parseInt req.params.page
      data.pagesDisplayed = config.design.pagesDisplayed
      data.pagesBaseLink =  "/games/#{req.params.name}/#{req.params.state}/"
      database.Game.count query, (err, count) ->
        data.pages = Math.floor(count / ipp)+1
        res.render "games/list.jade", data    
  
  
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
      
      if req.user.name in [game.playerA, game.playerB]
        data.ownGame = true
      
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
          
          res.render "games/game.jade", data
          
  app.get "/game/:id/kibitz", auth.loggedIn, (req, res) ->
    database.Game.findOne
      _id: req.params.id
    .select "kibitzers"
    .exec (err, game) ->
      return error.handle err if err
      unless game
        console.log "Game not found: ", req.params.id
        req.flash "error", "The game you want to watch does not exist."
        return res.redirect "/game/#{req.params.id}"
      unless game.kibitzers
        game.kibitzers = []
      unless req.user.id in game.kibitzers
        game.kibitzers.push req.user.id
      
      game.save (err) ->
        return error.handle err if err
        req.flash "info", "You are now watching this game."
        res.redirect "/game/#{req.params.id}"
        
  app.get "/game/:id/unkibitz", auth.loggedIn, (req, res) ->
    database.Game.findOne
      _id: req.params.id
    .select "kibitzers"
    .exec (err, game) ->
      return error.handle err if err
      unless game
        console.log "Game not found: ", req.params.id
        req.flash "error", "The game you want to stop watching does not exist."
        return res.redirect "/game/#{req.params.id}"
      unless game.kibitzers
        game.kibitzers = []
      while req.user.id in game.kibitzers
        game.kibitzers.splice(game.kibitzers.indexOf(req.user.id), 1)
        
      game.save (err) ->
        return error.handle err if err
        req.flash "info", "You are no longer watching this game."
        res.redirect "/game/#{req.params.id}"

          
  app.get "/game/:id/resign", auth.loggedIn, (req, res) ->
    game = database.Game.findOne
      _id: req.params.id
    .exec (err, game) ->
      return error.handle err if err
      if not game
        req.flash "error", "The game you want to resign from does not exist."
        return res.redirect "/games"
      
      if req.user.name == game.playerA
        who = "A"
      else if req.user.name == game.playerB
        who = "B"
      else
        req.flash "error", "You are not a participant in this game!"
        return res.redirect "/game/#{req.params.id}"
      
      game.resign who, (err) ->
        if err
          req.flash "error", error.message
          res.redirect "/game/"+req.params.id
        game.save (err) ->
          if err
            req.flash "error", "There was an error while writing to the database."
          else
            req.flash "info", "You resigned from this game."
          
          res.redirect "/game/"+req.params.id
        
  app.get "/game/:id/upload", auth.loggedIn, (req,res) ->
    res.render "games/upload.jade", assembleData(req, res)
  
  app.post "/game/:id/upload/do", auth.loggedIn, (req,res) ->
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
          
        # the magic happens here 
        logic.addLog log, req.files?.logfile?.path, game, req.user, (err) ->
          if err
            return error.handle err
          req.flash "info", "Your log was successfully uploaded."
          res.redirect "/game/#{game.id}"
            
            
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
          num = ""+i
          while num.length < 3
            num = "0"+num
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
  