window.deleteNotifications = () ->

  $("#notifications-menu").html("<li class='dropdown-header'>No new notifications!</li>")
  $("#notifications-toggle").html("<span class='glyphicon glyphicon-bullhorn' />")
  
  $.ajax({
    url: "/notifications/delete"
  })
  return

  
### 
  # handlers for events on challenge form
###
window.dyo = () ->
  if $("#dyo").is(":checked")
    $("#scenario").attr("disabled", "disabled")
  else
    $("#scenario").removeAttr("disabled")
  return
  
lastScenarios = []  
  
# autocomplete scenarios
window.scenario = () ->
  text = $("#scenarioText").val()
  if text
    $.ajax "/ajax/scenario/"+encodeURI(text)
      .done (results, status) ->
        console.log results # TODO reasonable handling here
        html = ""
        lastScenarios = results
        i = 0
        for result in results
          html += "
          <a href='javascript:window.selectScenario(#{i})'>
          <strong>#{result.number}</strong> - #{result.title}</a><br />
          "
          i = i + 1
        
        $("#scenario-area .suggestions").html(html)

# autocomplete opponents        
window.opponent = () ->
  text = $("#opponent").val()
  if text
    $.ajax "/ajax/user/"+encodeURI(text)
      .done (results, status) ->
        html = ""
        for result in results
          html += "<a href=\"javascript:window.selectUser('"+result.name+
            "');\">"+result.name+"</a>&nbsp;"
        $("#opponent-area .suggestions").html(html)
  

###
  #
###
window.selectScenario = (i) ->
  sc = lastScenarios[i]
  $("#scenarioText").val(sc.number + " - " + sc.title)
  $("input[name=scenario]").val sc._id
  $("option[value=A]").html (sc.attacker?.nation || "") + " (Attacker)"
  $("option[value=B]").html (sc.defender?.nation || "") + " (Defender)"
  return

window.selectUser = (user) ->
  $("#opponent").val(user)
  return # NOTE: Explicit "return" is necessary to prevent unwanted redirect
  
###
  #  tabbing
###
$("a[data-toggle='tab']").on "shown.bs.tab", (event) ->
  event.preventDefault
  $(event.target).tab("show")


# setup stuff
$(".help").tooltip();  