# Task app checklist
- Recurring tasks
- Notifications [compromise](#compromise)

# TBD
# ntfy
https://github.com/binwiederhier/ntfy

# RIP had sync issues after a few weeks (unrecoverable phone state)
# Super Productivity
- lacks notifications

# Compromise
Use [tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm&hl=en_US) to open the task app every Nth time you unlock your phone. EG every 7th unlock run Anytype:
- Add var `%LastTaskOpen`
- Create Profile
- Add "Event" -> "Display" -> "Display Unlocked"
- Edit task
- Add "Action" -> "Alert" -> "Flash"
- Set text "Launching Anytype"
- Add if `%LastTaskOpen` ~ `0`
- Add "Action" -> "App" -> "Shortcut"
- From the page you want to see in Anytype (on desktop) click on ... in top right, go to advanced and select "Copy Deeplink"
- Set shortcut text to the copied deeplink. EG "anytype://object?objectId=XYZ"
- Add if `%LastTaskOpen` ~ `0`
- Add "Action" -> "Variables" -> "Variable Add"
- Set name `%LastTaskOpen`
- Add "Action" -> "Variables" -> "Variable Set"
- Set name `%LastTaskOpen`
- Set to `0`
- Add if `%LastTaskOpen` > `6`
