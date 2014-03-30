# (c) 2014 Stephan Hillebrand
#
# This file contains all logic for games and challenges that's actually related
# to game mechanics - i. e. handling of game turns / phases, winning / losing,
# ELO handling, flipping the turn marker whenever a game is uploaded.
#
# No routes are defined in this file.

fs = require "fs"
mkdirp = require "mkdirp"

database = require "../database"
email = require "../email"

mongoose = database.mongoose

log = new mongoose.Schema
  sentBy: String # the player who sent the log
  empty: Boolean # for these times when a player has no actions and 
                 # btys immediately
  date: # obvious
    type: Date, default: Date.now
  message: String # a comment for the game
  
  firstPhase: # 1 is RPh, 8 is CCPh
    type: Number
    default: 0
    
  lastPhase: # 1 is RPh, 8 is CCPh
    type: Number
    default: 0
    
  
Log = mongoose.model "Log", log
exports.Log = Log

game = new mongoose.Schema
  playerA: 
    type: String
    index: true
  playerB: 
    type: String
    index: true
  kibitzers: [String] # list of usernames who watch the game
  started:
    type: Date, default: Date.now
  timeControl: String
  scenario: 
    type: String 
    ref: "Scenario"
  active:
    type: Boolean, default: true # set to false once completed / aborted
  result:
    type: String
    default: "ongoing"
  logs: [Log.schema]
  whoseTurn: 
    type: String
    enum: ["A", "B", ""]
    default: ""
  whoIsAttacker:
    type: String
    enum: ["A", "B", ""]
    default: ""
    
  result:
    type: String
    enum: ["ongoing", "winA", "winB", "cancelled", "draw"]
    default: "ongoing"

game.methods.resign = (player) ->
  aWon
  if player == "A"
    aWon = false 
    result = "winB"
  else if player == "B"
    result = "winA"
    aWon = true
  else 
    return   
  loadPlayersAndUpdateRatings this.playerA, this.playerB, aWon, (err) ->
    if err 
      console.log "Could not update ratings"
      console.log err
  
  
exports.Game = Game = database.mongoose.model "Game", game



exports.getPhaseByID = (id, html) ->
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
      if html
        a = "???"
      else
        a = "xxx" # file name compatible
      b = "black"
      
  if html 
    return "<span style='color:"+b+"; font-weight: bold;'>"+a+"</span>"
  else
    return a

# Wrapper for ratingAdjustments - takes usernames instead of user objects
# as argument
exports.loadPlayersAndUpdateRatings = (nameA, nameB, aWon, done) ->
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

 
# Adjust ratings after a game was concluded 
# aWon = true when player A won
exports.ratingAdjustments = (playerA, playerB, aWon, done) ->
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
      
exports.addLog = (log, file, game, user, done) -> 
  unless log and game and file and user and done
    return done new Error "Illegal parameters"
      
  game.logs.push log
  previousPlayer = game.whoseTurn || "" # needed to revert after error
  if(user.name == game.playerA)
    game.whoseTurn = "B"
  else if (user.name == game.playerB)
    game.whoseTurn = "A"
  else
    return done new Error "User has no access rights."
  
  game.save (err) ->
    return done err if err
    console.log log._id
    path = "./pub/logfiles/#{game._id}/#{log._id}.vlog"
    console.log "Saving to: ", path
    console.log "Tempfile: ", file
    fs.readFile file, (err, data) ->
      return done err if err
      console.log "Making dir: ", "./pub/logfiles/"+game._id
      mkdirp "./pub/logfiles/"+game._id, (err) ->
        if err
          console.log "Reverting log upload due to an error:"
          console.log err
          if game.logs.indexOf log >= 0
            game.logs.splice(game.logs.indexOf(log), 1)
            
          game.whoseTurn = previousPlayer
          game.save (err) ->
            if err
              console.log "An error occured while adding a log file. An 
                additional error occured while reverting: "
              console.log err
          return done err
        fs.writeFile path, data, (err2) ->
          if err2
            # oh bollocks! Delete log from DB to ensure consistency
            # well... eventual consistency
            if game.logs.indexOf log >= 0
              game.logs.splice(game.logs.indexOf(log), 1)
              
            game.whoseTurn = previousPlayer
            game.save (err) ->
              console.log "An error occured while adding a log file. An 
                additional error occured while reverting: "
              console.log err
            return done err2
          else
            email.sendLogMail game, (err, response) ->
              console.log err if err
              console.log "Mail transport with response", response if response
            for kibitz in game.kibitzers
              email.sendKibitzMail game, user # fire&forget error handling
              new database.Notification
                username: kibitz
                text: "#{user.name} moved in #{game.scenario.title}."
                action: "/game/#{game.id}"
                image: "/user/#{user.name}/avatar/32"
              .save (err) -> console.log err if err
            notificationTarget = game.playerA
            if game.whoseTurn == "B"
              notificationTarget = game.playerB
            new database.Notification
              username: notificationTarget
              text: "It's your turn in #{game.scenario.title}!"
              action: "/game/#{game.id}"
              image: "/user/#{user.name}/avatar/32"
            .save (err) ->
              console.log err if err # non-blocking error
              
            done false
              
# Calculate new rating
exports.newElo = (own, opponent, won) ->
  Math.floor own + kFactor(own)*(won - exp(own, opponent)), 100
  # no rating lower than 100 should be possible
  
# Calculate rating expectation
exp = (own, opponent) ->
  1 / (1+Math.pow(10, (opponent - own) / 400))
  
# The kappa factor used for rating calculation
kFactor = (rating) ->
  32 # TODO: Choose more accurate model