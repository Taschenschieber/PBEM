# Set up our database
exports.mongoose = mongoose = require "mongoose"
crypto = require "crypto"
db = mongoose.connection

db.on "error", console.error
db.once("open", () -> console.log("DB connection established."))

mongoose.connect "mongodb://localhost/pbem"

log = new mongoose.Schema
  sentBy: Boolean # true = Player A, false = Player B
  empty: Boolean # for these times when a player has no actions and 
                 # btys immediately
  date: # obvious
    type: Date, default: Date.now
  comment: String # a comment for the game
  
Log = mongoose.model "Log", log
exports.Log = Log

game = new mongoose.Schema
  playerA: String
  playerB: String
  kibitzers: [String] # list of usernames who watch the game
  started:
    type: Date, default: Date.now
  timeControl: String
  scenarioId: String # null if DYO
  active:
    type: Boolean, default: true # set to false once completed / aborted
  result:
    type: String
    default: "ongoing"
  logs: [Log.schema]
  
Game = mongoose.model "Game", game
exports.Game = Game

challenge = new mongoose.Schema
  from: String # the user the challenge is issued to
  to: String # the user the challenge is issued to
  sent: 
    type: Date, default: Date.now
  timeControl: String # the time control mode. Probably best to define some constants somewhere.
  scenarioId: String
  dyo: Boolean
  message: String
  
Challenge = mongoose.model "Challenge", challenge
exports.Challenge = Challenge  

notificationSchema = new mongoose.Schema
  username: String
  text: String
  action: String # url
  date: 
    type: Date, default: Date.now
  
Notification = mongoose.model "Notification", notificationSchema

userSchema = new mongoose.Schema
  name: String
  password: String
  email: String
  validationToken: 
    type: String
    default: crypto.randomBytes(32).toString "hex"
  activated: # was the e-mail confirmed yet?
    type: Boolean
    default: false
  banned:
    type: Boolean
    default: false
  notifications:
    onNewLog:
      type: Boolean, default: false
    onNewLogWithLog:
      type: Boolean, default: false
    onChallenge:
      type: Boolean, default: false
  
  
# encryption 

userSchema.pre "save", (next) ->
  user = this;  
  
  next() if not user.isModified "password"
  
  user.password = crypto.createHash("sha256").update(user.password).digest("base64")
  next()
      
# besides offering password validation, this does a couple of other checks as well.
userSchema.methods.comparePassword = (candidatePassword, cb) ->
  if user.banned
    return cb(new Error("You are banned!"), false)
  if not user.active
    return cb(new Error("Please validate your e-mail before your first log-in."), false)
  if crypto.createHash("sha256").update(candidatePassword).digest("base64") is this.password
    cb new Error("Invalid credentials!"), true
  else
    cb null, false

    
exports.User = User = mongoose.model "User", userSchema
exports.getUserByName = (name, done) ->
  User.findOne {name: name}, (err, user) ->
    done err, user
exports.createNotification = (username, message, action, done) ->
  notification = new Notification {
    username: username,
    text: message,
    action: action
  }
  notification.save (err) ->
    done err
exports.getNotifications = (username, done) ->
  console.log "Start to load notifications for ", username
  # show no more than 10 notifications, newest ones first
  Notification.find({username: username})
    .sort "-date"
    .limit 10
    .exec done
    
exports.getNotification = (id, done) ->
  Notification.find {_id: id}
    .exec done
    
exports.deleteNotification = (id, done) ->
  Notification.remove {_id: id}
    .exec done
        
exports.findChallengesFor = (userName, done) ->
  console.log "Find challenges for ", userName
  Challenge.find {to: userName}
    .sort "-date"
    .exec done
    
exports.findChallengesFrom = (userName, done) ->
  Challenge.find {from: userName}
    .sort "-date"
    .exec done