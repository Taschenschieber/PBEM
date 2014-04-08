csv = require "csv"
fs = require "fs"
database = require "../server/database"
Scenario = database.Scenario

Scenario.remove()

csv = csv().from.path(__dirname+"/scenarios.csv")
.on "record", (row, index) ->
    number = baseNumber = row[4]
    title = row[3]
    console.log title
    
    if not number?.trim()?
      "Scenario "+title+" has no number. Skipping."
      return
        
    # write to DB
    sc = new Scenario
      title: title
      number: number
      defender:
        nation: row[7]
      attacker:
        nation: row[8]
    
    sc.save (err) ->
      if err
        "Scenario "+number+" "+title+" has been skipped."
.on "end", (count) ->
  console.log count+" scenarios processed."
  Scenario.count (err, count2) ->
    count2+" scenarios currently in db."
    process.exit(0)
  
###
  findAlternativeNumber = (number, alternative, callback) ->
    add = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if alternative > 25
      console.log "Too many duplicates. Cancelling. Check input."
      process.exit(1)

    if alternative >= 0
      newNumber = number + "(" + add.charAt(alternative) + ")"
    else newNumber = number
    
    Scenario.findOne
      number: newNumber
    .exec (err, duplicate) ->
      if err
        console.log err
        console.log "An error occured. Cancelling."
        process.exit(1)

      if duplicate
        console.log number+" is already taken as a number."
        findAlternativeNumber number, alternative+1, callback
      else
        callback newNumber
###