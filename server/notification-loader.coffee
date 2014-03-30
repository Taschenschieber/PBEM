# (c) 2014 Stephan Hillebrand
#
# This file handles everything that has to do with notifications.
# Its most important function is the "populate" middleware, which populates
# the request with all notifications for the current user as well as 
# with data about important events that require the user's attention.
#
# Routes in this file:
# /notifications/:id - handle user click on a notification
# notifications/delete - delete all notifications for the current user

moment = require "moment"

database = require "./database"

exports.populate = (req, res, next) ->
    if req.user?.name?
      name = req.user.name
      # user is logged in - get his notifications and populate the request with them
      database.Notification.find
        $or: [
          username: req.user.name
        ,
          username: req.user._id
        ]
      .sort "-date"
      .limit "10"
      .exec (err, notifications) ->
        req.notifications = notifications

        # fancy dates
        for notification in notifications
          notification.fancyDate = moment(notification.date).fromNow()
        
        # load some other data as well - matches where it is this user's move,
        # open challenges and messages
        
        # TODO implement messages
        
        database.Game.count
          $and: [$or: [{playerA: name, whoseTurn: "A"}, {playerB: name, whoseTurn: "B"},
          {playerA: name, whoseTurn: ""}, {playerB: name, whoseTurn: ""}], result: "ongoing"]
        , (err, number) ->
          console.log err if err
          req.bullets = {}
          req.bullets.games = number || 0
          
          database.Challenge.count
            to: name
          , (err2, number2) ->
            console.log err2 if err2
            req.bullets.challenges = number2 || 0
            

            next()
    else
      # when logged out, no actions are to be taken
      next()

      
exports.setupRoutes = (app) ->
  # delete all notifications for current user. This is called by a script, no
  # reply is necessary
  app.get "/notifications/delete", (req,res) ->
    if req?.user?.name
      database.Notification.remove
        $or: [
          username: req.user.name
        ,
          username: req.user._id
        ]
      .exec (err) ->
        console.log err if err
        res.send ""
      

  # handle actions taken when user clicks on a notificaiton
  app.get "/notifications/:id", (req,res) ->
    database.getNotification req.params.id, (err, notification) ->
      if err || not notification?
        return res.send err || "Unknown error"
      action = notification.action || "#" # so it is accessible after deletion

      database.deleteNotification req.params.id, () ->
        return
      res.redirect action