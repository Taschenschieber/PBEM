database = require "./database"

exports.populate = (req, res, next) ->
    console.log "Notifications.populate"
    if req.user?.name?
      name = req.user.name
      # user is logged in - get his notifications and populate the reques with them
      database.getNotifications req.user.name, (err, notifications) -> 
        req.notifications = notifications

        # load some other data as well - matches where it is this user's move,
        # open challenges and messages
        
        # TODO implement messages
        
        database.Game.count
          $and: [
            $or: [{playerA: name, whoseTurn: "a"}, {playerB: name, whoseTurn: "b"},
            {playerA: name, whoseTurn: ""}, {playerB: name, whoseTurn: ""}]
          ]
        , (err, number) ->
          console.log err if err
          req.bullets = {}
          req.bullets.games = number || 0
          
          database.Challenge.count
            to: name
          , (err2, number2) ->
            console.log err2 if err2
            req.bullets.challenges = number || 0
            

            next()
    else
      # when logged out, no actions are to be taken
      next()