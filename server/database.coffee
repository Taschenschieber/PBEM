# Set up our database
exports.mongoose = mongoose = require "mongoose"
crypto = require "crypto"
db = mongoose.connection

db.on "error", console.error
db.once("open", () -> console.log("DB connection established."))

gameLogic = require "./games/logic.coffee"


mongoose.connect "mongodb://localhost/pbem"

message = new mongoose.Schema
  from: String
  to: String
  message: String
  sent:
    type: Date
    default: Date.now
  subject: String
  
exports.Message = Message = mongoose.model "Message", message
  
scenario = new mongoose.Schema
  number:
    type: String # because alphanumeric scenario IDs (SK, ASL classic, most TPPs)
    unique: true
    key: true
  title:
    type: String
    key: true
    unique: false
  attacker:
    nation:
      type: String # TODO figure out validation
  defender:
    nation:
      type: String
      
exports.Scenario = Scenario = mongoose.model "Scenario", scenario

# create an initial entry for debugging purposes if table is empty
Scenario.count {}, (err, result) ->
  console.log result, " scenarios in database"
  if result == 0
    new Scenario
      number: "A"
      title: "The Guards Counterattack"
      attacker:
        nation: "USSR"
      defender:
        nation: "Germany"
    .save (err) ->
      console.log err.message

exports.Game = gameLogic.Game
exports.Log = gameLogic.Log

challenge = new mongoose.Schema
  from: 
    type: String # the user the challenge is issued to
    index: true
  to: 
    type: String # the user the challenge is issued to
    index: true
  sent: 
    type: Date, default: Date.now
  timeControl: String # the time control mode. Probably best to define some constants somewhere.
  scenario: 
    type: String
    ref: "Scenario"
  dyo: Boolean
  message: String
  whoIsAttacker:
    type: String
    enum: ["A", "B"] # in keeping with Game, A is the sender and B is receiver
    # of the challenge
  
Challenge = mongoose.model "Challenge", challenge
exports.Challenge = Challenge  

notificationSchema = new mongoose.Schema
  username: 
    type: String
    index: true
  text: String
  action: String # url
  date: 
    type: Date, default: Date.now
  image: String
  
exports.Notification = Notification = mongoose.model "Notification", notificationSchema

userSchema = new mongoose.Schema
  name: 
    type: String
    index: true
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
    onKibitz:
      type: Boolean, default: false
  inbox: [message]
  outbox: [message]
  
  profile:
    # accounts on other platforms
    gamesquad: String
    thegeek: String
    facebook: String
    gplus: String
    twitter: String
    publicEmail: Boolean
    xmpp: String
  
  rating:
    points:
      type: Number
      default: 1000
    games: # used to determine if rating is provisional
      type: Number 
      default: 0
      
  
# encryption 

userSchema.pre "save", (next) ->
  user = this;  
  
  next() if not user.isModified "password"
  
  user.password = crypto.createHash("sha256").update(user.password).digest("base64")
  next()
      
# besides offering password validation, this does a couple of other checks as well.
userSchema.methods.comparePassword = (candidatePassword, cb) ->
  if crypto.createHash("sha256").update(candidatePassword).digest("base64") is this.password
    cb null, true
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