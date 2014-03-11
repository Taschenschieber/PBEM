common = require "./common"
database = common.database

exports.setupRoutes = (app) ->
  #static pages
  app.get "/games", (req,res) -> res.render("listActiveGames.jade", assembleData(req,res))
  app.get "/games/challenge", (req,res) -> res.render("issueChallenge.jade", assembleData(req,res))
  app.get "/games/challenge/success", (req,res) -> res.render("challengeIssued.jade", assembleData(req,res))
  app.get "/games/my/challenges", (req,res) ->
    data = assembleData req,res
    # load challenges from database
    database.findChallengersFor req.user.name, (err, challengers) ->
      return res.redirect "/error" if err
      data.challengers = challengers || []
      database.findChallengesFrom req.user.name, (err, challenges) ->
        return res.redirect "/error" if err
        data.challenges = challenges
        res.render "challenges.jade", data
  
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
    
    console.log challenge
      
    # write to this user's account
    database.getUserByName challenge.from, (err, user) -> 
      if err || not user
        req.flash "error", "Could not read from database: " + err?.message?
        return res.redirect "/error"
      else
        user.challenges.push challenge
        user.save (err) ->
          if err
            req.flash "error", "Could not write to database: " + err?.message?
            return res.redirect "/error" 
          # saved the challenge - now, issue a notification to the challenged player
          database.createNotification challenge.to, "You have been challenged to a match!", "/games/my/challenges", (err) ->
            console.log(err || "Notification created")
            # all done... hopefully. Worry about asynchronous err handling later.
            # no error handling for notifications, it's not really worth it.
          res.redirect("/games/challenge/success")
  
assembleData = (req,res) ->
  # assemble a bunch of data that pages can do stuff with
  {req: req, res: res}