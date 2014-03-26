window.deleteNotifications = () ->

  $("#notifications-menu").html("<li class='dropdown-header'>No new notifications!</li>")
  $("#notifications-toggle").html("Notifications")
  
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
  
# autocomplete scenarios
window.scenario = () ->
  text = $("#scenario").val()
  if text
    $.ajax "/ajax/scenario/"+encodeURI(text)
      .done (results, status) ->
        console.log results # TODO reasonable handling here
        html = ""
        for result in results
          html += "<a href='javascript:window.selectScenario(\""+result.number+
            "\", \""+result.title+"\")'><strong>"+result.number+"</strong> - "+
            result.title+"</a>&nbsp;"
        
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
window.selectScenario = (number, title) ->
  $("#scenario").val(number + " - " + title)
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
  