database = require "./database"

exports.populate = (req, res, next) ->
    console.log "Notifications.populate"
    if req.user?.name?
      # user is logged in - get his notifications and populate the reques with them
      database.getNotifications req.user.name, (err, notifications) -> 
        console.log "Notification loaded"
        req.user.notifications = notifications
        console.log notifications
        next()
    else
      # when logged out, no actions are to be taken
      next()