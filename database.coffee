# Set up our database
exports.mongoose = mongoose = require "mongoose"
crypto = require "crypto"
db = mongoose.connection

db.on "error", console.error
db.once("open", () -> console.log("DB connection established."))

mongoose.connect "mongodb://localhost/pbem"

challenge = new mongoose.Schema
  from: String # the user the challenge is issued to
  to: String # the user the challenge is issued to
  sent: 
    type: Date, default: Date.now
  timeControl: Number # the time control mode. Probably best to define some constants somewhere.
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
  password: String,
  email: String
  #challenges: [Challenge.schema]

# encryption 

userSchema.pre "save", (next) ->
  user = this;
  
  next() if not user.isModified "password"
  
  user.password = crypto.createHash("sha256").update(user.password).digest("base64")
  next()
      
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
  User.find {from: userName}
    .sort "-date"
    .exec done