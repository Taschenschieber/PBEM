PBEM
====

This project aims to develop a web platform for facilitating Play-by-E-Mail (PBeM) for VASSAL-based games, in particular matches of (Virtual) Advanced Squad Leader. The best wargame there is. Well, probably. I haven't got a clue about wargames, so don't take it from me.

Project goals
-------------

The first release will be considered feature complete once it has the following features:
* Possibility to search or directly challenge an opponent
* Uploaded logfiles will be permanently stored online, so you can just download an entire games from two years ago as a single ZIP file with neat, ordered files. No need to store gazillions of old e-mails anymore!
* Players will be automatically sent new log files via E-Mail and can submit new log files via E-Mail reply if they want to, so no additional work is required. Kibitzers will receive an E-Mail notification as well.
* Possibility to follow other players' games, with options for private games and games that are only published once they are done
* Extended time controls, allowing Tourney Directors (TDs) to determine which player stalled a game and should be forfeited for it
* Tourneys - Everybody can open a tourney, players can sign into tourneys via this platform, TDs can manage the tourney online (for example, enter the pairings for the next turn and games will automatically be created, players will be notified etc.), results are auto-reported to TDs

### Possible features down the line
* Generation of preview pictures for each log and possibility to skim through them in the browser
** would require permission to use artwork, though, and the VASSAL log format is rather obscure
* Automation of certain common tourney modes
* Other games than (V)ASL
** do require some work on central parts of the program, because more than two players are in the game

Technology
----------

This platform is written in CoffeeScript and based on node.js with the Express framework. HTML files are generated by JADE, client-side layout is provided by BootStrap. The database backend is MongoDB, with a possible change to MySQL down the line.
